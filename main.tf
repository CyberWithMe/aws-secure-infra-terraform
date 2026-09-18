terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~>5.0"
    }
  }
}

provider "aws" {
  region = "ap-southeast-1"
}

resource "aws_vpc" "my_vpc" {
  cidr_block           = "10.0.0.0/24"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "secure-infra-vpc"
  }

}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = "10.0.0.0/27"
  availability_zone       = "ap-southeast-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "secure-infra-public-subnet-1a"
  }
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.my_vpc.id
  cidr_block        = "10.0.0.32/27"
  availability_zone = "ap-southeast-1a"

  tags = {
    Name = "secure-infra-private-subnet-1a"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = "10.0.0.64/27"
  availability_zone       = "ap-southeast-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "secure-infra-public-subnet-1b"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.my_vpc.id
  cidr_block        = "10.0.0.96/27"
  availability_zone = "ap-southeast-1b"

  tags = {
    Name = "secure-infra-private-subnet-1b"
  }
}

resource "aws_internet_gateway" "my_igw" {
  vpc_id = aws_vpc.my_vpc.id

  tags = {
    Name = "secure-infra-igw"
  }
}

resource "aws_eip" "nat_eip_a" {
  domain = "vpc"

  tags = {
    Name = "secure-infra-nat-eip-1a"
  }
}

resource "aws_eip" "nat_eip_b" {
  domain = "vpc"

  tags = {
    Name = "secure-infra-nat-eip-1b"
  }
}

resource "aws_nat_gateway" "nat_gw_a" {
  allocation_id = aws_eip.nat_eip_a.id
  subnet_id     = aws_subnet.public_a.id

  tags = {
    Name = "secure-infra-nat-1a"
  }

  depends_on = [aws_internet_gateway.my_igw]
}

resource "aws_nat_gateway" "nat_gw_b" {
  allocation_id = aws_eip.nat_eip_b.id
  subnet_id     = aws_subnet.public_b.id

  tags = {
    Name = "secure-infra-nat-1b"
  }

  depends_on = [aws_internet_gateway.my_igw]
}


resource "aws_route_table" "public_igw"{
  vpc_id = aws_vpc.my_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.my_igw.id
  }

  tags = {
    Name = "secure-infra-public-rt"
  }
}

resource "aws_route_table_association" "public_a" {
  subnet_id = aws_subnet.public_a.id
  route_table_id = aws_route_table.public_igw.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id = aws_subnet.public_b.id
  route_table_id = aws_route_table.public_igw.id
}

resource "aws_route_table" "private_natgw_a"{
  vpc_id = aws_vpc.my_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw_a.id
  }

  tags = {
    Name = "secure-infra-private-rt-1a"
  }
}

resource "aws_route_table_association" "private_a"{
  subnet_id = aws_subnet.private_a.id
  route_table_id = aws_route_table.private_natgw_a.id
}

resource "aws_route_table" "private_natgw_b"{
  vpc_id = aws_vpc.my_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw_b.id
  }

  tags = {
    Name = "secure-infra-private-rt-1b"
  }
}

resource "aws_route_table_association" "private_b"{
  subnet_id = aws_subnet.private_b.id
  route_table_id = aws_route_table.private_natgw_b.id
}

resource "aws_security_group" "ec2_sg"{
  name = "secure-infra-ec2-sg"
  description = "Allow SSH only from bastion only"
  vpc_id = aws_vpc.my_vpc.id

  ingress {
    description = "SSH from bastion only"
    from_port = 22
    to_port = 22
    protocol = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  egress {
    description = "Allow all outbound"
    from_port = 0
    to_port = 0
    protocol = -1
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "secure-infra-ec2-sg"
  }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "app_server" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.private_a.id
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  key_name = aws_key_pair.deployer.key_name

  tags = {
    Name = "secure-infra-ec2"
  }
}

resource "aws_key_pair" "deployer" {
  key_name   = "secure-infra-key"
  public_key = file(var.ssh_public_key_path)
}

resource "aws_security_group" "bastion_sg" {
  name        = "secure-infra-bastion-sg"
  description = "Allow SSH only from my IP only - change when IP changes"
  vpc_id      = aws_vpc.my_vpc.id

  ingress {
    description = "SSH from my IP only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "secure-infra-bastion-sg"
  }
}

resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public_a.id
  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]
  key_name                    = aws_key_pair.deployer.key_name
  associate_public_ip_address = true

  tags = {
    Name = "secure-infra-bastion"
  }
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "cloudtrail_logs" {
  bucket = "secure-infra-cloudtrail-logs-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "secure-infra-cloudtrail-logs"
  }
}

resource "aws_s3_bucket_policy" "cloudtrail_bucket_policy" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.cloudtrail_logs.arn
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.cloudtrail_logs.arn}/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      }
    ]
  })
}

resource "aws_cloudtrail" "my_logs" {
  name                          = "secure-infra-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail_logs.id
  include_global_service_events = true
  is_multi_region_trail         = true

  depends_on = [aws_s3_bucket_policy.cloudtrail_bucket_policy]

  tags = {
    Name = "secure-infra-cloudtrail"
  }
}
