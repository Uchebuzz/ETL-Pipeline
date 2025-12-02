"""
ETL Pipeline for Financial Data Processing
Ingests data from S3/local, transforms it, and stores as Parquet in S3
"""

import os
import logging
import boto3
from datetime import datetime
from typing import Optional
from pyspark.sql import SparkSession
from pyspark.sql.functions import col, when, to_date, year, month, sum as spark_sum, avg, count
from pyspark.sql.types import StructType, StructField, StringType, DoubleType, DateType, IntegerType

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# CloudWatch logging setup
try:
    import watchtower
    handler = watchtower.CloudWatchLogHandler(
        log_group=os.getenv('CLOUDWATCH_LOG_GROUP', 'etl-pipeline'),
        stream_name=f"etl-{datetime.now().strftime('%Y-%m-%d')}"
    )
    logger.addHandler(handler)
    logger.info("CloudWatch logging enabled")
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
        self.spark = None
        self.s3_client = None
        
    def initialize_spark(self):
        """Initialize Spark session with S3 support"""
        logger.info("Initializing Spark session...")
        
        spark_builder = SparkSession.builder \
            .appName("FinancialETLPipeline") \
            .config("spark.sql.adaptive.enabled", "true") \
            .config("spark.sql.adaptive.coalescePartitions.enabled", "true")
        
        # Configure S3 access
        aws_access_key = os.getenv('AWS_ACCESS_KEY_ID')
        aws_secret_key = os.getenv('AWS_SECRET_ACCESS_KEY')
        
        if aws_access_key and aws_secret_key:
            spark_builder.config("spark.hadoop.fs.s3a.access.key", aws_access_key) \
                .config("spark.hadoop.fs.s3a.secret.key", aws_secret_key) \
                .config("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem") \
                .config("spark.hadoop.fs.s3a.aws.credentials.provider", 
                       "org.apache.hadoop.fs.s3a.SimpleAWSCredentialsProvider")
        
        self.spark = spark_builder.getOrCreate()
        logger.info("Spark session initialized successfully")
        
        # Initialize S3 client
        self.s3_client = boto3.client('s3', region_name=self.aws_region)
        
    def extract(self) -> Optional:
        """
        Extract data from source (S3 or local)
        
        Returns:
            Spark DataFrame
        """
        logger.info(f"Extracting data from {self.source_path}...")
        
        try:
            if self.source_type == 's3':
                # Read from S3
                df = self.spark.read \
                    .option("header", "true") \
                    .option("inferSchema", "true") \
                    .csv(self.source_path)
            else:
                # Read from local filesystem
                if self.source_path.endswith('.json'):
                    df = self.spark.read \
                        .option("multiline", "true") \
                        .json(self.source_path)
                else:
                    df = self.spark.read \
                        .option("header", "true") \
                        .option("inferSchema", "true") \
                        .csv(self.source_path)
            
            logger.info(f"Successfully extracted {df.count()} records")
            return df
            
        except Exception as e:
            logger.error(f"Error during extraction: {str(e)}")
            raise
    
    def transform(self, df):
        """
        Transform the financial data
        
        Args:
            df: Input Spark DataFrame
            
        Returns:
            Transformed Spark DataFrame
        """
        logger.info("Starting data transformation...")
        
        try:
            # Clean and standardize column names
            df = df.select([col(c).alias(c.lower().replace(' ', '_').replace('-', '_')) 
                           for c in df.columns])
            
            # Data cleaning and enrichment
            # Convert date columns if they exist
            date_columns = [c for c in df.columns if 'date' in c.lower()]
            for date_col in date_columns:
                df = df.withColumn(date_col, to_date(col(date_col), "yyyy-MM-dd"))
            
            # Add processing metadata
            df = df.withColumn("processed_date", 
                             when(col("processed_date").isNull(), 
                                 datetime.now().strftime("%Y-%m-%d")).otherwise(col("processed_date")))
            
            # If transaction amount exists, calculate aggregates
            amount_columns = [c for c in df.columns if 'amount' in c.lower() or 'value' in c.lower()]
            
            if amount_columns:
                # Add year and month for partitioning
                if date_columns:
                    df = df.withColumn("year", year(col(date_columns[0]))) \
                           .withColumn("month", month(col(date_columns[0])))
                
                # Data quality checks
                df = df.filter(col(amount_columns[0]).isNotNull())
            
            # Remove duplicates
            df = df.dropDuplicates()
            
            logger.info(f"Transformation complete. Records after transformation: {df.count()}")
            return df
            
        except Exception as e:
            logger.error(f"Error during transformation: {str(e)}")
            raise
    
    def load(self, df, output_prefix: str = "processed_data"):
        """
        Load transformed data to S3 as Parquet
        
        Args:
            df: Transformed Spark DataFrame
            output_prefix: S3 prefix for output files
        """
        logger.info(f"Loading data to s3://{self.destination_bucket}/{output_prefix}...")
        
        try:
            # Create S3 output path
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            s3_output_path = f"s3a://{self.destination_bucket}/{output_prefix}/date={timestamp}"
            
            # Write as Parquet with partitioning
            df.write \
                .mode("overwrite") \
                .option("compression", "snappy") \
                .parquet(s3_output_path)
            
            logger.info(f"Successfully loaded data to {s3_output_path}")
            
            # Log metrics
            record_count = df.count()
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
            
            # Initialize Spark
            self.initialize_spark()
            
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
        finally:
            if self.spark:
                self.spark.stop()
                logger.info("Spark session closed")


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

