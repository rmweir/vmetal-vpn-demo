variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "instance_type" {
  description = "EC2 instance type for the vCluster control plane node"
  type        = string
  default     = "t3.large"
}

variable "disk_size" {
  description = "Root volume size in GB"
  type        = number
  default     = 40
}

variable "instance_name" {
  description = "Name tag applied to the EC2 instance and related resources"
  type        = string
  default     = "vmetal-cp"
}

variable "ssh_key_name" {
  description = "Name of an existing EC2 key pair for SSH access"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.1.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.1.1.0/24"
}
