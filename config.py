"""
Configuration management for ETL Pipeline
Handles secrets and environment variables
"""

import os
from typing import Optional


class Config:
    """Configuration class for ETL Pipeline"""
    
    # AWS Configuration
    AWS_REGION = os.getenv('AWS_REGION', 'us-east-1')
    AWS_ACCESS_KEY_ID = os.getenv('AWS_ACCESS_KEY_ID')
    AWS_SECRET_ACCESS_KEY = os.getenv('AWS_SECRET_ACCESS_KEY')
    
    # S3 Configuration
    SOURCE_BUCKET = os.getenv('SOURCE_BUCKET', 'etl-pipeline-source')
    DESTINATION_BUCKET = os.getenv('DESTINATION_BUCKET', 'etl-pipeline-output')
    SOURCE_PATH = os.getenv('SOURCE_PATH', 'data/sample_financial_data.csv')
    SOURCE_TYPE = os.getenv('SOURCE_TYPE', 'local')  # 's3' or 'local'
    OUTPUT_PREFIX = os.getenv('OUTPUT_PREFIX', 'processed_data')
    
    # Monitoring Configuration
    CLOUDWATCH_LOG_GROUP = os.getenv('CLOUDWATCH_LOG_GROUP', 'etl-pipeline')
    CLOUDWATCH_ENABLED = os.getenv('CLOUDWATCH_ENABLED', 'true').lower() == 'true'
    
    # Secrets Management
    VAULT_ADDR = os.getenv('VAULT_ADDR')
    VAULT_TOKEN = os.getenv('VAULT_TOKEN')
    USE_VAULT = os.getenv('USE_VAULT', 'false').lower() == 'true'
    
    @classmethod
    def get_aws_credentials(cls) -> Optional[dict]:
        """
        Get AWS credentials from environment or Vault
        
        Returns:
            Dictionary with AWS credentials or None
        """
        if cls.USE_VAULT and cls.VAULT_ADDR:
            return cls._get_credentials_from_vault()
        else:
            if cls.AWS_ACCESS_KEY_ID and cls.AWS_SECRET_ACCESS_KEY:
                return {
                    'aws_access_key_id': cls.AWS_ACCESS_KEY_ID,
                    'aws_secret_access_key': cls.AWS_SECRET_ACCESS_KEY,
                    'region_name': cls.AWS_REGION
                }
        return None
    
    @classmethod
    def _get_credentials_from_vault(cls) -> Optional[dict]:
        """
        Retrieve AWS credentials from HashiCorp Vault
        
        Returns:
            Dictionary with AWS credentials or None
        """
        try:
            import hvac
            client = hvac.Client(url=cls.VAULT_ADDR, token=cls.VAULT_TOKEN)
            
            # Read AWS credentials from Vault
            secret_response = client.secrets.kv.v2.read_secret_version(path='aws/credentials')
            credentials = secret_response['data']['data']
            
            return {
                'aws_access_key_id': credentials.get('aws_access_key_id'),
                'aws_secret_access_key': credentials.get('aws_secret_access_key'),
                'region_name': cls.AWS_REGION
            }
        except ImportError:
            print("hvac library not installed. Install with: pip install hvac")
            return None
        except Exception as e:
            print(f"Error retrieving credentials from Vault: {str(e)}")
            return None
    
    @classmethod
    def validate(cls) -> bool:
        """
        Validate configuration
        
        Returns:
            True if configuration is valid
        """
        errors = []
        
        if cls.SOURCE_TYPE == 's3':
            if not cls.AWS_ACCESS_KEY_ID or not cls.AWS_SECRET_ACCESS_KEY:
                if not cls.USE_VAULT:
                    errors.append("AWS credentials required when using S3 source")
        
        if errors:
            print("Configuration errors:")
            for error in errors:
                print(f"  - {error}")
            return False
        
        return True

