<#
.SYNOPSIS
  MSSQL Database Discovery - JSON format pre Zabbix LLD
#>
param(
    [string]$Server,
    [string]$Port,
    [string]$User,
    [string]$Password
)

$LogFile = "C:\Program Files\Zabbix Agent 2\scripts\mssql_lld.log"
$SqlCmdExe = "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\sqlcmd.exe"
$ServerPort = "$Server,$Port"
$Query = "SET NOCOUNT ON;SELECT name FROM sys.databases WHERE database_id>4"

"$(Get-Date) | Discovery: Server=$Server`:$Port User=$User" | Out-File $LogFile -Append

try {
    $output = & $SqlCmdExe -S $ServerPort -U $User -P $Password -Q $Query -h -1 -W -b 2>&1
    
    $databases = $output | Where-Object { 
        $_ -and 
        $_.Trim() -ne "" -and 
        $_ -notmatch "rows affected" -and
        $_ -notmatch "^\s*$"
    }
    
    "Databases: $($databases -join ', ')" | Out-File $LogFile -Append
    
    $json = @{ data = @() }
    foreach ($db in $databases) {
        $json.data += @{ "{#DBNAME}" = $db.Trim() }
    }
    
    $result = ($json | ConvertTo-Json -Compress)
    "JSON: $result" | Out-File $LogFile -Append
    Write-Output $result
}
catch {
    "ERROR: $_" | Out-File $LogFile -Append
    Write-Output '{"data":[]}'
}