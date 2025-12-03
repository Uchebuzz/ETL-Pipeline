# CloudWatch Log Group for ETL Pipeline
resource "aws_cloudwatch_log_group" "etl_pipeline" {
  count             = var.enable_cloudwatch ? 1 : 0
  name              = "${var.project_name}-${var.environment}"
  retention_in_days = 30

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.project_name}-logs"
  }
}

# CloudWatch Metric Alarm for ETL Pipeline failures
resource "aws_cloudwatch_metric_alarm" "etl_pipeline_errors" {
  count               = var.enable_cloudwatch ? 1 : 0
  alarm_name          = "${var.project_name}-errors-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "PipelineErrors"
  namespace           = "ETL/Pipeline"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "This metric monitors ETL pipeline errors"
  treat_missing_data  = "notBreaching"

  tags = {
    Name = "${var.project_name}-error-alarm"
  }
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = var.enable_cloudwatch ? aws_cloudwatch_log_group.etl_pipeline[0].name : null
}

