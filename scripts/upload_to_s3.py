#!/usr/bin/env python3
"""
Script to upload sample data to S3
Usage: python scripts/upload_to_s3.py --bucket my-bucket --file data/sample_financial_data.csv
"""

import argparse
import boto3
import os
from pathlib import Path


def upload_file_to_s3(file_path: str, bucket_name: str, s3_key: str = None):
    """
    Upload a file to S3
    
    Args:
        file_path: Local file path
        bucket_name: S3 bucket name
        s3_key: S3 object key (defaults to filename)
    """
    if not os.path.exists(file_path):
        print(f"Error: File {file_path} not found")
        return False
    
    if s3_key is None:
        s3_key = os.path.basename(file_path)
    
    try:
        s3_client = boto3.client('s3')
        
        print(f"Uploading {file_path} to s3://{bucket_name}/{s3_key}...")
        s3_client.upload_file(file_path, bucket_name, s3_key)
        
        print(f"✓ Successfully uploaded to s3://{bucket_name}/{s3_key}")
        return True
        
    except Exception as e:
        print(f"Error uploading to S3: {str(e)}")
        return False


def main():
    parser = argparse.ArgumentParser(description='Upload files to S3')
    parser.add_argument('--bucket', required=True, help='S3 bucket name')
    parser.add_argument('--file', required=True, help='Local file path')
    parser.add_argument('--key', help='S3 object key (defaults to filename)')
    parser.add_argument('--prefix', default='input', help='S3 prefix (default: input)')
    
    args = parser.parse_args()
    
    # Generate S3 key
    if args.key:
        s3_key = args.key
    else:
        filename = os.path.basename(args.file)
        s3_key = f"{args.prefix}/{filename}"
    
    upload_file_to_s3(args.file, args.bucket, s3_key)


if __name__ == "__main__":
    main()

