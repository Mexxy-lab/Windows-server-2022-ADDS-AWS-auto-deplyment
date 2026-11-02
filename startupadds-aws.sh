#!/usr/bin/env bash

# Deploy the AWS Windows AD lab using Terraform, SSM, and Ansible.
# Windows instances remain private; Ansible connects through SSM tunnels.

set -Eeuo pipefail
umask 077

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

# Locate the Terraform configuration without assuming the current directory.
if [[ -f "$PROJECT_DIR/versions.tf" && -f "$PROJECT_DIR/main.tf" ]]; then
    TERRAFORM_DIR="$PROJECT_DIR"
elif [[ -f "$PROJECT_DIR/aws-ad-lab-terraform/versions.tf" &&
        -f "$PROJECT_DIR/aws-ad-lab-terraform/main.tf" ]]; then
    TERRAFORM_DIR="$PROJECT_DIR/aws-ad-lab-terraform"
else
    echo "[ERROR] Could not locate Terraform configuration."
    exit 1
fi

# Store logs separately from Terraform state and temporary credentials.
LOG_DIR="$PROJECT_DIR/logs"
mkdir -p "$LOG_DIR"
chmod 700 "$LOG_DIR"
LOG_FILE="$LOG_DIR/startupadds-aws-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

# Temporary files and SSM tunnel processes are cleaned up on exit.
ANSIBLE_INVENTORY=""
TFPLAN_FILE=""
VAULT_PLAIN_FILE=""
BOOTSTRAP_SECRET_FILE=""
SSM_SCRIPT_FILE=""
SSM_PARAMS_FILE=""

DC_TUNNEL_PID=""
CLIENT_TUNNEL_PID=""
SUDO_KEEPALIVE_PID=""

# Track temporary hostname mappings used by Ansible through SSM tunnels.
DC_HOSTNAME="DC01"
CLIENT_HOSTNAME=""
HOSTS_BLOCK_ACTIVE=0

# ---------------------------------------------------------------------------
# Manage temporary /etc/hosts entries.
# ---------------------------------------------------------------------------

update_hosts_block() {
    local action="$1"
    local dc_hostname="${2:-DC01}"
    local client_hostname="${3:-}"

    if [[ "$action" == "remove" ]]; then
        # Never prompt for a password while the EXIT cleanup trap is running.
        sudo -n python3 - "$action" "$dc_hostname" "$client_hostname" <<'PY'
import os
import sys
import tempfile
from pathlib import Path

action, dc_hostname, client_hostname = sys.argv[1:4]

hosts_file = Path("/etc/hosts")
start_marker = "# BEGIN AWS-WINDOWS-ADLAB SSM HOSTS"
end_marker = "# END AWS-WINDOWS-ADLAB SSM HOSTS"

original = hosts_file.read_text(encoding="utf-8")
lines = original.splitlines()

kept_lines = []
inside_block = False

for line in lines:
    stripped = line.strip()

    if stripped == start_marker:
        if inside_block:
            raise SystemExit("ERROR: Nested /etc/hosts block marker found.")
        inside_block = True
        continue

    if stripped == end_marker:
        if not inside_block:
            raise SystemExit("ERROR: Unmatched /etc/hosts end marker found.")
        inside_block = False
        continue

    if not inside_block:
        kept_lines.append(line)

if inside_block:
    raise SystemExit("ERROR: Unclosed /etc/hosts block marker found.")

updated = "\n".join(kept_lines).rstrip() + "\n"

# Write atomically so /etc/hosts is never left partially written.
stat = hosts_file.stat()
fd, temporary_path = tempfile.mkstemp(
    prefix=".hosts.aws-ad-lab.",
    dir="/etc",
    text=True,
)

try:
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        handle.write(updated)
        handle.flush()
        os.fsync(handle.fileno())

    os.chown(temporary_path, stat.st_uid, stat.st_gid)
    os.chmod(temporary_path, stat.st_mode)
    os.replace(temporary_path, hosts_file)
finally:
    if os.path.exists(temporary_path):
        os.unlink(temporary_path)

print("Temporary AWS AD lab hostname mappings removed.")
PY
        return
    fi

    if [[ "$action" != "add" ]]; then
        echo "[ERROR] Invalid /etc/hosts action: $action"
        return 1
    fi

    # Add the temporary mappings after validating hostnames and conflicts.
    sudo python3 - "$action" "$dc_hostname" "$client_hostname" <<'PY'
import os
import re
import sys
import tempfile
from pathlib import Path

action, dc_hostname, client_hostname = sys.argv[1:4]

hosts_file = Path("/etc/hosts")
start_marker = "# BEGIN AWS-WINDOWS-ADLAB SSM HOSTS"
end_marker = "# END AWS-WINDOWS-ADLAB SSM HOSTS"

hostname_pattern = re.compile(r"^[A-Za-z0-9][A-Za-z0-9-]{0,14}$")

hostnames = [dc_hostname]

if client_hostname:
    hostnames.append(client_hostname)

for hostname in hostnames:
    if not hostname_pattern.fullmatch(hostname):
        raise SystemExit(f"ERROR: Invalid Windows hostname: {hostname}")

original = hosts_file.read_text(encoding="utf-8")
lines = original.splitlines()

kept_lines = []
inside_block = False

for line in lines:
    stripped = line.strip()

    if stripped == start_marker:
        if inside_block:
            raise SystemExit("ERROR: Nested /etc/hosts block marker found.")
        inside_block = True
        continue

    if stripped == end_marker:
        if not inside_block:
            raise SystemExit("ERROR: Unmatched /etc/hosts end marker found.")
        inside_block = False
        continue

    if not inside_block:
        kept_lines.append(line)

if inside_block:
    raise SystemExit("ERROR: Unclosed /etc/hosts block marker found.")

existing_loopback_aliases = set()

for line in kept_lines:
    content = line.split("#", 1)[0].strip()

    if not content:
        continue

    fields = content.split()

    if len(fields) < 2:
        continue

    address = fields[0]

    for alias in fields[1:]:
        normalized_alias = alias.casefold()

        for hostname in hostnames:
            if normalized_alias == hostname.casefold():
                if address != "127.0.0.1":
                    raise SystemExit(
                        f"ERROR: {hostname} already maps to {address} "
                        "in /etc/hosts. Refusing to overwrite it."
                    )

                existing_loopback_aliases.add(normalized_alias)

aliases_to_add = [
    hostname
    for hostname in hostnames
    if hostname.casefold() not in existing_loopback_aliases
]

updated_lines = list(kept_lines)

if aliases_to_add:
    if updated_lines and updated_lines[-1].strip():
        updated_lines.append("")

    updated_lines.append(start_marker)
    updated_lines.append("127.0.0.1 " + " ".join(aliases_to_add))
    updated_lines.append(end_marker)

updated = "\n".join(updated_lines).rstrip() + "\n"

stat = hosts_file.stat()

fd, temporary_path = tempfile.mkstemp(
    prefix=".hosts.aws-ad-lab.",
    dir="/etc",
    text=True,
)

try:
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        handle.write(updated)
        handle.flush()
        os.fsync(handle.fileno())

    os.chown(temporary_path, stat.st_uid, stat.st_gid)
    os.chmod(temporary_path, stat.st_mode)
    os.replace(temporary_path, hosts_file)
finally:
    if os.path.exists(temporary_path):
        os.unlink(temporary_path)

print("Temporary AWS AD lab hostname mappings installed.")

for hostname in hostnames:
    print(f"127.0.0.1 {hostname}")
PY
}

