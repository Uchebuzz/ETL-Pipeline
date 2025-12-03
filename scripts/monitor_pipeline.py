#!/usr/bin/env python3
"""
Monitor ETL Pipeline execution
Checks Lambda logs, Glue job status, and S3 output files
Usage: python scripts/monitor_pipeline.py [--lambda-name NAME] [--glue-job NAME] [--dest-bucket NAME]
"""

import argparse
import boto3
import json
import os
from datetime import datetime, timedelta
from botocore.exceptions import ClientError


def get_lambda_logs(lambda_name: str, region: str, hours: int = 1):
    """Get recent Lambda function logs from CloudWatch"""
    print(f"\n{'='*60}")
    print(f"📋 Lambda Function: {lambda_name}")
    print(f"{'='*60}")
    
    logs_client = boto3.client('logs', region_name=region)
    lambda_client = boto3.client('lambda', region_name=region)
    
    try:
        # Get function details
        func_info = lambda_client.get_function(FunctionName=lambda_name)
        print(f"✓ Lambda function found")
        print(f"  Runtime: {func_info['Configuration']['Runtime']}")
        print(f"  Last Modified: {func_info['Configuration']['LastModified']}")
        
        # Get log group name
        log_group = f"/aws/lambda/{lambda_name}"
        
        # Get recent log streams
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(hours=hours)
        
        try:
            streams = logs_client.describe_log_streams(
                logGroupName=log_group,
                orderBy='LastEventTime',
                descending=True,
                limit=5
            )
            
            if not streams.get('logStreams'):
                print(f"\n⚠ No log streams found in {log_group}")
                print("  This might mean:")
                print("  - Lambda hasn't been triggered yet")
                print("  - Logs haven't been created")
                return
            
            print(f"\n📊 Recent Log Streams:")
            for stream in streams['logStreams']:
                print(f"  - {stream['logStreamName']}")
                print(f"    Last Event: {datetime.fromtimestamp(stream['lastEventTimestamp']/1000)}")
            
            # Get logs from most recent stream
            latest_stream = streams['logStreams'][0]['logStreamName']
            print(f"\n📝 Latest Logs from '{latest_stream}':")
            print("-" * 60)
            
            events = logs_client.get_log_events(
                logGroupName=log_group,
                logStreamName=latest_stream,
                startTime=int(start_time.timestamp() * 1000),
                limit=50
            )
            
            if events.get('events'):
                for event in events['events']:
                    timestamp = datetime.fromtimestamp(event['timestamp']/1000)
                    message = event['message'].strip()
                    print(f"[{timestamp}] {message}")
            else:
                print("  No recent events found")
                
        except ClientError as e:
            if e.response['Error']['Code'] == 'ResourceNotFoundException':
                print(f"\n⚠ Log group {log_group} not found")
                print("  Lambda may not have been invoked yet")
            else:
                print(f"\n❌ Error getting logs: {e}")
                
    except ClientError as e:
        print(f"❌ Error: {e}")


def get_glue_job_status(glue_job_name: str, region: str):
    """Get Glue job run status"""
    print(f"\n{'='*60}")
    print(f"🔧 Glue Job: {glue_job_name}")
    print(f"{'='*60}")
    
    glue_client = boto3.client('glue', region_name=region)
    
    try:
        # Get job details
        job_info = glue_client.get_job(JobName=glue_job_name)
        print(f"✓ Glue job found")
        print(f"  Glue Version: {job_info['Job']['GlueVersion']}")
        print(f"  Worker Type: {job_info['Job']['Command']['Name']}")
        
        # Get recent job runs
        runs = glue_client.get_job_runs(
            JobName=glue_job_name,
            MaxResults=5
        )
        
        if not runs.get('JobRuns'):
            print(f"\n⚠ No job runs found")
            print("  Job hasn't been triggered yet")
            return
        
        print(f"\n📊 Recent Job Runs:")
        print("-" * 60)
        
        for run in runs['JobRuns']:
            status = run['JobRunState']
            status_icon = "✅" if status == "SUCCEEDED" else "❌" if status == "FAILED" else "⏳"
            
            print(f"\n{status_icon} Run ID: {run['Id']}")
            print(f"   Status: {status}")
            print(f"   Started: {run.get('StartedOn', 'N/A')}")
            print(f"   Completed: {run.get('CompletedOn', 'In Progress...')}")
            
            if 'ErrorMessage' in run:
                print(f"   Error: {run['ErrorMessage']}")
            
            if 'Arguments' in run:
                print(f"   Arguments: {json.dumps(run['Arguments'], indent=6)}")
        
        # Get latest run details
        latest_run = runs['JobRuns'][0]
        if latest_run['JobRunState'] == 'RUNNING':
            print(f"\n⏳ Latest job is still running...")
        elif latest_run['JobRunState'] == 'SUCCEEDED':
            print(f"\n✅ Latest job completed successfully!")
        elif latest_run['JobRunState'] == 'FAILED':
            print(f"\n❌ Latest job failed!")
            if 'ErrorMessage' in latest_run:
                print(f"   Error: {latest_run['ErrorMessage']}")
        
    except ClientError as e:
        print(f"❌ Error: {e}")


