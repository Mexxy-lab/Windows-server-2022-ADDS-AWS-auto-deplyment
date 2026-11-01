[CmdletBinding()]
param(
    [string]$InternalPrefix = "10.20.0.0/24",
    [string]$InternalIP = "10.20.0.1",
    [string]$NatName = "ADLabNAT"
)

$ErrorActionPreference = "Stop"

# Locate the internal network interface.
$internalInterface = Get-NetIPAddress `
    -AddressFamily IPv4 `
    -IPAddress $InternalIP

# Enable forwarding on the internal interface.
Set-NetIPInterface `
    -InterfaceIndex $internalInterface.InterfaceIndex `
    -Forwarding Enabled

# Check whether the NAT already exists.
$existingNat = Get-NetNat -Name $NatName `
    -ErrorAction SilentlyContinue

# Create NAT only when necessary.
if (-not $existingNat) {
    New-NetNat `
        -Name $NatName `
        -InternalIPInterfaceAddressPrefix $InternalPrefix
}

# Display the resulting NAT configuration.
Get-NetNat -Name $NatName