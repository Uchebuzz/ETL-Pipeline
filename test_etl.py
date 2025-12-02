"""
Unit tests for ETL Pipeline
Run with: pytest test_etl.py -v
"""

import pytest
import os
import tempfile
import shutil
import csv
from etl_pipeline import ETLPipeline


class TestETLPipeline:
    """Test cases for ETL Pipeline"""
    
    @pytest.fixture
    def temp_dir(self):
        """Create temporary directory for test data"""
        temp_path = tempfile.mkdtemp()
        yield temp_path
        shutil.rmtree(temp_path)
    
    @pytest.fixture
    def sample_csv(self, temp_dir):
        """Create sample CSV file"""
        csv_path = os.path.join(temp_dir, "test_data.csv")
        with open(csv_path, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['Transaction ID', 'Date', 'Amount', 'Currency'])
            for i in range(10):
                writer.writerow([f'TXN-{i:03d}', '2024-01-01', 100.0 + i, 'USD'])
        return csv_path
    
    def test_pipeline_initialization(self):
        """Test pipeline initialization"""
        pipeline = ETLPipeline(
            source_path="test.csv",
            destination_bucket="test-bucket",
            source_type="local"
        )
        assert pipeline.source_path == "test.csv"
        assert pipeline.destination_bucket == "test-bucket"
        assert pipeline.source_type == "local"
    
    @pytest.mark.skip(reason="Requires Spark and AWS setup")
    def test_pipeline_extract(self, sample_csv):
        """Test data extraction"""
        pipeline = ETLPipeline(
            source_path=sample_csv,
            destination_bucket="test-bucket",
            source_type="local"
        )
        pipeline.initialize_spark()
        df = pipeline.extract()
        assert df is not None
        assert df.count() > 0
        pipeline.spark.stop()
    
    @pytest.mark.skip(reason="Requires Spark and AWS setup")
    def test_pipeline_transform(self, sample_csv):
        """Test data transformation"""
        pipeline = ETLPipeline(
            source_path=sample_csv,
            destination_bucket="test-bucket",
            source_type="local"
        )
        pipeline.initialize_spark()
        df = pipeline.extract()
        df_transformed = pipeline.transform(df)
        assert df_transformed is not None
        pipeline.spark.stop()


if __name__ == "__main__":
    pytest.main([__file__, "-v"])

