########################################
# MSSQL LLD (Low Level Discovery) Script for Zabbix
# Script: mssql_lld.ps1
# Path: C:\Program Files\Zabbix Agent 2\scripts\mssql_lld.ps1
# Pouzitie: mssql_lld.ps1 <server> <port> <user> <password>
########################################

param(
    [string]$Server,
    [string]$Port,
    [string]$User,
    [string]$Password
)

# Importuj spolocny modul
Import-Module "$PSScriptRoot\mssql_common.psm1" -Force
Initialize-Log "mssql_lld.log"

Write-Log INFO "Starting database discovery for: $Server,$Port"

try {
    $sqlcmd = Get-SqlCmd
    $serverPort = "$Server,$Port"
    
    # SQL dotaz pre zoznam databaz (FOR JSON PATH)
    $q = @"
SET NOCOUNT ON;
SELECT name AS [{#DBNAME}]
FROM sys.databases
WHERE database_id > 4
AND state = 0
AND HAS_DBACCESS(name) = 1
FOR JSON PATH
"@
    
    Write-Log INFO "Executing discovery query"
    
    # Spusti sqlcmd
    $json = & $sqlcmd -S $serverPort -U $User -P $Password -Q $q -h -1 -W -b 2>&1
    
    Write-Log INFO "SQLCMD exit code: $LASTEXITCODE"
    
    # Kontrola chyby
    if ($LASTEXITCODE -ne 0) {
        Write-Log ERROR "SQLCMD failed with exit code: $LASTEXITCODE"
        Write-Log ERROR "Error output: $json"
        Write-Output '{"data":[]}'
        exit 0
    }
    
    # Vycisti vystup - odstran prazdne riadky
    $cleanJson = ($json | Where-Object { $_ -and $_.Trim() -ne '' } | Out-String).Trim()
    
    # Ak je prazdny vysledok
    if ([string]::IsNullOrWhiteSpace($cleanJson)) {
        Write-Log WARNING "Empty JSON returned"
        $cleanJson = "[]"
    }
    
    # Loguj pocet najdenych databaz
    if ($cleanJson -ne "[]") {
        try {
            $jsonObject = $cleanJson | ConvertFrom-Json -ErrorAction Stop
            $dbCount = @($jsonObject).Count
            Write-Log INFO "Discovered $dbCount databases"
            
            if ($dbCount -gt 0) {
                $dbNames = $jsonObject | ForEach-Object { $_.'{#DBNAME}' }
                Write-Log INFO "Databases: $($dbNames -join ', ')"
            }
        }
        catch {
            Write-Log WARNING "Could not parse JSON for logging: $_"
        }
    }
    else {
        Write-Log INFO "No databases discovered"
    }
    
    # Vrat finalny JSON pre Zabbix LLD
    $finalOutput = "{`"data`":$cleanJson}"
    Write-Output $finalOutput
}
catch {
    Write-Log ERROR "Discovery failed: $_"
    Write-Output '{"data":[]}'
}
finally {
    Write-Log INFO "Discovery completed"
}