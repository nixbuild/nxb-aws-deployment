terraform {
  backend "local" {}
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    http = {
      source = "hashicorp/http"
    }
  }
}

provider "aws" {
  region = var.region
}

locals {
  availability_zone = "${var.region}a"
  nxb_server_ip     = cidrhost(aws_subnet.public.cidr_block, 10)
}

# VPC

resource "aws_vpc" "nxb" {
  cidr_block           = "10.0.0.0/20"
  enable_dns_hostnames = true
  tags = {
    Name = "nxb"
  }
}

# Public subnet

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.nxb.id
  cidr_block              = "10.0.0.0/21"
  availability_zone       = local.availability_zone
  map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "public" {
  vpc_id = aws_vpc.nxb.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.nxb.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.public.id
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nxb_server" {
  domain                    = "vpc"
  associate_with_private_ip = local.nxb_server_ip
  depends_on                = [aws_internet_gateway.public]
}

# Private subnet

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.nxb.id
  cidr_block        = "10.0.8.0/21"
  availability_zone = local.availability_zone
}

resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "private" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
  depends_on    = [aws_internet_gateway.public]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.nxb.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.private.id
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}


# Security groups

resource "aws_security_group" "public" {
  vpc_id = aws_vpc.nxb.id

  ingress {
    description = "Allow traffic between instances within the security group"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  ingress {
    description = "Allow traffic from private subnet"
    from_port   = 0
    to_port     = 65535 # TODO Lock down
    protocol    = "tcp"
    cidr_blocks = [aws_subnet.private.cidr_block]
  }

  ingress {
    description = "Allow SSH traffic from everywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow Nix traffic from everywhere"
    from_port   = 2222
    to_port     = 2222
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "private" {
  vpc_id = aws_vpc.nxb.id

  ingress {
    description = "Allow traffic from public subnet"
    from_port   = 0
    to_port     = 65535 # TODO Lock down
    protocol    = "tcp"
    cidr_blocks = [aws_subnet.public.cidr_block]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


# IAM

resource "aws_iam_role" "nxb_server" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "nxb_server" {
  statement {
    actions = [
      "ec2:RunInstances",
      "ec2:DescribeImages",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:AssociateAddress",
      "ec2:CreateTags",
      "ec2:DescribeInstances",
      "ec2:TerminateInstances",
      "sts:DecodeAuthorizationMessage"
    ]
    resources = ["*"] # TODO
  }

  statement {
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath"
    ]
    resources = [
      "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/${var.ssm_param_biscuit_secretkey}",
      "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/${var.ssm_param_ssh_hostkey}",
    ]
  }

  statement {
    actions   = ["kms:Decrypt"]
    resources = ["*"] # We use the default AWS-provided key
  }
}

resource "aws_iam_role_policy" "nxb_server" {
  role   = aws_iam_role.nxb_server.id
  policy = data.aws_iam_policy_document.nxb_server.json
}

resource "aws_iam_role_policy_attachment" "nxb_server_ssm" {
  role       = aws_iam_role.nxb_server.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "nxb_server" {
  role = aws_iam_role.nxb_server.name
}


# EBS

resource "aws_ebs_volume" "nxb_data" {
  availability_zone = local.availability_zone
  size              = 2048
  type              = "gp3"
  iops              = 6000
  throughput        = 1000
}


# EC2

resource "aws_instance" "nxb_server" {
  ami                    = local.amis[var.nxb_server_ami].ami_id
  instance_type          = var.nxb_server_instance_type
  iam_instance_profile   = aws_iam_instance_profile.nxb_server.name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.public.id]
  private_ip             = local.nxb_server_ip

  user_data_base64 = base64gzip(local.nxb_server_userdata)

  root_block_device {
    volume_size = 10
    volume_type = "gp3"
  }

  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name = "nxb-server"
  }
}

resource "aws_eip_association" "nxb_server" {
  instance_id   = aws_instance.nxb_server.id
  allocation_id = aws_eip.nxb_server.id
}

resource "aws_volume_attachment" "nxb_state" {
  device_name  = "/dev/sdb"
  volume_id    = aws_ebs_volume.nxb_data.id
  instance_id  = aws_instance.nxb_server.id
  force_detach = true
}

output "nxb_server_public_ip" {
  value       = aws_eip.nxb_server.public_ip
  description = "The public IP address of nxb-server."
}
