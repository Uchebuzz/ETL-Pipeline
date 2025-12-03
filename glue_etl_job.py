"""
AWS Glue ETL Job Script using PySpark
Processes CSV or JSON files from S3 and outputs Parquet files
"""

import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql import functions as F
from pyspark.sql.types import *
from datetime import datetime

# Initialize Glue context
args = getResolvedOptions(sys.argv, [
    'JOB_NAME',
    'source_bucket',
    'source_key',
    'destination_bucket',
    'output_prefix'
])

# Glue provides its own SparkContext - don't create a new one
glueContext = GlueContext(SparkContext.getOrCreate())
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# Get job parameters
source_bucket = args['source_bucket']
source_key = args['source_key']
destination_bucket = args['destination_bucket']
output_prefix = args.get('output_prefix', 'processed_data')

# Construct S3 paths
source_path = f"s3://{source_bucket}/{source_key}"
timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
output_path = f"s3://{destination_bucket}/{output_prefix}/date={timestamp}/"

print(f"Reading data from: {source_path}")
print(f"Writing data to: {output_path}")

# Detect file type and read accordingly
if source_key.lower().endswith('.json'):
    # Read JSON from S3
    df = spark.read.format("json").option("inferSchema", "true").load(source_path)
    print("Reading JSON file")
else:
    # Read CSV from S3
    df = spark.read.format("csv").option("header", "true").option("inferSchema", "true").load(source_path)
    print("Reading CSV file")

print(f"Initial record count: {df.count()}")

# Transform data
# Clean and standardize column names
for col_name in df.columns:
    new_col_name = col_name.lower().replace(' ', '_').replace('-', '_')
    if new_col_name != col_name:
        df = df.withColumnRenamed(col_name, new_col_name)

# Convert date columns
date_columns = [c for c in df.columns if 'date' in c.lower()]
for date_col in date_columns:
    df = df.withColumn(date_col, F.to_date(F.col(date_col), 'yyyy-MM-dd'))

# Add processing metadata
df = df.withColumn('processed_date', F.lit(datetime.now().strftime("%Y-%m-%d")))

# Handle amount columns and add partitioning columns
amount_columns = [c for c in df.columns if 'amount' in c.lower() or 'value' in c.lower()]

if amount_columns:
    # Add year and month for partitioning if date column exists
    if date_columns:
        df = df.withColumn('year', F.year(F.col(date_columns[0])))
        df = df.withColumn('month', F.month(F.col(date_columns[0])))
    
    # Remove rows with null amounts
    df = df.filter(F.col(amount_columns[0]).isNotNull())

# Remove duplicates
df = df.dropDuplicates()

print(f"Final record count after transformation: {df.count()}")

# Write to S3 as Parquet with Snappy compression
df.write.mode("overwrite").format("parquet").option("compression", "snappy").save(output_path)

print(f"Successfully wrote data to {output_path}")

job.commit()

