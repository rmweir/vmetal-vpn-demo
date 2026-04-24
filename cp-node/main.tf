data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# --- Networking ---

resource "aws_vpc" "cp" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true

  tags = { Name = "${var.instance_name}-vpc" }
}

resource "aws_subnet" "cp" {
  vpc_id                  = aws_vpc.cp.id
  cidr_block              = var.subnet_cidr
  map_public_ip_on_launch = true

  tags = { Name = "${var.instance_name}-subnet" }
}

resource "aws_internet_gateway" "cp" {
  vpc_id = aws_vpc.cp.id

  tags = { Name = "${var.instance_name}-igw" }
}

resource "aws_route_table" "cp" {
  vpc_id = aws_vpc.cp.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.cp.id
  }

  tags = { Name = "${var.instance_name}-rt" }
}

resource "aws_route_table_association" "cp" {
  subnet_id      = aws_subnet.cp.id
  route_table_id = aws_route_table.cp.id
}

# --- Security group ---

resource "aws_security_group" "cp" {
  name        = "${var.instance_name}-sg"
  description = "vMetal CP node: SSH inbound, full outbound"
  vpc_id      = aws_vpc.cp.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.instance_name}-sg" }
}

# --- Instance ---

resource "aws_instance" "cp" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = var.ssh_key_name
  subnet_id              = aws_subnet.cp.id
  vpc_security_group_ids = [aws_security_group.cp.id]

  root_block_device {
    volume_size = var.disk_size
    volume_type = "gp3"
  }

  tags = { Name = var.instance_name }
}