def check_s3_output(dest_bucket: str, region: str, prefix: str = "processed_data"):
    """Check S3 bucket for processed output files"""
    print(f"\n{'='*60}")
    print(f"📦 Destination Bucket: {dest_bucket}")
    print(f"{'='*60}")
    
    s3_client = boto3.client('s3', region_name=region)
    
    try:
        # Check if bucket exists
        s3_client.head_bucket(Bucket=dest_bucket)
        print(f"✓ Bucket exists")
        
        # List objects in processed_data prefix
        print(f"\n📁 Files in '{prefix}/' prefix:")
        print("-" * 60)
        
        paginator = s3_client.get_paginator('list_objects_v2')
        pages = paginator.paginate(Bucket=dest_bucket, Prefix=prefix)
        
        file_count = 0
        total_size = 0
        
        for page in pages:
            if 'Contents' in page:
                for obj in page['Contents']:
                    file_count += 1
                    size = obj['Size']
                    total_size += size
                    modified = obj['LastModified']
                    key = obj['Key']
                    
                    size_mb = size / (1024 * 1024)
                    print(f"  📄 {key}")
                    print(f"     Size: {size_mb:.2f} MB | Modified: {modified}")
        
        if file_count == 0:
            print(f"  ⚠ No files found in '{prefix}/'")
            print("  This might mean:")
            print("  - Glue job hasn't completed yet")
            print("  - Glue job failed")
            print("  - Output prefix is different")
        else:
            total_mb = total_size / (1024 * 1024)
            print(f"\n✓ Found {file_count} file(s), Total: {total_mb:.2f} MB")
        
    except ClientError as e:
        if e.response['Error']['Code'] == '404':
            print(f"❌ Bucket '{dest_bucket}' not found")
        else:
            print(f"❌ Error: {e}")


def get_terraform_outputs():
    """Try to get resource names from terraform outputs"""
    import subprocess
    
    terraform_dir = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'terraform')
    
    if not os.path.exists(terraform_dir):
        return None
    
    outputs = {}
    try:
        result = subprocess.run(
            ['terraform', 'output', '-json'],
            cwd=terraform_dir,
            capture_output=True,
            text=True,
            timeout=10
        )
        
        if result.returncode == 0:
            data = json.loads(result.stdout)
            outputs = {
                'lambda_name': data.get('lambda_function_name', {}).get('value'),
                'glue_job': data.get('glue_job_name', {}).get('value'),
                'dest_bucket': data.get('destination_bucket_name', {}).get('value'),
                'region': data.get('aws_region', {}).get('value')
            }
            return outputs
    except Exception:
        pass
    
    return None


def main():
    parser = argparse.ArgumentParser(description='Monitor ETL Pipeline execution')
    parser.add_argument('--lambda-name', help='Lambda function name')
    parser.add_argument('--glue-job', help='Glue job name')
    parser.add_argument('--dest-bucket', help='Destination S3 bucket name')
    parser.add_argument('--region', help='AWS region (default: from AWS_REGION env or terraform)')
    parser.add_argument('--hours', type=int, default=1, help='Hours of logs to retrieve (default: 1)')
    parser.add_argument('--prefix', default='processed_data', help='S3 output prefix (default: processed_data)')
    
    args = parser.parse_args()
    
    # Try to get from terraform outputs if not provided
    tf_outputs = get_terraform_outputs()
    
    lambda_name = args.lambda_name or (tf_outputs and tf_outputs.get('lambda_name'))
    glue_job = args.glue_job or (tf_outputs and tf_outputs.get('glue_job'))
    dest_bucket = args.dest_bucket or (tf_outputs and tf_outputs.get('dest_bucket'))
    region = args.region or (tf_outputs and tf_outputs.get('region')) or os.environ.get('AWS_REGION') or 'us-east-1'
    
    if not lambda_name:
        print("⚠ Lambda function name not provided and couldn't get from terraform")
        print("   Use --lambda-name or run 'terraform output' in terraform/ directory")
        return
    
    if not glue_job:
        print("⚠ Glue job name not provided and couldn't get from terraform")
        print("   Use --glue-job or run 'terraform output' in terraform/ directory")
        return
    
    if not dest_bucket:
        print("⚠ Destination bucket not provided and couldn't get from terraform")
        print("   Use --dest-bucket or run 'terraform output' in terraform/ directory")
        return
    
    print("\n" + "="*60)
    print("🔍 ETL Pipeline Monitoring")
    print(f"🌍 Region: {region}")
    print("="*60)
    
    # Check Lambda logs
    get_lambda_logs(lambda_name, region, args.hours)
    
    # Check Glue job status
    get_glue_job_status(glue_job, region)
    
    # Check S3 output
    check_s3_output(dest_bucket, region, args.prefix)
    
    print("\n" + "="*60)
    print("✅ Monitoring complete!")
    print("="*60 + "\n")


if __name__ == "__main__":
    main()

