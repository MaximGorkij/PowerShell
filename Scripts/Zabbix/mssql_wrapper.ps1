<#
.SYNOPSIS
  MSSQL Zabbix Wrapper for Agent 2
.DESCRIPTION
  Executes SQL queries via sqlcmd and returns numeric or string results.
#>

param(
    [Parameter(Mandatory = $true)][string]$Server,
    [Parameter(Mandatory = $true)][string]$Port,
    [Parameter(Mandatory = $true)][string]$User,
    [Parameter(Mandatory = $true)][string]$Password,
    [Parameter(Mandatory = $true)][string]$Query,
    [string]$Type = "numeric"
)

# Full path to sqlcmd
$SqlCmdExe = "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\sqlcmd.exe"
$ServerPort = "$Server,$Port"

try {
    $r = & $SqlCmdExe -S $ServerPort -U $User -P $Password -Q $Query -h -1 -W 2>$null
    $r2 = $r | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }

    if ($Type -eq "numeric") {
        try { Write-Output ([math]::Round([double]$r2, 2)) } catch { Write-Output 0 }
    }
    else {
        if ([string]::IsNullOrWhiteSpace($r2)) { Write-Output "UNKNOWN" } else { Write-Output $r2 }
    }
}
catch {
    if ($Type -eq "numeric") { Write-Output 0 } else { Write-Output "UNKNOWN" }
}