# ---------------------------------------------------------------------------
# Keep sudo authentication alive during long deployments.
# This allows the EXIT trap to remove temporary /etc/hosts entries.
# ---------------------------------------------------------------------------

start_sudo_keepalive() {
    echo "[INFO] Starting sudo credential keepalive..."

    (
        while sleep 60; do
            sudo -n -v || exit 0
        done
    ) >/dev/null 2>&1 &

    SUDO_KEEPALIVE_PID=$!
}

# ---------------------------------------------------------------------------
# Cleanup function.
# ---------------------------------------------------------------------------

cleanup() {
    echo "[INFO] Cleaning up temporary files and SSM tunnels..."

    # Stop the sudo keepalive process before cleaning up.
    if [[ -n "$SUDO_KEEPALIVE_PID" ]]; then
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
        wait "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
        SUDO_KEEPALIVE_PID=""
    fi

    # Remove only the temporary hostname mappings created by this deployment.
    if [[ "$HOSTS_BLOCK_ACTIVE" == "1" ]]; then
        echo "[INFO] Removing temporary Windows hostname mappings..."

        # Refresh sudo credentials if the session is still interactive.
        sudo -n -v 2>/dev/null || true

        update_hosts_block remove || {
            echo "[WARNING] Could not remove the temporary /etc/hosts block."
            echo "[WARNING] Manually remove the marked block if it remains."
        }

        HOSTS_BLOCK_ACTIVE=0
    fi

    # Stop remaining tunnels using their recorded process IDs and ports.
    if [[ -n "$DC_TUNNEL_PID" ]]; then
        stop_ssm_tunnel "$DC_TUNNEL_PID" 15986 "DC01" || true
        DC_TUNNEL_PID=""
    fi

    if [[ -n "$CLIENT_TUNNEL_PID" ]]; then
        stop_ssm_tunnel "$CLIENT_TUNNEL_PID" 15987 "Windows-client" || true
        CLIENT_TUNNEL_PID=""
    fi

    # Remove temporary files.
    [[ -z "$ANSIBLE_INVENTORY" ]] || rm -f -- "$ANSIBLE_INVENTORY"
    [[ -z "$TFPLAN_FILE" ]] || rm -f -- "$TFPLAN_FILE"
    [[ -z "$VAULT_PLAIN_FILE" ]] || rm -f -- "$VAULT_PLAIN_FILE"
    [[ -z "$BOOTSTRAP_SECRET_FILE" ]] || rm -f -- "$BOOTSTRAP_SECRET_FILE"
    [[ -z "$SSM_SCRIPT_FILE" ]] || rm -f -- "$SSM_SCRIPT_FILE"
    [[ -z "$SSM_PARAMS_FILE" ]] || rm -f -- "$SSM_PARAMS_FILE"
}

trap cleanup EXIT
# shellcheck disable=SC2154
trap 'rc=$?; echo "[ERROR] Failed at line $LINENO (exit $rc). Check $LOG_FILE."; exit "$rc"' ERR

echo "=================================================="
echo " Windows Server 2022 Active Directory DEPLOYMENT"
echo " AWS private-network architecture"
echo " Started: $(date)"
echo " Repository: $PROJECT_DIR"
echo " Terraform: $TERRAFORM_DIR"
echo "=================================================="

# ---------------------------------------------------------------------------
# 1. Activate the project virtual environment.
# ---------------------------------------------------------------------------

if [[ -f "$PROJECT_DIR/.venv/bin/activate" ]]; then
    # shellcheck disable=SC1091
    source "$PROJECT_DIR/.venv/bin/activate"
fi

for cmd in \
    terraform aws ansible-playbook ansible ansible-inventory \
    ansible-vault ansible-galaxy python3 session-manager-plugin setsid
do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "[ERROR] Required command not found: $cmd"
        exit 1
    }
done

python3 -c 'import yaml' || {
    echo "[ERROR] PyYAML is missing from the active Python environment."
    exit 1
}

# Validate required deployment files.
for file in \
    ansible.cfg requirements.yml inventory/hosts.ini \
    group_vars/windows.yml group_vars/vault.yml \
    playbooks/connection_test.yml \
    playbooks/domain_controller.yml \
    playbooks/domain_users.yml \
    playbooks/domain_client.yml \
    playbooks/validate_deployment.yml \
    playbooks/validate_client.yml \
    files/user_accounts_final.csv \
    scripts/Create-DomainUsers.ps1
do
    [[ -f "$PROJECT_DIR/$file" ]] || {
        echo "[ERROR] Required file missing: $file"
        exit 1
    }
done

# Locate the Ansible Vault password file.
VAULT_PASS_FILE="${ANSIBLE_VAULT_PASSWORD_FILE:-$HOME/.ansible_vault_pass}"

[[ -r "$VAULT_PASS_FILE" ]] || {
    echo "[ERROR] Missing readable Ansible Vault password file."
    echo "[ERROR] Set ANSIBLE_VAULT_PASSWORD_FILE or create ~/.ansible_vault_pass."
    exit 1
}

ansible-vault view "$PROJECT_DIR/group_vars/vault.yml" \
    --vault-password-file "$VAULT_PASS_FILE" >/dev/null

echo "[OK] Ansible Vault decryption check passed."

# Validate the Windows Administrator password without displaying it.
python3 - "$PROJECT_DIR/group_vars/vault.yml" "$VAULT_PASS_FILE" <<'PY'
import subprocess
import sys
import string
import yaml

vault_file, vault_pass_file = sys.argv[1:3]

result = subprocess.run(
    [
        "ansible-vault", "view", vault_file,
        "--vault-password-file", vault_pass_file,
    ],
    capture_output=True,
    text=True,
    check=True,
)

vault = yaml.safe_load(result.stdout)
password = vault.get("domain_admin_password", "") if isinstance(vault, dict) else ""

checks = {
    "length": 20 <= len(password) <= 64,
    "uppercase": any(c.isupper() for c in password),
    "lowercase": any(c.islower() for c in password),
    "digit": any(c.isdigit() for c in password),
    "symbol": any(c in string.punctuation for c in password),
    "no_whitespace": bool(password) and password == password.strip()
        and not any(c.isspace() for c in password),
    "no_account_or_domain_terms": not any(
        term in password.casefold()
        for term in ("administrator", "admin", "pumej", "pumejlab", "password")
    ),
    "ascii_only": password.isascii(),
}

