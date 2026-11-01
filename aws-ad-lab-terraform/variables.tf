# AWS region for all lab resources.
variable "aws_region" {
  description = "AWS Region for the Active Directory lab."
  type        = string
  default     = "us-east-1"
}

# Common project name used in resource names and tags.
variable "project_name" {
  description = "Name used to identify lab resources."
  type        = string
  default     = "pumej-ad-lab"
}

# Active Directory DNS domain.
variable "domain_name" {
  description = "Active Directory DNS domain name."
  type        = string
  default     = "pumejlab.com"
}

# Active Directory NetBIOS domain name.
variable "domain_netbios_name" {
  description = "Active Directory NetBIOS domain name."
  type        = string
  default     = "PUMEJLAB"
}

# Overall VPC address space.
variable "vpc_cidr" {
  description = "CIDR block for the lab VPC."
  type        = string
  default     = "10.20.0.0/16"
}

# Public subnet hosts the NAT instance.
variable "public_subnet_cidr" {
  description = "CIDR block for the public NAT subnet."
  type        = string
  default     = "10.20.1.0/24"
}

# Private subnet hosts the Windows instances.
variable "private_subnet_cidr" {
  description = "CIDR block for private Windows instances."
  type        = string
  default     = "10.20.2.0/24"
}

# Static private address for the NAT instance.
variable "nat_private_ip" {
  description = "Private IP address assigned to the NAT instance."
  type        = string
  default     = "10.20.1.10"
}

# Static private address for the domain controller.
variable "dc_private_ip" {
  description = "Private IP address assigned to DC01."
  type        = string
  default     = "10.20.2.10"
}

# Static private address for the optional Windows client.
variable "client_private_ip" {
  description = "Private IP address assigned to the optional Windows client."
  type        = string
  default     = "10.20.2.20"
}

# NAT instance size. A micro instance is economical for a small lab.
variable "nat_instance_type" {
  description = "EC2 instance type for the Linux NAT instance."
  type        = string
  default     = "t3.micro"
}

# Domain controller instance size.
variable "dc_instance_type" {
  description = "EC2 instance type for the domain controller."
  type        = string
  default     = "t3.large"
}

# Optional Windows client instance size.
variable "client_instance_type" {
  description = "EC2 instance type for the optional Windows client."
  type        = string
  default     = "t3.large"
}

# Controls whether the additional Windows client is deployed.
variable "deploy_windows_client" {
  description = "Deploy an optional Windows domain client."
  type        = bool
  default     = false
}

# Encrypted Windows root volume size.
variable "root_volume_size_gib" {
  description = "Size of each Windows root volume in GiB."
  type        = number
  default     = 60

  validation {
    condition     = var.root_volume_size_gib >= 30
    error_message = "Windows root volumes must be at least 30 GiB."
  }
}