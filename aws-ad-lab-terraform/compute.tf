# Domain Controller - DC01.
resource "aws_instance" "dc01" {
  ami           = data.aws_ssm_parameter.windows_server_2022_ami.value
  instance_type = var.dc_instance_type

  # Windows instances are deployed in the private subnet.
  subnet_id = aws_subnet.private.id

  # Explicitly prevent public IP assignment.
  associate_public_ip_address = false

  # Apply the Windows security group.
  vpc_security_group_ids = [
    aws_security_group.windows.id
  ]

  # Use the Windows instance profile for SSM and bootstrap secret access.
  iam_instance_profile = aws_iam_instance_profile.windows.name

  # Assign the static private address used by the AD domain.
  private_ip = var.dc_private_ip

  # Encrypt the Windows operating system volume.
  root_block_device {
    volume_size           = var.root_volume_size_gib
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  # Require IMDSv2.
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-DC01"
    Role = "DomainController"
  })

  # Ensure routing, DNS configuration, and IAM permissions are ready
  # before Windows instances launch.
  depends_on = [
    aws_route_table_association.private,
    aws_vpc_dhcp_options_association.lab,
    aws_iam_role_policy_attachment.windows_ssm,
    aws_iam_role_policy_attachment.windows_secret_access
  ]
}

# Optional Windows domain client.
resource "aws_instance" "windows_client" {
  count = var.deploy_windows_client ? 1 : 0

  ami           = data.aws_ssm_parameter.windows_server_2022_ami.value
  instance_type = var.client_instance_type

  # The client is also deployed in the private subnet.
  subnet_id = aws_subnet.private.id

  # Never assign a public IP to the Windows client.
  associate_public_ip_address = false

  vpc_security_group_ids = [
    aws_security_group.windows.id
  ]

  # The client needs SSM and bootstrap secret access too.
  iam_instance_profile = aws_iam_instance_profile.windows.name

  private_ip = var.client_private_ip

  root_block_device {
    volume_size           = var.root_volume_size_gib
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  # Ensure routing, DNS configuration, and IAM permissions are ready
  # before Windows instances launch.
  depends_on = [
    aws_route_table_association.private,
    aws_vpc_dhcp_options_association.lab,
    aws_iam_role_policy_attachment.windows_ssm,
    aws_iam_role_policy_attachment.windows_secret_access
  ]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-WIN-CLIENT-01"
    Role = "DomainClient"
  })
}