failed = [name for name, passed in checks.items() if not passed]

if failed:
    print("ERROR: Windows password preflight failed: " + ", ".join(failed))
    sys.exit(1)

print("Windows password preflight passed.")
PY

# Install required Ansible collections.
echo "[INFO] Installing required Ansible collections..."
ansible-galaxy collection install -r "$PROJECT_DIR/requirements.yml"

# Run playbook syntax checks before Terraform deployment.
for playbook in \
    connection_test.yml \
    domain_controller.yml \
    domain_users.yml \
    domain_client.yml \
    validate_client.yml \
    validate_deployment.yml
do
    echo "[INFO] Syntax-checking playbooks/$playbook..."

    ansible-playbook "$PROJECT_DIR/playbooks/$playbook" \
        --syntax-check \
        --vault-password-file "$VAULT_PASS_FILE"
done

echo "[OK] Required Ansible playbooks passed syntax checks."

# ---------------------------------------------------------------------------
# 2. Verify AWS identity and review the Terraform plan.
# ---------------------------------------------------------------------------

echo "[INFO] Checking AWS identity..."
aws sts get-caller-identity

cd "$TERRAFORM_DIR"

terraform init
terraform fmt -check -recursive
terraform validate

TFPLAN_FILE="$(mktemp "$TERRAFORM_DIR/tfplan.XXXXXX")"

echo "[INFO] Creating a saved Terraform plan..."
terraform plan -out="$TFPLAN_FILE"

echo
echo "[WARNING] Review the complete Terraform plan above."
echo "[WARNING] This deployment creates billable AWS resources."
echo "[WARNING] Windows EC2 instances, NAT compute, storage, and public IPv4"
echo "[WARNING] addresses can incur charges while resources are running."
echo

if [[ "${JENKINS_AUTO_APPROVE:-false}" == "true" ]]; then
    echo "[INFO] Jenkins deployment approval received."
    CONFIRM="YES"
else
    read -r -p "Apply this exact Terraform plan? Type YES to continue: " CONFIRM
fi

if [[ "$CONFIRM" != "YES" ]]; then
    echo "[INFO] Cancelled before Terraform apply."
    exit 0
fi

# Apply only the exact saved plan that was reviewed.
terraform apply "$TFPLAN_FILE"

rm -f -- "$TFPLAN_FILE"
TFPLAN_FILE=""

# ---------------------------------------------------------------------------
# 3. Read Terraform outputs.
# ---------------------------------------------------------------------------

NAT_INSTANCE_ID="$(terraform output -raw nat_instance_id)"
NAT_PRIVATE_IP="$(terraform output -raw nat_private_ip)"
NAT_PUBLIC_IP="$(terraform output -raw nat_public_ip)"

DC_PRIVATE_IP="$(terraform output -raw dc01_private_ip)"
DC_INSTANCE_ID="$(terraform output -raw dc01_instance_id)"

SECRET_ARN="$(terraform output -raw bootstrap_secret_arn)"
AWS_REGION="$(terraform output -raw aws_region)"
DOMAIN_NAME="$(terraform output -raw domain_name)"

CLIENT_PRIVATE_IP="$(terraform output -raw windows_client_private_ip)"
CLIENT_INSTANCE_ID="$(terraform output -raw windows_client_instance_id)"

VPC_DNS_RESOLVER_IP="$(terraform output -raw vpc_dns_resolver_ip)"

echo "[OK] NAT instance: $NAT_INSTANCE_ID ($NAT_PRIVATE_IP)"
echo "[OK] NAT public IP: $NAT_PUBLIC_IP"
echo "[OK] DC01 instance: $DC_INSTANCE_ID ($DC_PRIVATE_IP)"

if [[ -n "$CLIENT_INSTANCE_ID" ]]; then
    echo "[OK] Windows client: $CLIENT_INSTANCE_ID ($CLIENT_PRIVATE_IP)"
else
    echo "[INFO] Optional Windows client is not deployed."
fi

# ---------------------------------------------------------------------------
# 4. Populate Secrets Manager with the encrypted Vault password.
# ---------------------------------------------------------------------------

VAULT_PLAIN_FILE="$(mktemp)"
BOOTSTRAP_SECRET_FILE="$(mktemp)"
chmod 600 "$VAULT_PLAIN_FILE" "$BOOTSTRAP_SECRET_FILE"

ansible-vault view "$PROJECT_DIR/group_vars/vault.yml" \
    --vault-password-file "$VAULT_PASS_FILE" > "$VAULT_PLAIN_FILE"

python3 - "$VAULT_PLAIN_FILE" "$BOOTSTRAP_SECRET_FILE" <<'PY'
import os
import sys
from pathlib import Path
import yaml

vault = yaml.safe_load(Path(sys.argv[1]).read_text(encoding="utf-8"))
password = vault.get("domain_admin_password") if isinstance(vault, dict) else None

if not isinstance(password, str) or not password or "\n" in password or "\r" in password:
    raise SystemExit("domain_admin_password is missing or invalid.")

Path(sys.argv[2]).write_text(password, encoding="utf-8")
os.chmod(sys.argv[2], 0o600)
PY

echo "[INFO] Updating the Secrets Manager bootstrap secret..."

aws secretsmanager put-secret-value \
    --region "$AWS_REGION" \
    --secret-id "$SECRET_ARN" \
    --secret-string "file://$BOOTSTRAP_SECRET_FILE" >/dev/null

rm -f -- "$VAULT_PLAIN_FILE" "$BOOTSTRAP_SECRET_FILE"
VAULT_PLAIN_FILE=""
BOOTSTRAP_SECRET_FILE=""

echo "[OK] Bootstrap secret populated."

# ---------------------------------------------------------------------------
# 5. SSM helper functions.
# ---------------------------------------------------------------------------

wait_for_ssm() {
    local instance_id="$1"
    local label="$2"
    local attempt
    local status

    echo "[INFO] Waiting for SSM Online: $label ($instance_id)..."

    for attempt in $(seq 1 90); do
        status="$(aws ssm describe-instance-information \
            --region "$AWS_REGION" \
            --filters "Key=InstanceIds,Values=$instance_id" \
            --query 'InstanceInformationList[0].PingStatus' \
            --output text 2>/dev/null || true)"

        if [[ "$status" == "Online" ]]; then
            echo "[OK] $label is Online in SSM."
            return 0
        fi

        echo "[INFO] $label SSM status: ${status:-unknown} ($attempt/90)"
        sleep 10
    done

    echo "[ERROR] $label did not register with SSM."
    return 1
}

SSM_STDOUT=""
SSM_STDERR=""

