<#
.SYNOPSIS
  MSSQL Zabbix Wrapper - DEBUG VERSION
#>
param(
    [string]$Server,
    [string]$Port,
    [string]$User,
    [string]$Password,
    [string]$Query,
    [string]$Type = "numeric"
)

$LogFile = "C:\Program Files\Zabbix Agent 2\scripts\mssql_debug.log"
$SqlCmdExe = "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\sqlcmd.exe"
$ServerPort = "$Server,$Port"

"$(Get-Date) | Server=$Server Port=$Port User=$User Query=$Query Type=$Type" | Out-File $LogFile -Append

try {
    $output = & $SqlCmdExe -S $ServerPort -U $User -P $Password -Q $Query -h -1 -W -b 2>&1
    
    "OUTPUT: $output" | Out-File $LogFile -Append
    
    $result = $output | Where-Object { 
        $_ -and 
        $_.Trim() -ne "" -and 
        $_ -notmatch "rows affected" -and
        $_ -notmatch "^\s*$"
    } | Select-Object -First 1
    
    # Kontrola ci mame vysledok
    if ($null -eq $result -or [string]::IsNullOrWhiteSpace($result)) {
        "EMPTY RESULT" | Out-File $LogFile -Append
        if ($Type -eq "numeric") { 
            Write-Output 0 
        }
        else { 
            Write-Output "UNKNOWN" 
        }
        return
    }
    
    $result = $result.Trim()
    "RESULT: $result" | Out-File $LogFile -Append
    
    if ($Type -eq "numeric") {
        try { 
            $num = [math]::Round([double]$result, 2)
            "NUMERIC: $num" | Out-File $LogFile -Append
            Write-Output $num
        }
        catch { 
            "ERROR PARSE: $_" | Out-File $LogFile -Append
            Write-Output 0 
        }
    }
    else {
        Write-Output $result
    }
}
catch {
    "EXCEPTION: $_" | Out-File $LogFile -Append
    if ($Type -eq "numeric") { Write-Output 0 } else { Write-Output "UNKNOWN" }
}