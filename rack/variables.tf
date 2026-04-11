variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "instance_type" {
  description = "EC2 instance type. Must support nested virtualization for KubeVirt (e.g. c5.metal, m5.metal)"
  type        = string
  default     = "c5.metal"
}

variable "disk_size" {
  description = "Root volume size in GB"
  type        = number
  default     = 200
}

variable "instance_name" {
  description = "Name tag applied to the EC2 instance and related resources"
  type        = string
  default     = "vmetal-rack"
}

variable "ssh_key_name" {
  description = "Name of an existing EC2 key pair for SSH access"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
}