run_ssm_script() {
    local instance_id="$1"
    local label="$2"
    local document="$3"
    local script="$4"
    local timeout_seconds="${5:-900}"
    local command_id
    local status
    local attempt

    SSM_PARAMS_FILE="$(mktemp)"
    chmod 600 "$SSM_PARAMS_FILE"

    python3 - "$SSM_PARAMS_FILE" "$script" <<'PY'
import json
import sys
from pathlib import Path

Path(sys.argv[1]).write_text(
    json.dumps({"commands": [sys.argv[2]]}),
    encoding="utf-8",
)
PY

    echo "[INFO] Sending SSM command to $label..."

    # Submit the command and capture any AWS CLI error.
    if ! command_id="$(aws ssm send-command \
        --region "$AWS_REGION" \
        --instance-ids "$instance_id" \
        --document-name "$document" \
        --comment "AWS AD lab deployment automation" \
        --timeout-seconds "$timeout_seconds" \
        --parameters "file://$SSM_PARAMS_FILE" \
        --query 'Command.CommandId' \
        --output text)"; then

        rm -f -- "$SSM_PARAMS_FILE"
        SSM_PARAMS_FILE=""

        echo "[ERROR] Failed to submit SSM command to $label."
        return 1
    fi

    # Reject an empty or invalid command ID before polling.
    if [[ -z "$command_id" || "$command_id" == "None" ]]; then
        rm -f -- "$SSM_PARAMS_FILE"
        SSM_PARAMS_FILE=""

        echo "[ERROR] AWS SSM did not return a valid command ID for $label."
        return 1
    fi

    rm -f -- "$SSM_PARAMS_FILE"
    SSM_PARAMS_FILE=""

    for attempt in $(seq 1 180); do
        status="$(aws ssm get-command-invocation \
            --region "$AWS_REGION" \
            --command-id "$command_id" \
            --instance-id "$instance_id" \
            --query Status \
            --output text 2>/dev/null || true)"

        case "$status" in
            Success)
                SSM_STDOUT="$(aws ssm get-command-invocation \
                    --region "$AWS_REGION" \
                    --command-id "$command_id" \
                    --instance-id "$instance_id" \
                    --query StandardOutputContent \
                    --output text 2>/dev/null || true)"

                SSM_STDERR="$(aws ssm get-command-invocation \
                    --region "$AWS_REGION" \
                    --command-id "$command_id" \
                    --instance-id "$instance_id" \
                    --query StandardErrorContent \
                    --output text 2>/dev/null || true)"

                echo "[OK] SSM command succeeded on $label."
                return 0
                ;;

            Failed|Cancelled|TimedOut|DeliveryTimedOut|ExecutionTimedOut|Undeliverable)
                SSM_STDOUT="$(aws ssm get-command-invocation \
                    --region "$AWS_REGION" \
                    --command-id "$command_id" \
                    --instance-id "$instance_id" \
                    --query StandardOutputContent \
                    --output text 2>/dev/null || true)"

                SSM_STDERR="$(aws ssm get-command-invocation \
                    --region "$AWS_REGION" \
                    --command-id "$command_id" \
                    --instance-id "$instance_id" \
                    --query StandardErrorContent \
                    --output text 2>/dev/null || true)"

                echo "[ERROR] SSM command status on $label: $status"
                echo "[ERROR] Standard output: $SSM_STDOUT"
                echo "[ERROR] Standard error: $SSM_STDERR"
                return 1
                ;;

            *)
                echo "[INFO] $label SSM command status: ${status:-Pending} ($attempt/180)"
                sleep 5
                ;;
        esac
    done

    echo "[ERROR] Timed out waiting for SSM command on $label."
    return 1
}

# ---------------------------------------------------------------------------
# 6. Wait for NAT initialization.
# ---------------------------------------------------------------------------

wait_for_ssm "$NAT_INSTANCE_ID" "NAT instance"

NAT_READY_SCRIPT=$(cat <<'NAT_SCRIPT'
#!/bin/bash
set -e

cloud-init status --wait

test "$(sysctl -n net.ipv4.ip_forward)" = "1"

nft list ruleset | grep -q 'masquerade'

echo "NAT_READY: cloud-init completed, forwarding enabled, masquerade present."
NAT_SCRIPT
)

run_ssm_script \
    "$NAT_INSTANCE_ID" \
    "NAT instance" \
    "AWS-RunShellScript" \
    "$NAT_READY_SCRIPT" \
    900

if ! grep -q "NAT_READY:" <<< "$SSM_STDOUT"; then
    echo "[ERROR] NAT instance did not pass its readiness checks."
    echo "$SSM_STDOUT"
    exit 1
fi

echo "[OK] NAT instance is initialized."

# ---------------------------------------------------------------------------
# 7. Wait for Windows SSM registration.
# ---------------------------------------------------------------------------

wait_for_ssm "$DC_INSTANCE_ID" "DC01"

if [[ -n "$CLIENT_INSTANCE_ID" ]]; then
    wait_for_ssm "$CLIENT_INSTANCE_ID" "Windows client"
fi

# ---------------------------------------------------------------------------
# 8. Set DC01 hostname through SSM before opening the WinRM tunnel.
# ---------------------------------------------------------------------------

RENAME_DC_SCRIPT=$(cat <<'POWERSHELL'
$ErrorActionPreference = 'Stop'

if ($env:COMPUTERNAME -ne 'DC01') {
    Rename-Computer -NewName 'DC01' -Force
    Write-Output 'HOSTNAME_CHANGE: DC01'
    shutdown.exe /r /t 30 /f
}
else {
    Write-Output 'HOSTNAME_OK: DC01'
}
POWERSHELL
)

echo "[INFO] Checking the DC01 hostname..."

run_ssm_script \
    "$DC_INSTANCE_ID" \
    "DC01" \
    "AWS-RunPowerShellScript" \
    "$RENAME_DC_SCRIPT" \
    300

if grep -q "HOSTNAME_CHANGE:" <<< "$SSM_STDOUT"; then
    echo "[INFO] DC01 hostname changed. Waiting for its reboot..."
    sleep 40
    wait_for_ssm "$DC_INSTANCE_ID" "DC01 after hostname change"
else
    echo "[OK] DC01 already has the correct hostname."
fi

# ---------------------------------------------------------------------------
# 9. Bootstrap WinRM HTTPS on Windows using SSM.
# ---------------------------------------------------------------------------

