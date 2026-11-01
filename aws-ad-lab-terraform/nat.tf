# Retrieve the latest Amazon Linux 2023 x86_64 AMI.
data "aws_ssm_parameter" "amazon_linux_2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# NAT instance provides outbound internet connectivity for private instances.
resource "aws_instance" "nat" {
  ami                    = data.aws_ssm_parameter.amazon_linux_2023_ami.value
  instance_type          = var.nat_instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.nat.id]

  # The NAT instance must have a public address to communicate with the internet.
  associate_public_ip_address = true

  # Disable EC2 source/destination checking so the instance can forward packets.
  source_dest_check = false

  # Assign a predictable private address in the public subnet.
  private_ip = var.nat_private_ip

  # Allow Systems Manager to manage the NAT instance without SSH access.
  iam_instance_profile = aws_iam_instance_profile.nat.name

  # Require IMDSv2 for instance metadata access.
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  # Keep the NAT instance disk small and encrypted.
  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  # Configure IPv4 forwarding and persistent NAT firewall rules.
  user_data = <<-USERDATA
    #!/bin/bash
    set -euxo pipefail

    # Install the nftables firewall utility.
    dnf install -y nftables

    # Enable IPv4 forwarding immediately and persistently.
    cat > /etc/sysctl.d/99-nat-instance.conf <<'SYSCTL'
    net.ipv4.ip_forward = 1
    SYSCTL

    sysctl --system

    # Create the NAT rules file.
    # The primary interface is discovered dynamically because interface
    # names can vary between EC2 instance configurations.
    cat > /usr/local/sbin/configure-nat-firewall <<'SCRIPT'
    #!/bin/bash
    set -euo pipefail

    PRIMARY_IF="$(ip -o -4 route show to default | awk '{print $5; exit}')"

    if [[ -z "$PRIMARY_IF" ]]; then
        echo "Could not determine the primary network interface."
        exit 1
    fi

    # Remove our previous tables if this script is run again.
    nft list table ip nat >/dev/null 2>&1 && nft delete table ip nat || true
    nft list table inet nat_filter >/dev/null 2>&1 && nft delete table inet nat_filter || true

    # Build the NAT and forwarding rules.
    cat > /etc/nftables/nat-instance.nft <<NFT
    table ip nat {
        chain postrouting {
            type nat hook postrouting priority srcnat; policy accept;
            ip saddr ${var.private_subnet_cidr} oifname "$PRIMARY_IF" masquerade
        }
    }

    table inet nat_filter {
        chain forward {
            type filter hook forward priority filter; policy drop;
            ct state established,related accept
            iifname "$PRIMARY_IF" oifname "$PRIMARY_IF" ip saddr ${var.private_subnet_cidr} accept
        }
    }
    NFT

    # Load the firewall rules.
    nft -f /etc/nftables/nat-instance.nft
    SCRIPT

    chmod 700 /usr/local/sbin/configure-nat-firewall

    # Create a systemd service so the NAT rules are restored after reboot.
    cat > /etc/systemd/system/nat-firewall.service <<'UNIT'
    [Unit]
    Description=Private subnet NAT firewall rules
    Wants=network-online.target
    After=network-online.target

    [Service]
    Type=oneshot
    ExecStart=/usr/local/sbin/configure-nat-firewall
    RemainAfterExit=yes

    [Install]
    WantedBy=multi-user.target
    UNIT

    systemctl daemon-reload
    systemctl enable --now nat-firewall.service

    # Record successful NAT initialization in the system log.
    logger "Active Directory lab NAT instance initialization completed."
  USERDATA

  # Recreate the NAT instance if its bootstrap configuration changes.
  user_data_replace_on_change = true

  # Ensure the public route is available before installing packages.
  depends_on = [
    aws_route_table_association.public,
    aws_iam_role_policy_attachment.nat_ssm
  ]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-nat-instance"
    Role = "NAT"
  })
}