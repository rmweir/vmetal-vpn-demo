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

resource "aws_vpc" "rack" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true

  tags = { Name = "${var.instance_name}-vpc" }
}

resource "aws_subnet" "rack" {
  vpc_id                  = aws_vpc.rack.id
  cidr_block              = var.subnet_cidr
  map_public_ip_on_launch = true

  tags = { Name = "${var.instance_name}-subnet" }
}

resource "aws_internet_gateway" "rack" {
  vpc_id = aws_vpc.rack.id

  tags = { Name = "${var.instance_name}-igw" }
}

resource "aws_route_table" "rack" {
  vpc_id = aws_vpc.rack.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.rack.id
  }

  tags = { Name = "${var.instance_name}-rt" }
}

resource "aws_route_table_association" "rack" {
  subnet_id      = aws_subnet.rack.id
  route_table_id = aws_route_table.rack.id
}

# --- Security group ---

resource "aws_security_group" "rack" {
  name        = "${var.instance_name}-sg"
  description = "vMetal rack: SSH + VirtualBMC (Redfish) inbound, full outbound"
  vpc_id      = aws_vpc.rack.id

  # SSH
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # VirtualBMC Redfish NodePorts — Metal3/Ironic connects here to power cycle and boot VMs
  ingress {
    description = "VirtualBMC Redfish NodePorts"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Full outbound — needed for image pulls, OS downloads, and VPN
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.instance_name}-sg" }
}

# --- Instance ---

resource "aws_instance" "rack" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = var.ssh_key_name
  subnet_id              = aws_subnet.rack.id
  vpc_security_group_ids = [aws_security_group.rack.id]

  root_block_device {
    volume_size = var.disk_size
    volume_type = "gp3"
  }

  tags = { Name = var.instance_name }
}