bootstrap_instance() {
    local instance_id="$1"
    local label="$2"

    wait_for_ssm "$instance_id" "$label"

    SSM_SCRIPT_FILE="$(mktemp)"
    chmod 600 "$SSM_SCRIPT_FILE"

    python3 - "$SSM_SCRIPT_FILE" "$SECRET_ARN" "$AWS_REGION" <<'PY'
import sys
from pathlib import Path

out_path, secret_arn, region = sys.argv[1:4]

script = r'''
$ErrorActionPreference = "Stop"
$secretArn = '__SECRET_ARN__'
$region = '__AWS_REGION__'

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$aws = Join-Path $env:ProgramFiles 'Amazon\AWSCLIV2\aws.exe'

if (-not (Test-Path $aws)) {
    $msi = Join-Path $env:TEMP 'AWSCLIV2.msi'

    Invoke-WebRequest `
        -Uri 'https://awscli.amazonaws.com/AWSCLIV2.msi' `
        -OutFile $msi

    $installer = Start-Process -FilePath 'msiexec.exe' `
        -ArgumentList @('/i', $msi, '/qn', '/norestart') `
        -Wait -PassThru

    Remove-Item $msi -Force -ErrorAction SilentlyContinue

    if ($installer.ExitCode -notin @(0, 3010)) {
        throw 'AWS CLI installation failed.'
    }

    if (-not (Test-Path $aws)) {
        throw 'AWS CLI was not found after installation.'
    }
}

$env:AWS_DEFAULT_REGION = $region

$password = & $aws secretsmanager get-secret-value `
    --secret-id $secretArn `
    --query SecretString `
    --output text

if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($password)) {
    throw 'Could not retrieve the bootstrap secret.'
}

$securePassword = ConvertTo-SecureString $password -AsPlainText -Force

Set-LocalUser -Name 'Administrator' -Password $securePassword
Enable-LocalUser -Name 'Administrator'

$password = $null
$securePassword = $null

Enable-PSRemoting -Force -SkipNetworkProfileCheck

Set-Service -Name WinRM -StartupType Automatic
Start-Service -Name WinRM

Set-Item WSMan:\localhost\Service\Auth\Basic $false
Set-Item WSMan:\localhost\Service\Auth\Negotiate $true
Set-Item WSMan:\localhost\Service\AllowUnencrypted $false

$listener = Get-WSManInstance `
    -ResourceURI winrm/config/Listener `
    -Enumerate |
    Where-Object {
        $_.Transport -eq 'HTTPS' -and $_.Address -eq '*'
    } |
    Select-Object -First 1

if (-not $listener) {
    $cert = New-SelfSignedCertificate `
        -DnsName $env:COMPUTERNAME `
        -CertStoreLocation 'Cert:\LocalMachine\My' `
        -KeyAlgorithm RSA `
        -KeyLength 2048 `
        -NotAfter (Get-Date).AddYears(2)

    New-WSManInstance `
        -ResourceURI winrm/config/Listener `
        -SelectorSet @{ Address='*'; Transport='HTTPS' } `
        -ValueSet @{
            Hostname = $env:COMPUTERNAME
            CertificateThumbprint = $cert.Thumbprint
        } | Out-Null
}

if (-not (Get-NetFirewallRule -Name 'WinRM-HTTPS-In-TCP' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule `
        -Name 'WinRM-HTTPS-In-TCP' `
        -DisplayName 'Windows Remote Management (HTTPS-In)' `
        -Enabled True `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort 5986 `
        -Action Allow `
        -Profile Any | Out-Null
}

Write-Output 'WINRM_BOOTSTRAP_OK'
'''

script = script.replace('__SECRET_ARN__', secret_arn)
script = script.replace('__AWS_REGION__', region)

Path(out_path).write_text(script, encoding="utf-8")
PY

    echo "[INFO] Bootstrapping WinRM HTTPS on $label..."

    run_ssm_script \
        "$instance_id" \
        "$label" \
        "AWS-RunPowerShellScript" \
        "$(cat "$SSM_SCRIPT_FILE")" \
        900

    rm -f -- "$SSM_SCRIPT_FILE"
    SSM_SCRIPT_FILE=""

    if ! grep -q "WINRM_BOOTSTRAP_OK" <<< "$SSM_STDOUT"; then
        echo "[ERROR] WinRM bootstrap did not report success on $label."
        echo "$SSM_STDOUT"
        return 1
    fi
}

bootstrap_instance "$DC_INSTANCE_ID" "DC01"

if [[ -n "$CLIENT_INSTANCE_ID" ]]; then
    bootstrap_instance "$CLIENT_INSTANCE_ID" "Windows client"
fi

# ---------------------------------------------------------------------------
# 9A. Discover the optional Windows client hostname through SSM.
# ---------------------------------------------------------------------------

if [[ -n "$CLIENT_INSTANCE_ID" ]]; then
    echo "[INFO] Discovering the Windows client hostname through SSM..."

    CLIENT_HOSTNAME_SCRIPT=$(cat <<'POWERSHELL'
$ErrorActionPreference = 'Stop'
Write-Output "CLIENT_HOSTNAME:$env:COMPUTERNAME"
POWERSHELL
)

    run_ssm_script \
        "$CLIENT_INSTANCE_ID" \
        "Windows client hostname discovery" \
        "AWS-RunPowerShellScript" \
        "$CLIENT_HOSTNAME_SCRIPT" \
        120

    CLIENT_HOSTNAME="$(
        sed -n 's/^CLIENT_HOSTNAME://p' <<< "$SSM_STDOUT" |
        tr -d '\r' |
        tail -n 1
    )"

    if [[ ! "$CLIENT_HOSTNAME" =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,14}$ ]]; then
        echo "[ERROR] Invalid or missing Windows client hostname."
        echo "[ERROR] SSM output: $SSM_STDOUT"
        exit 1
    fi

    echo "[OK] Windows client hostname: $CLIENT_HOSTNAME"
fi

# ---------------------------------------------------------------------------
# 9B. Prepare temporary hostname mappings and sudo cleanup permissions.
# ---------------------------------------------------------------------------

echo "[INFO] Preparing temporary Windows hostname mappings..."

sudo -v
start_sudo_keepalive

update_hosts_block add "$DC_HOSTNAME" "$CLIENT_HOSTNAME"
HOSTS_BLOCK_ACTIVE=1

echo "[OK] Temporary hostname mappings created."

# ---------------------------------------------------------------------------
# 10. SSM tunnel management.
# ---------------------------------------------------------------------------

# Check whether a local TCP port can be bound.
# SO_REUSEADDR avoids unnecessary failures caused by recently closed sockets.
port_is_free() {
    python3 - "$1" <<'PY'
import socket
import sys

port = int(sys.argv[1])

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

    try:
        sock.bind(("127.0.0.1", port))
    except OSError:
        raise SystemExit(1)
PY
}

# Check whether the local SSM forwarding port is accepting connections.
port_is_listening() {
    python3 - "$1" <<'PY'
import socket
import sys

with socket.create_connection(("127.0.0.1", int(sys.argv[1])), timeout=2):
    pass
PY
}

