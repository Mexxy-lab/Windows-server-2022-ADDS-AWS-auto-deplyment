# Retrieve the AWS account ID and active region for the KMS key policy.
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Allow the AWS account to manage the KMS key through IAM.
# Also allow CloudWatch Logs to encrypt and decrypt this log group's data.
data "aws_iam_policy_document" "cloudwatch_logs_kms" {
  statement {
    sid    = "EnableAccountKeyAdministration"
    effect = "Allow"

    principals {
      type = "AWS"
      identifiers = [
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      ]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudWatchLogsEncryption"
    effect = "Allow"

    principals {
      type = "Service"
      identifiers = [
        "logs.${data.aws_region.current.region}.amazonaws.com"
      ]
    }

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*"
    ]

    resources = ["*"]

    # Restrict this key's CloudWatch Logs use to our specific log group.
    condition {
      test     = "ArnEquals"
      variable = "kms:EncryptionContext:aws:logs:arn"

      # Construct the log group ARN directly instead of referencing
      # the CloudWatch Log Group resource. This breaks the dependency cycle.
      values = [
        "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/vpc/${var.project_name}/rejected-traffic"
      ]
    }
  }
}

# Dedicated customer-managed key for CloudWatch Logs.
resource "aws_kms_key" "cloudwatch_logs" {
  description             = "Encrypts rejected VPC traffic logs."
  enable_key_rotation     = true
  deletion_window_in_days = 7

  policy = data.aws_iam_policy_document.cloudwatch_logs_kms.json

  tags = local.common_tags
}

# Friendly alias for the CloudWatch Logs encryption key.
resource "aws_kms_alias" "cloudwatch_logs" {
  name          = "alias/${var.project_name}-cloudwatch-logs"
  target_key_id = aws_kms_key.cloudwatch_logs.key_id
}

# Store rejected VPC traffic logs in CloudWatch.
resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/aws/vpc/${var.project_name}/rejected-traffic"
  retention_in_days = 30

  # Encrypt log events with our dedicated customer-managed KMS key.
  kms_key_id = aws_kms_key.cloudwatch_logs.arn

  tags = local.common_tags
}

# Allow the VPC Flow Logs service to assume this IAM role.
data "aws_iam_policy_document" "vpc_flow_logs_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

# Dedicated role for publishing VPC Flow Logs.
resource "aws_iam_role" "vpc_flow_logs" {
  name               = "${var.project_name}-vpc-flow-logs-role"
  assume_role_policy = data.aws_iam_policy_document.vpc_flow_logs_assume_role.json

  tags = local.common_tags
}

# Define the minimum CloudWatch permissions needed to publish logs.
data "aws_iam_policy_document" "vpc_flow_logs" {
  statement {
    sid = "PublishVpcFlowLogs"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams"
    ]

    resources = [
      "${aws_cloudwatch_log_group.vpc_flow_logs.arn}:*"
    ]
  }
}

# Attach the scoped logging permissions to the role.
resource "aws_iam_role_policy" "vpc_flow_logs" {
  name   = "${var.project_name}-vpc-flow-logs-policy"
  role   = aws_iam_role.vpc_flow_logs.id
  policy = data.aws_iam_policy_document.vpc_flow_logs.json
}

# Capture rejected traffic across the entire lab VPC.
resource "aws_flow_log" "lab_rejected_traffic" {
  vpc_id               = aws_vpc.lab.id
  traffic_type         = "REJECT"
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.vpc_flow_logs.arn
  iam_role_arn         = aws_iam_role.vpc_flow_logs.arn

  # Use one-minute aggregation intervals.
  max_aggregation_interval = 60

  depends_on = [
    aws_iam_role_policy.vpc_flow_logs
  ]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-rejected-traffic-flow-log"
  })
}
