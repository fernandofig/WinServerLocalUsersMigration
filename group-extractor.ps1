<#
.SYNOPSIS
    Extracts all local groups on a Windows Server to a CSV file.

.DESCRIPTION
    Queries local group accounts on the machine and exports Group Name,
    Description, Group SID, and pipe-separated Members list to a CSV file.

.PARAMETER OutputFile
    Path to the output CSV file.

.EXAMPLE
    .\group-extractor.ps1 C:\Migration\source_groups.csv
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, Position = 0, HelpMessage = "Path to the output CSV file")]
    [ValidateNotNullOrEmpty()]
    [string]$OutputFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "Starting local group extraction..." -ForegroundColor Cyan

# Ensure output directory exists
$outputDir = Split-Path -Path $OutputFile -Parent
if ($outputDir -and -not (Test-Path -Path $outputDir)) {
    Write-Host "Creating output directory: $outputDir" -ForegroundColor DarkGray
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

try {
    $hasLocalGroupCmdlet = [bool](Get-Command -Name Get-LocalGroup -ErrorAction SilentlyContinue)
    $extractedGroups = [System.Collections.Generic.List[PSCustomObject]]::new()

    if ($hasLocalGroupCmdlet) {
        $groups = Get-LocalGroup
        foreach ($grp in $groups) {
            $sidValue = if ($grp.SID -is [System.Security.Principal.SecurityIdentifier]) {
                $grp.SID.Value
            } elseif ($grp.SID.Value) {
                $grp.SID.Value
            } else {
                [string]$grp.SID
            }

            $memberNames = [System.Collections.Generic.List[string]]::new()
            try {
                $members = Get-LocalGroupMember -Group $grp.Name -ErrorAction Stop
                foreach ($m in $members) {
                    # Strip domain/computer prefix: "COMPUTER\Username" -> "Username"
                    $rawName = [string]$m.Name
                    $usernameOnly = if ($rawName -match '\\([^\\]+)$') { $Matches[1] } else { $rawName }
                    if (-not [string]::IsNullOrWhiteSpace($usernameOnly)) {
                        $memberNames.Add($usernameOnly)
                    }
                }
            } catch {
                Write-Warning "Could not query members for group '$($grp.Name)': $($_.Exception.Message)"
            }

            $membersJoined = ($memberNames -join '|')

            $grpObj = [PSCustomObject]@{
                'Group Name'        = [string]$grp.Name
                'Description'       = [string]$grp.Description
                'Members'           = $membersJoined
                'Group SID'         = $sidValue
                'Members user list' = $membersJoined
            }
            $extractedGroups.Add($grpObj)
        }
    } else {
        # Fallback to ADSI
        Write-Host "Get-LocalGroup cmdlet not found. Falling back to ADSI provider..." -ForegroundColor Yellow
        $computerName = $env:COMPUTERNAME
        $adsiComputer = [ADSI]"WinNT://$computerName"
        $groups = $adsiComputer.Children | Where-Object { $_.SchemaClassName -eq 'Group' }

        foreach ($grp in $groups) {
            $groupSidBytes = $grp.objectSid.Value
            $sidValue = if ($groupSidBytes) { (New-Object System.Security.Principal.SecurityIdentifier($groupSidBytes, 0)).Value } else { "" }

            $memberNames = [System.Collections.Generic.List[string]]::new()
            try {
                $membersObj = $grp.Invoke('Members')
                foreach ($m in $membersObj) {
                    $mName = [string]$m.GetType().InvokeMember('Name', 'GetProperty', $null, $m, $null)
                    if (-not [string]::IsNullOrWhiteSpace($mName)) {
                        $memberNames.Add($mName)
                    }
                }
            } catch {
                Write-Warning "Could not query members for group '$($grp.Name)': $($_.Exception.Message)"
            }

            $membersJoined = ($memberNames -join '|')

            $grpObj = [PSCustomObject]@{
                'Group Name'        = [string]$grp.Name
                'Description'       = [string]$grp.Description
                'Members'           = $membersJoined
                'Group SID'         = $sidValue
                'Members user list' = $membersJoined
            }
            $extractedGroups.Add($grpObj)
        }
    }

    $extractedGroups | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8

    Write-Host "Successfully extracted $($extractedGroups.Count) groups to: $OutputFile" -ForegroundColor Green
} catch {
    Write-Error "Failed to extract local groups: $($_.Exception.Message)"
    exit 1
}