# Start an SSM port-forwarding session and verify that its local port opens.
start_ssm_tunnel() {
    local instance_id="$1"
    local local_port="$2"
    local label="$3"
    local log_file="$LOG_DIR/ssm-${label// /-}-${local_port}.log"
    local attempt
    local pid
    local port_ready=false

    echo "[INFO] Checking local port $local_port before starting $label tunnel..."

    # Wait up to 30 seconds for a previous SSM plugin to release the port.
    for attempt in $(seq 1 30); do
        if port_is_free "$local_port"; then
            port_ready=true
            break
        fi

        echo "[INFO] Port $local_port is still occupied ($attempt/30). Waiting..."
        sleep 1
    done

    if [[ "$port_ready" != true ]]; then
        echo "[ERROR] Port $local_port remained occupied after 30 seconds."
        echo "[INFO] Current listener information:"
        sudo ss -ltnp | grep ":$local_port " || true
        return 1
    fi

    echo "[INFO] Starting SSM tunnel for $label on 127.0.0.1:$local_port..."

    # setsid creates a separate process group so cleanup can terminate both
    # AWS CLI and its Session Manager plugin.
    setsid aws ssm start-session \
        --region "$AWS_REGION" \
        --target "$instance_id" \
        --document-name "AWS-StartPortForwardingSession" \
        --parameters "{\"portNumber\":[\"5986\"],\"localPortNumber\":[\"$local_port\"]}" \
        </dev/null >"$log_file" 2>&1 &

    pid=$!

    if [[ "$label" == "DC01" ]]; then
        DC_TUNNEL_PID="$pid"
    else
        CLIENT_TUNNEL_PID="$pid"
    fi

    # Wait for the Session Manager plugin to open the local port.
    for attempt in $(seq 1 60); do
        if port_is_listening "$local_port" 2>/dev/null; then
            echo "[OK] SSM tunnel established for $label."
            return 0
        fi

        if ! kill -0 "$pid" 2>/dev/null; then
            echo "[ERROR] SSM tunnel process exited for $label."
            echo "[ERROR] Review $log_file"
            return 1
        fi

        echo "[INFO] Waiting for $label tunnel ($attempt/60)..."
        sleep 2
    done

    echo "[ERROR] SSM tunnel did not open local port $local_port."
    echo "[ERROR] Review $log_file"
    return 1
}

# Stop an SSM tunnel and wait until its listening port is released.
# Stop an SSM tunnel and verify that its process group and local port are released.
stop_ssm_tunnel() {
    local pid="$1"
    local local_port="$2"
    local label="$3"
    local attempt

    if [[ -z "$pid" ]]; then
        echo "[INFO] No active process recorded for $label tunnel."
        return 0
    fi

    # Refuse to signal anything unless the recorded PID is numeric.
    if [[ ! "$pid" =~ ^[0-9]+$ ]]; then
        echo "[ERROR] Invalid tunnel PID for $label: $pid"
        return 1
    fi

    echo "[INFO] Stopping $label SSM tunnel (PID $pid)..."

    # Gracefully terminate the complete process group.
    kill -TERM -- "-$pid" 2>/dev/null || true

    # Allow the AWS CLI and Session Manager plugin time to exit.
    for attempt in $(seq 1 10); do
        if ! kill -0 -- "-$pid" 2>/dev/null; then
            break
        fi

        sleep 1
    done

    # Force termination if any process in the group remains.
    if kill -0 -- "-$pid" 2>/dev/null; then
        echo "[WARNING] $label tunnel did not stop gracefully; sending KILL."
        kill -KILL -- "-$pid" 2>/dev/null || true
    fi

    # Reap the AWS CLI process if it is still our child.
    wait "$pid" 2>/dev/null || true

    # Verify that the local forwarding port is released.
    for attempt in $(seq 1 20); do
        if port_is_free "$local_port"; then
            echo "[OK] Port $local_port released for $label."
            return 0
        fi

        echo "[INFO] Waiting for $label tunnel to release port $local_port ($attempt/20)..."
        sleep 1
    done

    echo "[ERROR] $label tunnel did not release port $local_port."
    sudo ss -ltnp | grep ":$local_port " || true
    return 1
}

# ---------------------------------------------------------------------------
# 11. Open the initial SSM tunnels.
# ---------------------------------------------------------------------------

start_ssm_tunnel "$DC_INSTANCE_ID" 15986 "DC01"

if [[ -n "$CLIENT_INSTANCE_ID" ]]; then
    start_ssm_tunnel "$CLIENT_INSTANCE_ID" 15987 "Windows-client"
fi

# ---------------------------------------------------------------------------
# 12. Generate the temporary Ansible inventory.
# ---------------------------------------------------------------------------

ANSIBLE_INVENTORY="$(mktemp)"
chmod 600 "$ANSIBLE_INVENTORY"

cat > "$ANSIBLE_INVENTORY" <<EOF
[domain_controller]
dc01 ansible_host=${DC_HOSTNAME} ansible_port=15986

[windows_clients]
EOF

if [[ -n "$CLIENT_INSTANCE_ID" ]]; then
    printf 'windowsclient_01 ansible_host=%s ansible_port=15987\n' \
        "$CLIENT_HOSTNAME" >> "$ANSIBLE_INVENTORY"
fi

cat >> "$ANSIBLE_INVENTORY" <<'EOF'

[windows:children]
domain_controller
windows_clients

[windows:vars]
ansible_connection=winrm
ansible_winrm_scheme=https
ansible_winrm_transport=ntlm
ansible_winrm_server_cert_validation=ignore
ansible_user=Administrator
EOF

cd "$PROJECT_DIR"

inventory_graph="$(ansible-inventory -i "$ANSIBLE_INVENTORY" --graph 2>&1)" || {
    echo "[ERROR] Ansible could not parse the generated AWS inventory."
    echo "$inventory_graph"
    exit 1
}

echo "$inventory_graph"

grep -q 'dc01' <<< "$inventory_graph" || {
    echo "[ERROR] Generated inventory does not contain dc01."
    exit 1
}

if [[ -n "$CLIENT_INSTANCE_ID" ]]; then
    grep -q 'windowsclient_01' <<< "$inventory_graph" || {
        echo "[ERROR] Generated inventory does not contain windowsclient_01."
        exit 1
    }
fi

echo "[OK] Generated AWS inventory contains the expected hosts."

# Confirm each Windows hostname resolves to the local SSM tunnel address.
python3 - "$DC_HOSTNAME" "$CLIENT_HOSTNAME" "$CLIENT_INSTANCE_ID" <<'PY'
import socket
import sys

dc_hostname, client_hostname, client_instance_id = sys.argv[1:4]

targets = [(dc_hostname, 15986)]

if client_instance_id:
    targets.append((client_hostname, 15987))

for hostname, port in targets:
    addresses = {
        result[4][0]
        for result in socket.getaddrinfo(
            hostname,
            port,
            family=socket.AF_INET,
            type=socket.SOCK_STREAM,
        )
    }

    if addresses != {"127.0.0.1"}:
        raise SystemExit(
            f"ERROR: {hostname} does not resolve exclusively to 127.0.0.1. "
            f"Resolved addresses: {sorted(addresses)}"
        )

    print(f"[OK] {hostname}:{port} resolves to 127.0.0.1.")
PY

