# IAM trust policy allowing EC2 to assume an instance role.
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# IAM role for the Windows domain controller and optional client.
resource "aws_iam_role" "windows_ssm" {
  name               = "${var.project_name}-windows-ssm-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = local.common_tags
}

# Allow Windows instances to register with Systems Manager.
resource "aws_iam_role_policy_attachment" "windows_ssm" {
  role       = aws_iam_role.windows_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Customer-managed KMS key for encrypting the bootstrap secret.
resource "aws_kms_key" "secrets" {
  description             = "Encrypts the AWS AD lab bootstrap secret."
  enable_key_rotation     = true
  deletion_window_in_days = 7

  tags = local.common_tags
}

# Friendly alias for the bootstrap secret encryption key.
resource "aws_kms_alias" "secrets" {
  name          = "alias/${var.project_name}-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}

# Create the bootstrap secret in Secrets Manager.
# startupadds-aws.sh populates its value after Terraform deployment.
resource "aws_secretsmanager_secret" "bootstrap_password" {
  name                    = "${var.project_name}/bootstrap-password"
  description             = "Temporary bootstrap password for Windows AD lab instances."
  recovery_window_in_days = 0

  # Encrypt the secret using our customer-managed KMS key.
  kms_key_id = aws_kms_key.secrets.arn

  tags = local.common_tags
}

# Permit Windows instances to retrieve and decrypt only this lab's bootstrap secret.
data "aws_iam_policy_document" "windows_secret_access" {
  statement {
    sid = "ReadWindowsBootstrapSecret"

    actions = [
      "secretsmanager:GetSecretValue"
    ]

    resources = [
      aws_secretsmanager_secret.bootstrap_password.arn
    ]
  }

  statement {
    sid = "DecryptBootstrapSecret"

    actions = [
      "kms:Decrypt"
    ]

    resources = [
      aws_kms_key.secrets.arn
    ]
  }
}

resource "aws_iam_policy" "windows_secret_access" {
  name        = "${var.project_name}-windows-secret-access"
  description = "Allows Windows lab instances to retrieve their bootstrap password."
  policy      = data.aws_iam_policy_document.windows_secret_access.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "windows_secret_access" {
  role       = aws_iam_role.windows_ssm.name
  policy_arn = aws_iam_policy.windows_secret_access.arn
}

# Instance profile used by DC01 and the optional Windows client.
resource "aws_iam_instance_profile" "windows" {
  name = "${var.project_name}-windows-instance-profile"
  role = aws_iam_role.windows_ssm.name

  tags = local.common_tags
}

# Separate IAM role for the NAT instance.
resource "aws_iam_role" "nat_ssm" {
  name               = "${var.project_name}-nat-ssm-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = local.common_tags
}

# Allow Systems Manager management of the NAT instance.
resource "aws_iam_role_policy_attachment" "nat_ssm" {
  role       = aws_iam_role.nat_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Instance profile used by the NAT instance.
resource "aws_iam_instance_profile" "nat" {
  name = "${var.project_name}-nat-instance-profile"
  role = aws_iam_role.nat_ssm.name

  tags = local.common_tags
}