# Security group for the NAT instance.
resource "aws_security_group" "nat" {
  name        = "${var.project_name}-nat-sg"
  description = "Allows private subnet traffic to reach the NAT instance."
  vpc_id      = aws_vpc.lab.id

  # Forwarded packets arrive from the private Windows subnet.
  # The NAT instance performs routing and masquerading.
  ingress {
    description = "Forwarded traffic from private Windows subnet"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.private_subnet_cidr]
  }

  # Permit HTTP for operating system updates and downloads.
  egress {
    description = "HTTP outbound"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Permit HTTPS for package repositories and required downloads.
  egress {
    description = "HTTPS outbound"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # DNS and NTP rules are intentionally omitted.
  # AWS-provided DNS and Amazon Time Sync are available through
  # AWS-managed resolver and link-local services.

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-nat-sg"
  })
}

# Security group shared by DC01 and the optional Windows client.
resource "aws_security_group" "windows" {
  name        = "${var.project_name}-windows-sg"
  description = "Private Windows AD instances with no public management access."
  vpc_id      = aws_vpc.lab.id

  # Allow AD, DNS, Kerberos, SMB, RPC, and other internal
  # Windows communication between instances using this group.
  ingress {
    description = "Internal Windows and Active Directory communication"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # Allow private VPC communication, including domain services.
  egress {
    description = "Internal VPC communication"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  # Allow Windows Update, AWS SSM, and AWS API HTTPS access.
  egress {
    description = "HTTPS outbound"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTP downloads when required.
  egress {
    description = "HTTP outbound"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # DNS and NTP rules are intentionally omitted.
  # DC01 will use AmazonProvidedDNS as its DNS forwarder.
  # The PDC Emulator will use Amazon Time Sync.

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-windows-sg"
  })
}
