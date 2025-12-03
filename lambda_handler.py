"""
Lambda handler for S3-triggered ETL pipeline
Triggers AWS Glue job when a CSV or JSON file is uploaded to the source S3 bucket
"""

import json
import os
import logging
import boto3

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)


def lambda_handler(event, context):
    """
    Lambda handler for S3 event-triggered ETL pipeline
    Triggers AWS Glue job instead of running ETL directly
    
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
        
        # Get configuration from environment variables
        glue_job_name = os.getenv('GLUE_JOB_NAME')
        destination_bucket = os.getenv('DESTINATION_BUCKET')
        output_prefix = os.getenv('OUTPUT_PREFIX', 'processed_data')
        aws_region = os.getenv('AWS_REGION', 'us-east-1')
        
        if not glue_job_name:
            logger.error("GLUE_JOB_NAME environment variable not set")
            return {
                'statusCode': 500,
                'body': json.dumps('GLUE_JOB_NAME not configured')
            }
        
        if not destination_bucket:
            logger.error("DESTINATION_BUCKET environment variable not set")
            return {
                'statusCode': 500,
                'body': json.dumps('DESTINATION_BUCKET not configured')
            }
        
        # Initialize Glue client
        glue_client = boto3.client('glue', region_name=aws_region)
        
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
            
            # Only process CSV or JSON files
            if not (object_key.lower().endswith('.csv') or object_key.lower().endswith('.json')):
                logger.info(f"Skipping unsupported file type: {object_key}")
                continue
            
            logger.info(f"Triggering Glue job for file: s3://{bucket_name}/{object_key}")
            
            # Prepare job arguments
            job_arguments = {
                '--source_bucket': bucket_name,
                '--source_key': object_key,
                '--destination_bucket': destination_bucket,
                '--output_prefix': output_prefix
            }
            
            try:
                # Start Glue job
                response = glue_client.start_job_run(
                    JobName=glue_job_name,
                    Arguments=job_arguments
                )
                
                job_run_id = response['JobRunId']
                logger.info(f"Started Glue job run: {job_run_id} for {object_key}")
                
                results.append({
                    'source': f"s3://{bucket_name}/{object_key}",
                    'glue_job_name': glue_job_name,
                    'job_run_id': job_run_id,
                    'status': 'triggered'
                })
                
            except Exception as e:
                logger.error(f"Error triggering Glue job for {object_key}: {str(e)}")
                results.append({
                    'source': f"s3://{bucket_name}/{object_key}",
                    'status': 'error',
                    'error': str(e)
                })
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Glue jobs triggered successfully',
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

