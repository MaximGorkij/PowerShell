<#
.SYNOPSIS
  Velkost DATA suborov databazy v MB
#>
param(
    [string]$Server,
    [string]$Port,
    [string]$User,
    [string]$Password,
    [string]$Database
)

$LogFile = "C:\Program Files\Zabbix Agent 2\scripts\mssql_data_size.log"
$SqlCmdExe = "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\sqlcmd.exe"
$ServerPort = "$Server,$Port"
$Query = "SET NOCOUNT ON;SELECT SUM(size)*8/1024 FROM sys.master_files WHERE database_id=DB_ID('$Database') AND type_desc='ROWS'"

"$(Get-Date) | Data size: DB=$Database" | Out-File $LogFile -Append

try {
    $output = & $SqlCmdExe -S $ServerPort -U $User -P $Password -Q $Query -h -1 -W -b 2>&1
    
    $result = $output | Where-Object { 
        $_ -and 
        $_.Trim() -ne "" -and 
        $_ -notmatch "rows affected" -and
        $_ -notmatch "^\s*$"
    } | Select-Object -First 1
    
    $value = [math]::Round([double]$result.Trim(), 2)
    "Result: $value MB" | Out-File $LogFile -Append
    Write-Output $value
}
catch {
    "ERROR: $_" | Out-File $LogFile -Append
    Write-Output 0
}