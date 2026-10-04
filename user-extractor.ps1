<#
.SYNOPSIS
    Extracts all local users on a Windows Server to a CSV file.

.DESCRIPTION
    Queries local user accounts on the machine and exports their Username,
    Full name, Description, and User SID to a CSV file.

.PARAMETER OutputFile
    Path to the output CSV file.

.EXAMPLE
    .\user-extractor.ps1 C:\Migration\source_users.csv
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, Position = 0, HelpMessage = "Path to the output CSV file")]
    [ValidateNotNullOrEmpty()]
    [string]$OutputFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "Starting local user extraction..." -ForegroundColor Cyan

# Ensure output directory exists
$outputDir = Split-Path -Path $OutputFile -Parent
if ($outputDir -and -not (Test-Path -Path $outputDir)) {
    Write-Host "Creating output directory: $outputDir" -ForegroundColor DarkGray
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

try {
    # Check if Microsoft.PowerShell.LocalAccounts module is available
    if (Get-Command -Name Get-LocalUser -ErrorAction SilentlyContinue) {
        $localUsers = Get-LocalUser
    } else {
        # Fallback to ADSI (for older environments or minimal installations)
        Write-Host "Get-LocalUser cmdlet not found. Falling back to ADSI provider..." -ForegroundColor Yellow
        $computerName = $env:COMPUTERNAME
        $adsiComputer = [ADSI]"WinNT://$computerName"
        $localUsers = $adsiComputer.Children | Where-Object { $_.SchemaClassName -eq 'User' } | ForEach-Object {
            $userSidBytes = $_.objectSid.Value
            $sid = if ($userSidBytes) { (New-Object System.Security.Principal.SecurityIdentifier($userSidBytes, 0)).Value } else { "" }
            [PSCustomObject]@{
                Name        = [string]$_.Name
                FullName    = [string]$_.FullName
                Description = [string]$_.Description
                SID         = [PSCustomObject]@{ Value = $sid }
            }
        }
    }

    $extractedUsers = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($u in $localUsers) {
        $sidValue = if ($u.SID -is [System.Security.Principal.SecurityIdentifier]) {
            $u.SID.Value
        } elseif ($u.SID.Value) {
            $u.SID.Value
        } else {
            [string]$u.SID
        }

        $userObj = [PSCustomObject]@{
            'Username'    = [string]$u.Name
            'Full name'   = [string]$u.FullName
            'Description' = [string]$u.Description
            'User SID'    = $sidValue
        }
        $extractedUsers.Add($userObj)
    }

    $extractedUsers | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8

    Write-Host "Successfully extracted $($extractedUsers.Count) users to: $OutputFile" -ForegroundColor Green
} catch {
    Write-Error "Failed to extract local users: $($_.Exception.Message)"
    exit 1
}
