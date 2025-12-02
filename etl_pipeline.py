"""
ETL Pipeline for Financial Data Processing
Ingests data from S3/local, transforms it, and stores as Parquet in S3
"""

import os
import logging
import boto3
import pandas as pd
import pyarrow.parquet as pq
import pyarrow as pa
from datetime import datetime
from typing import Optional
from io import BytesIO, StringIO

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# CloudWatch logging setup
try:
    import watchtower
    cloudwatch_enabled = os.getenv('CLOUDWATCH_ENABLED', 'true').lower() == 'true'
    if cloudwatch_enabled:
        try:
            handler = watchtower.CloudWatchLogHandler(
                log_group=os.getenv('CLOUDWATCH_LOG_GROUP', '/aws/lambda/etl-pipeline'),
                stream_name=f"etl-{datetime.now().strftime('%Y-%m-%d')}"
            )
            logger.addHandler(handler)
            logger.info("CloudWatch logging enabled")
        except Exception as e:
            logger.warning(f"CloudWatch logging setup failed: {str(e)}. Using standard logging.")
    else:
        logger.info("CloudWatch logging disabled")
except ImportError:
    logger.warning("watchtower not installed, using standard logging")


class ETLPipeline:
    """Main ETL Pipeline class"""
    
    def __init__(self, source_path: str, destination_bucket: str, 
                 source_type: str = 's3', aws_region: str = 'us-east-1'):
        """
        Initialize ETL Pipeline
        
        Args:
            source_path: Path to source data (S3 URI or local path)
            destination_bucket: S3 bucket for output
            source_type: 's3' or 'local'
            aws_region: AWS region
        """
        self.source_path = source_path
        self.destination_bucket = destination_bucket
        self.source_type = source_type
        self.aws_region = aws_region
        self.s3_client = None
        
    def initialize_s3_client(self):
        """Initialize S3 client"""
        logger.info("Initializing S3 client...")
        self.s3_client = boto3.client('s3', region_name=self.aws_region)
        logger.info("S3 client initialized successfully")
        
    def extract(self) -> Optional[pd.DataFrame]:
        """
        Extract data from source (S3 or local)
        
        Returns:
            Pandas DataFrame
        """
        logger.info(f"Extracting data from {self.source_path}...")
        
        try:
            if self.source_type == 's3':
                # Parse S3 URI
                if not self.s3_client:
                    self.initialize_s3_client()
                
                # Extract bucket and key from S3 URI
                s3_path = self.source_path.replace('s3://', '')
                bucket, key = s3_path.split('/', 1) if '/' in s3_path else (s3_path, '')
                
                # Read from S3
                logger.info(f"Reading from s3://{bucket}/{key}")
                obj = self.s3_client.get_object(Bucket=bucket, Key=key)
                
                if key.endswith('.json'):
                    df = pd.read_json(BytesIO(obj['Body'].read()))
                else:
                    df = pd.read_csv(BytesIO(obj['Body'].read()))
            else:
                # Read from local filesystem
                if self.source_path.endswith('.json'):
                    df = pd.read_json(self.source_path)
                else:
                    df = pd.read_csv(self.source_path)
            
            logger.info(f"Successfully extracted {len(df)} records")
            return df
            
        except Exception as e:
            logger.error(f"Error during extraction: {str(e)}")
            raise
    
    def transform(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Transform the financial data
        
        Args:
            df: Input Pandas DataFrame
            
        Returns:
            Transformed Pandas DataFrame
        """
        logger.info("Starting data transformation...")
        
        try:
            # Clean and standardize column names
            df.columns = df.columns.str.lower().str.replace(' ', '_').str.replace('-', '_')
            
            # Data cleaning and enrichment
            # Convert date columns if they exist
            date_columns = [c for c in df.columns if 'date' in c.lower()]
            for date_col in date_columns:
                df[date_col] = pd.to_datetime(df[date_col], format='%Y-%m-%d', errors='coerce')
            
            # Add processing metadata
            if 'processed_date' not in df.columns:
                df['processed_date'] = datetime.now().strftime("%Y-%m-%d")
            else:
                df['processed_date'] = df['processed_date'].fillna(datetime.now().strftime("%Y-%m-%d"))
            
            # If transaction amount exists, calculate aggregates
            amount_columns = [c for c in df.columns if 'amount' in c.lower() or 'value' in c.lower()]
            
            if amount_columns:
                # Add year and month for partitioning
                if date_columns:
                    df['year'] = pd.to_datetime(df[date_columns[0]]).dt.year
                    df['month'] = pd.to_datetime(df[date_columns[0]]).dt.month
                
                # Data quality checks - remove rows with null amounts
                df = df[df[amount_columns[0]].notna()]
            
            # Remove duplicates
            df = df.drop_duplicates()
            
            logger.info(f"Transformation complete. Records after transformation: {len(df)}")
            return df
            
        except Exception as e:
            logger.error(f"Error during transformation: {str(e)}")
            raise
    
    def load(self, df: pd.DataFrame, output_prefix: str = "processed_data"):
        """
        Load transformed data to S3 as Parquet
        
        Args:
            df: Transformed Pandas DataFrame
            output_prefix: S3 prefix for output files
        """
        logger.info(f"Loading data to s3://{self.destination_bucket}/{output_prefix}...")
        
        try:
            if not self.s3_client:
                self.initialize_s3_client()
            
            # Create S3 output path
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            s3_key = f"{output_prefix}/date={timestamp}/data.parquet"
            
            # Convert DataFrame to Parquet in memory
            parquet_buffer = BytesIO()
            table = pa.Table.from_pandas(df)
            pq.write_table(table, parquet_buffer, compression='snappy')
            parquet_buffer.seek(0)
            
            # Upload to S3
            self.s3_client.put_object(
                Bucket=self.destination_bucket,
                Key=s3_key,
                Body=parquet_buffer.getvalue()
            )
            
            s3_output_path = f"s3://{self.destination_bucket}/{s3_key}"
            logger.info(f"Successfully loaded data to {s3_output_path}")
            
            # Log metrics
            record_count = len(df)
            logger.info(f"Total records loaded: {record_count}")
            
            return s3_output_path
            
        except Exception as e:
            logger.error(f"Error during load: {str(e)}")
            raise
    
    def run(self, output_prefix: str = "processed_data"):
        """
        Execute the complete ETL pipeline
        
        Args:
            output_prefix: S3 prefix for output files
        """
        try:
            logger.info("=" * 50)
            logger.info("Starting ETL Pipeline Execution")
            logger.info("=" * 50)
            
            # Initialize S3 client
            self.initialize_s3_client()
            
            # Extract
            df = self.extract()
            
            # Transform
            df_transformed = self.transform(df)
            
            # Load
            output_path = self.load(df_transformed, output_prefix)
            
            logger.info("=" * 50)
            logger.info("ETL Pipeline Execution Completed Successfully")
            logger.info("=" * 50)
            
            return output_path
            
        except Exception as e:
            logger.error(f"ETL Pipeline failed: {str(e)}")
            raise


def main():
    """Main entry point"""
    # Get configuration from environment variables
    source_path = os.getenv('SOURCE_PATH', 'data/sample_financial_data.csv')
    destination_bucket = os.getenv('DESTINATION_BUCKET', 'etl-pipeline-output')
    source_type = os.getenv('SOURCE_TYPE', 'local')  # 's3' or 'local'
    aws_region = os.getenv('AWS_REGION', 'us-east-1')
    output_prefix = os.getenv('OUTPUT_PREFIX', 'processed_data')
    
    # Validate required environment variables
    if source_type == 's3':
        if not os.getenv('AWS_ACCESS_KEY_ID') or not os.getenv('AWS_SECRET_ACCESS_KEY'):
            logger.warning("AWS credentials not found in environment variables")
    
    # Create and run pipeline
    pipeline = ETLPipeline(
        source_path=source_path,
        destination_bucket=destination_bucket,
        source_type=source_type,
        aws_region=aws_region
    )
    
    pipeline.run(output_prefix=output_prefix)


if __name__ == "__main__":
    main()
