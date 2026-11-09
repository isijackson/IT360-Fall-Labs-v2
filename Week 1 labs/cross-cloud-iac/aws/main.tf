terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "region" {
  type    = string
  default = "us-east-1"
}
variable "name" {
  type    = string
  default = "it360-web"
}
variable "ssh_public_key" { type = string }
variable "ssh_source_cidr" {
  type    = string
  default = "0.0.0.0/0" # narrow this to <your public ip>/32 outside a sandbox
}

provider "aws" { region = var.region }

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_key_pair" "web" {
  key_name   = "${var.name}-key"
  public_key = var.ssh_public_key
}

resource "aws_security_group" "web" {
  name = "${var.name}-sg"
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_source_cidr]
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "web" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.web.key_name
  vpc_security_group_ids = [aws_security_group.web.id]
  tags                   = { Name = var.name }
  user_data              = <<-EOT
    #!/bin/bash
    apt-get update && apt-get install -y nginx
    echo "<h1>served from AWS by $(hostname)</h1>" > /var/www/html/index.html
  EOT
}

output "public_ip" { value = aws_instance.web.public_ip }
