"""
Lambda handler for S3-triggered ETL pipeline
Triggers when a CSV file is uploaded to the source S3 bucket
"""

import json
import os
import logging
import boto3
from etl_pipeline import ETLPipeline

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)


def lambda_handler(event, context):
    """
    Lambda handler for S3 event-triggered ETL pipeline
    
    Args:
        event: S3 event containing bucket and object information
        context: Lambda context
    
    Returns:
        Response dictionary
    """
    try:
        logger.info(f"Received event: {json.dumps(event)}")
        
        # Extract S3 event information
        records = event.get('Records', [])
        if not records:
            logger.warning("No records found in event")
            return {
                'statusCode': 400,
                'body': json.dumps('No records in event')
            }
        
        # Process each S3 event record
        results = []
        for record in records:
            if record.get('eventSource') != 'aws:s3':
                logger.warning(f"Skipping non-S3 event: {record.get('eventSource')}")
                continue
            
            s3_event = record.get('s3', {})
            bucket_name = s3_event.get('bucket', {}).get('name')
            object_key = s3_event.get('object', {}).get('key')
            
            if not bucket_name or not object_key:
                logger.error("Missing bucket name or object key in S3 event")
                continue
            
            # Only process CSV files
            if not object_key.lower().endswith('.csv'):
                logger.info(f"Skipping non-CSV file: {object_key}")
                continue
            
            logger.info(f"Processing file: s3://{bucket_name}/{object_key}")
            
            # Get configuration from environment variables
            destination_bucket = os.getenv('DESTINATION_BUCKET')
            if not destination_bucket:
                logger.error("DESTINATION_BUCKET environment variable not set")
                return {
                    'statusCode': 500,
                    'body': json.dumps('DESTINATION_BUCKET not configured')
                }
            
            aws_region = os.getenv('AWS_REGION', 'us-east-1')
            output_prefix = os.getenv('OUTPUT_PREFIX', 'processed_data')
            
            # Construct S3 URI
            source_path = f"s3://{bucket_name}/{object_key}"
            
            # Create and run ETL pipeline
            pipeline = ETLPipeline(
                source_path=source_path,
                destination_bucket=destination_bucket,
                source_type='s3',
                aws_region=aws_region
            )
            
            try:
                output_path = pipeline.run(output_prefix=output_prefix)
                results.append({
                    'source': source_path,
                    'destination': output_path,
                    'status': 'success'
                })
                logger.info(f"Successfully processed {source_path} -> {output_path}")
            except Exception as e:
                logger.error(f"Error processing {source_path}: {str(e)}")
                results.append({
                    'source': source_path,
                    'status': 'error',
                    'error': str(e)
                })
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'ETL pipeline execution completed',
                'results': results
            })
        }
        
    except Exception as e:
        logger.error(f"Lambda handler error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }

