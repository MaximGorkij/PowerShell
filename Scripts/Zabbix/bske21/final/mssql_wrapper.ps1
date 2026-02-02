########################################
# MSSQL Wrapper Script for Zabbix
# Wrapper: mssql_wrapper.ps1
# Path: C:\Program Files\Zabbix Agent 2\scripts\mssql_wrapper.ps1
# Pouzitie: mssql_wrapper.ps1 <server> <port> <user> <password> <query> <type>
########################################

param(
    [string]$Server,
    [string]$Port,
    [string]$User,
    [string]$Password,
    [string]$Query,
    [string]$Type = "numeric"  # numeric alebo string
)

# Importuj spolocny modul
Import-Module "$PSScriptRoot\mssql_common.psm1" -Force
Initialize-Log "mssql_wrapper.log"

Write-Log INFO "Called with: Server=$Server, Port=$Port, Type=$Type"

try {
    $sqlcmd = Get-SqlCmd
    $serverPort = "$Server,$Port"
    
    Write-Log INFO "Query: $Query"
    
    # Spusti sqlcmd
    $out = & $sqlcmd `
        -S $serverPort `
        -U $User `
        -P $Password `
        -Q "SET NOCOUNT ON;$Query" `
        -h -1 -W -s ";" -b 2>&1
    
    Write-Log INFO "SQLCMD exit code: $LASTEXITCODE"
    
    # Kontrola chyby
    if ($LASTEXITCODE -ne 0 -or -not $out) {
        Write-Log ERROR "sqlcmd failed. Exit code: $LASTEXITCODE"
        if ($Type -eq "numeric") {
            Write-Output 0
        } else {
            Write-Output "ERROR"
        }
        exit 0
    }
    
    # Ziskaj prvy neprazdny riadok
    $line = $out | Where-Object { $_ -and $_.Trim() } | Select-Object -First 1
    
    if (-not $line) {
        Write-Log ERROR "No value returned"
        if ($Type -eq "numeric") {
            Write-Output 0
        } else {
            Write-Output "NODATA"
        }
        exit 0
    }
    
    # Vrat vysledok podla typu
    if ($Type -eq "numeric") {
        try {
            $result = [double]::Parse($line.Trim(), [cultureinfo]::InvariantCulture)
            Write-Log INFO "Result: $result"
            Write-Output $result
        }
        catch {
            Write-Log ERROR "Parse error: '$line'"
            Write-Output 0
        }
    }
    else {
        $result = $line.Trim()
        Write-Log INFO "Result: $result"
        Write-Output $result
    }
}
catch {
    Write-Log ERROR "Exception: $_"
    if ($Type -eq "numeric") {
        Write-Output 0
    } else {
        Write-Output "ERROR"
    }
}