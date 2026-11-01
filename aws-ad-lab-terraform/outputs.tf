# AWS deployment region.
output "aws_region" {
  description = "AWS region containing the lab."
  value       = var.aws_region
}

# Active Directory DNS domain.
output "domain_name" {
  description = "Active Directory domain name."
  value       = var.domain_name
}

# NAT instance information.
output "nat_instance_id" {
  description = "EC2 instance ID of the NAT instance."
  value       = aws_instance.nat.id
}

output "nat_private_ip" {
  description = "Private IP address of the NAT instance."
  value       = aws_instance.nat.private_ip
}

output "nat_public_ip" {
  description = "Public IP address of the NAT instance."
  value       = aws_instance.nat.public_ip
}

# Domain controller information.
output "dc01_instance_id" {
  description = "EC2 instance ID of DC01."
  value       = aws_instance.dc01.id
}

output "dc01_private_ip" {
  description = "Private IP address of DC01."
  value       = aws_instance.dc01.private_ip
}

# Optional Windows client information.
# Empty strings are returned when the optional client is disabled.
output "windows_client_instance_id" {
  description = "EC2 instance ID of the optional Windows client."
  value       = var.deploy_windows_client ? aws_instance.windows_client[0].id : ""
}

output "windows_client_private_ip" {
  description = "Private IP address of the optional Windows client."
  value       = var.deploy_windows_client ? aws_instance.windows_client[0].private_ip : ""
}

# Secrets Manager bootstrap secret ARN.
output "bootstrap_secret_arn" {
  description = "ARN of the Windows bootstrap password secret."
  value       = aws_secretsmanager_secret.bootstrap_password.arn
}

# AmazonProvidedDNS resolver address.
# The VPC resolver is the second address in the VPC CIDR range.
output "vpc_dns_resolver_ip" {
  description = "AmazonProvidedDNS resolver address for external DNS forwarding."
  value       = cidrhost(var.vpc_cidr, 2)
}