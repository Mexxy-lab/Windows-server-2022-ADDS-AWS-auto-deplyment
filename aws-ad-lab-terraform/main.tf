# Retrieve available Availability Zones in the selected AWS region.
data "aws_availability_zones" "available" {
  state = "available"
}

# Retrieve the latest Windows Server 2022 English Full Base AMI.
data "aws_ssm_parameter" "windows_server_2022_ami" {
  name = "/aws/service/ami-windows-latest/Windows_Server-2022-English-Full-Base"
}

# Common resource tags.
locals {
  common_tags = {
    Project     = var.project_name
    Environment = "lab"
    ManagedBy   = "Terraform"
  }
}

# Main VPC for the Active Directory environment.
resource "aws_vpc" "lab" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-vpc"
  })
}

# Internet gateway provides internet connectivity to the public subnet.
resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-igw"
  })
}

# Public subnet for the NAT instance.
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-public-subnet"
    Tier = "public"
  })
}

# Private subnet for DC01 and the optional Windows client.
resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = var.private_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-private-subnet"
    Tier = "private"
  })
}

# Public subnet route table sends internet-bound traffic to the IGW.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.lab.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab.id
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-public-rt"
  })
}

# Associate the public route table with the NAT subnet.
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Private route table sends internet-bound traffic through the NAT instance.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.lab.id

  route {
    cidr_block           = "0.0.0.0/0"
    network_interface_id = aws_instance.nat.primary_network_interface_id
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-private-rt"
  })
}

# Associate the private route table with the Windows subnet.
resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# Provide a domain search suffix while retaining Amazon-provided DNS.
# This is important before AD DNS has been installed on DC01.
resource "aws_vpc_dhcp_options" "lab" {
  domain_name         = var.domain_name
  domain_name_servers = ["AmazonProvidedDNS"]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-dhcp-options"
  })
}

# Associate the DHCP options with the lab VPC.
resource "aws_vpc_dhcp_options_association" "lab" {
  vpc_id          = aws_vpc.lab.id
  dhcp_options_id = aws_vpc_dhcp_options.lab.id
}