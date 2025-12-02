# EC2 Instance for ETL Processing (optional)
resource "aws_instance" "etl_processor" {
  count                  = var.enable_ec2 ? 1 : 0
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.ec2_instance_type
  iam_instance_profile   = aws_iam_instance_profile.etl_instance_profile[0].name
  vpc_security_group_ids = [aws_security_group.etl_sg[0].id]

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y python3 python3-pip docker
              systemctl start docker
              systemctl enable docker
              
              # Install Docker Compose
              curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
              chmod +x /usr/local/bin/docker-compose
              
              # Install AWS CLI
              pip3 install awscli boto3
              EOF

  tags = {
    Name = "${var.project_name}-processor-${var.environment}"
  }
}

# Security Group for EC2
resource "aws_security_group" "etl_sg" {
  count       = var.enable_ec2 ? 1 : 0
  name        = "${var.project_name}-sg-${var.environment}"
  description = "Security group for ETL pipeline EC2 instance"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Restrict this in production
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-security-group"
  }
}

# Data source for Amazon Linux AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

output "ec2_instance_id" {
  description = "ID of the EC2 instance"
  value       = var.enable_ec2 ? aws_instance.etl_processor[0].id : null
}

output "ec2_instance_public_ip" {
  description = "Public IP of the EC2 instance"
  value       = var.enable_ec2 ? aws_instance.etl_processor[0].public_ip : null
}

