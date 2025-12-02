"""
CloudWatch Monitoring Setup
Configures CloudWatch metrics and alarms for ETL pipeline
"""

import boto3
import json
from datetime import datetime
import logging

logger = logging.getLogger(__name__)


class CloudWatchMonitor:
    """CloudWatch monitoring for ETL pipeline"""
    
    def __init__(self, log_group_name: str, region: str = 'us-east-1'):
        """
        Initialize CloudWatch monitor
        
        Args:
            log_group_name: CloudWatch log group name
            region: AWS region
        """
        self.log_group_name = log_group_name
        self.cloudwatch = boto3.client('cloudwatch', region_name=region)
        self.logs = boto3.client('logs', region_name=region)
        
    def put_metric(self, metric_name: str, value: float, unit: str = 'Count'):
        """
        Put custom metric to CloudWatch
        
        Args:
            metric_name: Name of the metric
            value: Metric value
            unit: Unit of measurement
        """
        try:
            self.cloudwatch.put_metric_data(
                Namespace='ETL/Pipeline',
                MetricData=[
                    {
                        'MetricName': metric_name,
                        'Value': value,
                        'Unit': unit,
                        'Timestamp': datetime.utcnow()
                    }
                ]
            )
            logger.info(f"Published metric {metric_name}: {value}")
        except Exception as e:
            logger.error(f"Error publishing metric: {str(e)}")
    
    def log_pipeline_start(self):
        """Log pipeline start event"""
        self.put_metric('PipelineStarted', 1)
        logger.info("ETL Pipeline started")
    
    def log_pipeline_complete(self, duration_seconds: float, records_processed: int):
        """
        Log pipeline completion
        
        Args:
            duration_seconds: Pipeline duration in seconds
            records_processed: Number of records processed
        """
        self.put_metric('PipelineCompleted', 1)
        self.put_metric('PipelineDuration', duration_seconds, 'Seconds')
        self.put_metric('RecordsProcessed', records_processed)
        logger.info(f"ETL Pipeline completed: {records_processed} records in {duration_seconds}s")
    
    def log_pipeline_error(self, error_message: str):
        """
        Log pipeline error
        
        Args:
            error_message: Error message
        """
        self.put_metric('PipelineErrors', 1)
        logger.error(f"ETL Pipeline error: {error_message}")
    
    def create_log_stream(self, stream_name: str):
        """
        Create CloudWatch log stream
        
        Args:
            stream_name: Name of the log stream
        """
        try:
            # Create log group if it doesn't exist
            try:
                self.logs.create_log_group(logGroupName=self.log_group_name)
            except self.logs.exceptions.ResourceAlreadyExistsException:
                pass
            
            # Create log stream
            try:
                self.logs.create_log_stream(
                    logGroupName=self.log_group_name,
                    logStreamName=stream_name
                )
            except self.logs.exceptions.ResourceAlreadyExistsException:
                pass
            
            logger.info(f"Log stream {stream_name} ready")
        except Exception as e:
            logger.error(f"Error creating log stream: {str(e)}")


if __name__ == "__main__":
    # Example usage
    monitor = CloudWatchMonitor('etl-pipeline')
    monitor.log_pipeline_start()
    monitor.log_pipeline_complete(120.5, 5000)
    print("CloudWatch monitoring setup complete")