# ---------------------------------------------------------------------------
# 13. Test initial WinRM connectivity.
# ---------------------------------------------------------------------------

echo "[INFO] Testing authenticated WinRM connectivity..."

ansible-playbook \
    -i "$ANSIBLE_INVENTORY" \
    playbooks/connection_test.yml \
    --vault-password-file "$VAULT_PASS_FILE"

# ---------------------------------------------------------------------------
# 14. Promote the domain controller.
# ---------------------------------------------------------------------------

echo "[INFO] Configuring Active Directory Domain Services..."

ansible-playbook \
    -i "$ANSIBLE_INVENTORY" \
    playbooks/domain_controller.yml \
    --limit domain_controller \
    --vault-password-file "$VAULT_PASS_FILE"

# ---------------------------------------------------------------------------
# 15. Reboot Windows through SSM with a visible countdown.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Reboot a Windows instance through SSM and verify the complete reboot cycle.
# ---------------------------------------------------------------------------

reboot_via_ssm() {
    local instance_id="$1"
    local label="$2"
    local countdown=60
    local remaining
    local attempt
    local status
    local pre_boot_time
    local current_boot_time
    local boot_changed=false
    local boot_query

    # Query Windows for its last boot time in a consistent UTC format.
    # Comparing this value is more reliable than waiting for SSM to report Offline.
    # shellcheck disable=SC2016
    boot_query='$ErrorActionPreference = "Stop"; (Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime.ToUniversalTime().ToString("o")'

    echo
    echo "=================================================="
    echo "[INFO] Requesting reboot of $label through AWS SSM"
    echo "=================================================="

    # Confirm that SSM can currently communicate with the instance.
    status="$(aws ssm describe-instance-information \
        --region "$AWS_REGION" \
        --filters "Key=InstanceIds,Values=$instance_id" \
        --query 'InstanceInformationList[0].PingStatus' \
        --output text 2>/dev/null || true)"

    if [[ "$status" != "Online" ]]; then
        echo "[ERROR] $label is not Online before reboot. Current status: $status"
        return 1
    fi

    # Capture the boot time before restarting Windows.
    echo "[INFO] Recording the current Windows boot time on $label..."

    if ! run_ssm_script \
        "$instance_id" \
        "$label" \
        "AWS-RunPowerShellScript" \
        "$boot_query" \
        180; then

        echo "[ERROR] Could not retrieve the pre-reboot boot time for $label."
        return 1
    fi

    pre_boot_time="$(printf '%s\n' "$SSM_STDOUT" |
        tr -d '\r' |
        awk 'NF { value=$0 } END { print value }')"

    if [[ -z "$pre_boot_time" || "$pre_boot_time" == "None" ]]; then
        echo "[ERROR] Could not parse the pre-reboot boot time for $label."
        echo "[ERROR] SSM output: $SSM_STDOUT"
        return 1
    fi

    echo "[INFO] Previous Windows boot time: $pre_boot_time"

    # Schedule the Windows restart.
    if ! run_ssm_script \
        "$instance_id" \
        "$label" \
        "AWS-RunPowerShellScript" \
        "shutdown.exe /r /t 45 /f" \
        180; then

        echo "[ERROR] Could not schedule the reboot of $label."
        return 1
    fi

    # Wait beyond the 45-second Windows shutdown timer.
    # Log progress every 10 seconds instead of every second.
    for ((remaining=countdown; remaining>0; remaining--)); do

        if (( remaining % 10 == 0 || remaining == 1 )); then
            printf '[INFO] %s restarting in %02d seconds...\n' \
                "$label" "$remaining"
        fi

        sleep 1
    done

    echo "[INFO] $label shutdown countdown completed."

    # Poll Windows boot time until it changes.
    # SSM may remain Online throughout a reboot, so an Offline transition
    # is deliberately not required.
    echo "[INFO] Checking for a changed Windows boot time on $label..."

    local start_seconds=$SECONDS

    for attempt in $(seq 1 90); do
        if run_ssm_script \
            "$instance_id" \
            "$label" \
            "AWS-RunPowerShellScript" \
            "$boot_query" \
            180; then

            current_boot_time="$(printf '%s\n' "$SSM_STDOUT" |
                tr -d '\r' |
                awk 'NF { value=$0 } END { print value }')"

            if [[ -n "$current_boot_time" &&
                  "$current_boot_time" != "None" &&
                  "$current_boot_time" != "$pre_boot_time" ]]; then

                boot_changed=true
                echo "[OK] $label reboot verified."
                echo "[INFO] Previous boot time: $pre_boot_time"
                echo "[INFO] Current boot time:  $current_boot_time"
                break
            fi

            echo "[INFO] Windows is responding; boot time has not changed yet ($attempt/90)."
        else
            echo "[WARN] Could not retrieve boot time from $label ($attempt/90)."
        fi

        # Limit the overall verification period to approximately 15 minutes.
        if (( SECONDS - start_seconds >= 900 )); then
            break
        fi

        sleep 10
    done

    if [[ "$boot_changed" != true ]]; then
        echo "[ERROR] Could not verify a changed Windows boot time on $label."
        echo "[ERROR] Previous boot time: $pre_boot_time"
        echo "[ERROR] Last observed boot time: ${current_boot_time:-unknown}"
        return 1
    fi

    return 0
}

# Stop the DC tunnel before rebooting it.
stop_ssm_tunnel "$DC_TUNNEL_PID" 15986 "DC01"
DC_TUNNEL_PID=""

echo "[INFO] Rebooting DC01 after AD DS promotion..."
reboot_via_ssm "$DC_INSTANCE_ID" "DC01"

# ---------------------------------------------------------------------------
# 16. Wait for AD DS, DNS, and AD Web Services to become ready.
# ---------------------------------------------------------------------------

wait_for_ad_ready() {
    local instance_id="$1"
    local label="$2"
    local attempt
    local script

    script=$(cat <<'POWERSHELL'
$ErrorActionPreference = 'Stop'
$domain = '__DOMAIN_NAME__'

try {
    $services = Get-Service -Name NTDS,DNS,ADWS -ErrorAction Stop
    $stopped = @($services | Where-Object { $_.Status -ne 'Running' })

    if ($stopped.Count -gt 0) {
        $details = (($stopped | ForEach-Object {
            $_.Name + '=' + $_.Status
        }) -join ', ')

        Write-Output "AD_NOT_READY: $details"
        exit 0
    }

    Import-Module ActiveDirectory -ErrorAction Stop
    $null = Get-ADDomain -Identity $domain -ErrorAction Stop

    Write-Output "AD_READY: Domain $domain is ready."
}
catch {
    Write-Output ("AD_NOT_READY: " + $_.Exception.Message)
}
POWERSHELL
)

    script="${script//__DOMAIN_NAME__/$DOMAIN_NAME}"

    echo "[INFO] Waiting for Active Directory readiness on $label..."

    for attempt in $(seq 1 30); do
        wait_for_ssm "$instance_id" "$label"

        if run_ssm_script \
            "$instance_id" \
            "$label" \
            "AWS-RunPowerShellScript" \
            "$script" \
            120; then

            if grep -q "AD_READY:" <<< "$SSM_STDOUT"; then
                echo "[OK] AD DS, DNS, and AD Web Services are ready."
                echo "$SSM_STDOUT"
                return 0
            fi

            echo "[INFO] Active Directory is not ready yet."
            echo "$SSM_STDOUT"
        fi

        echo "[INFO] Retrying AD readiness check ($attempt/30)..."
        sleep 20
    done

    echo "[ERROR] Active Directory did not become ready."
    return 1
}

