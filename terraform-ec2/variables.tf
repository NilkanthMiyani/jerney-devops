variable "aws_region" {
  description = "AWS region to deploy the EC2 instance"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "instance_type" {
  description = "EC2 instance type (t3.large recommended for single-node kubeadm)"
  type        = string
  default     = "t3.large"
}

variable "key_name" {
  description = "Name of the existing EC2 key pair"
  type        = string
  default     = "nilkanth-personal"
}

variable "volume_size" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 30
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH into the instance (set to your IP/32)"
  type        = string
  default     = "0.0.0.0/0" # Restrict this to your IP in production
}