wait_for_ad_ready "$DC_INSTANCE_ID" "DC01"

# ---------------------------------------------------------------------------
# 17. Configure DNS forwarding and Amazon Time Sync.
# ---------------------------------------------------------------------------

echo "[INFO] Configuring DC01 DNS forwarding and time synchronization..."

DC_NETWORK_SCRIPT=$(cat <<'POWERSHELL'
$ErrorActionPreference = 'Stop'

$forwarder = '__VPC_DNS_RESOLVER_IP__'

$currentForwarders = @(
    Get-DnsServerForwarder |
    Select-Object -ExpandProperty IPAddress |
    ForEach-Object { $_.IPAddressToString }
)

if ($forwarder -notin $currentForwarders) {
    Add-DnsServerForwarder -IPAddress $forwarder
}

& w32tm.exe /config `
    /manualpeerlist:"169.254.169.123,0x8" `
    /syncfromflags:manual `
    /reliable:yes `
    /update

if ($LASTEXITCODE -ne 0) {
    throw "Failed to configure the Windows Time service."
}

Restart-Service -Name W32Time

& w32tm.exe /resync /rediscover

if ($LASTEXITCODE -ne 0) {
    throw "Windows Time synchronization request failed."
}

Write-Output "DNS_FORWARDER_CONFIGURED: $forwarder"
Write-Output "AMAZON_TIME_SYNC_CONFIGURED: 169.254.169.123"
POWERSHELL
)

DC_NETWORK_SCRIPT="${DC_NETWORK_SCRIPT//__VPC_DNS_RESOLVER_IP__/$VPC_DNS_RESOLVER_IP}"

run_ssm_script \
    "$DC_INSTANCE_ID" \
    "DC01 DNS and time configuration" \
    "AWS-RunPowerShellScript" \
    "$DC_NETWORK_SCRIPT" \
    180

grep -q "DNS_FORWARDER_CONFIGURED:" <<< "$SSM_STDOUT" || {
    echo "[ERROR] DC01 DNS forwarder configuration was not confirmed."
    exit 1
}

grep -q "AMAZON_TIME_SYNC_CONFIGURED:" <<< "$SSM_STDOUT" || {
    echo "[ERROR] DC01 time configuration was not confirmed."
    exit 1
}

echo "[OK] DNS forwarding and Amazon Time Sync configuration completed."
echo "$SSM_STDOUT"

# Reopen the DC tunnel after the reboot and AD readiness check.
start_ssm_tunnel "$DC_INSTANCE_ID" 15986 "DC01"

# Test post-promotion access using the domain Administrator account.
echo "[INFO] Verifying domain Administrator WinRM access..."

ansible-playbook \
    -i "$ANSIBLE_INVENTORY" \
    playbooks/connection_test.yml \
    --limit dc01 \
    -e 'ansible_user=PUMEJLAB\Administrator' \
    --vault-password-file "$VAULT_PASS_FILE"

# ---------------------------------------------------------------------------
# 18. Create organizational units and import domain users.
# ---------------------------------------------------------------------------

echo "[INFO] Creating OUs and importing domain users..."

ansible-playbook \
    -i "$ANSIBLE_INVENTORY" \
    playbooks/domain_users.yml \
    --vault-password-file "$VAULT_PASS_FILE"

# ---------------------------------------------------------------------------
# 19. Join the optional Windows client to the AD domain.
# ---------------------------------------------------------------------------

if [[ -n "$CLIENT_INSTANCE_ID" ]]; then
    echo "[INFO] Configuring the Windows client DNS and joining the domain..."

    # The AWS DC address is supplied as an override.
    # The shared windows.yml values remain unchanged for the Vagrant lab.
    ansible-playbook \
        -i "$ANSIBLE_INVENTORY" \
        playbooks/domain_client.yml \
        --vault-password-file "$VAULT_PASS_FILE" \
        -e "domain_dns_server=$DC_PRIVATE_IP"

    # The client playbook must not use win_reboot.
    # Stop the existing SSM tunnel before rebooting the client.
    stop_ssm_tunnel "$CLIENT_TUNNEL_PID" 15987 "Windows-client"
    CLIENT_TUNNEL_PID=""

    echo "[INFO] Rebooting the Windows client through SSM..."

    reboot_via_ssm "$CLIENT_INSTANCE_ID" "Windows client"

    # Reopen the client tunnel after it returns to SSM Online.
    start_ssm_tunnel "$CLIENT_INSTANCE_ID" 15987 "Windows-client"

else
    echo "[INFO] Skipping client join; no Windows client was deployed."
fi

# ---------------------------------------------------------------------------
# 20. Final Active Directory validation.
# ---------------------------------------------------------------------------

echo "[INFO] Running final Active Directory validation..."

# Validate the domain controller, domain, and imported users.
ansible-playbook \
    -i "$ANSIBLE_INVENTORY" \
    playbooks/validate_deployment.yml \
    --vault-password-file "$VAULT_PASS_FILE"

# Only validate client membership when a Windows client was deployed.
if [[ -n "$CLIENT_INSTANCE_ID" ]]; then
    echo "[INFO] Validating Windows client domain membership..."

    ansible-playbook \
        -i "$ANSIBLE_INVENTORY" \
        playbooks/validate_client.yml \
        --vault-password-file "$VAULT_PASS_FILE"
else
    echo "[INFO] Skipping client validation; no Windows client was deployed."
fi

# ---------------------------------------------------------------------------
# 21. Deployment completion.
# ---------------------------------------------------------------------------

echo
echo "=================================================="
echo "[SUCCESS] AWS Active Directory deployment completed."
echo "Domain: $DOMAIN_NAME"
echo "Domain Controller: $DC_PRIVATE_IP"
echo "NAT private IP: $NAT_PRIVATE_IP"
echo "NAT public IP: $NAT_PUBLIC_IP"
echo "Windows Client: ${CLIENT_PRIVATE_IP:-not deployed}"
echo "Ansible DC tunnel: 127.0.0.1:15986"

if [[ -n "$CLIENT_INSTANCE_ID" ]]; then
    echo "Ansible client tunnel: 127.0.0.1:15987"
fi

echo "Log file: $LOG_FILE"
echo "Completed: $(date)"
echo "=================================================="
