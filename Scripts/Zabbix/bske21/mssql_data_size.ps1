########################################
# MSSQL Data Size Script for Zabbix
# Script: mssql_data_size.ps1
# Path: C:\Program Files\Zabbix Agent 2\scripts\mssql_data_size.ps1
# Pouzitie: mssql_data_size.ps1 <server> <port> <user> <password> <database>
########################################

param(
    [string]$Server,
    [string]$Port,
    [string]$User,
    [string]$Password,
    [string]$Database
)

# Importuj spolocny modul
Import-Module "$PSScriptRoot\mssql_common.psm1" -Force
Initialize-Log "mssql_data_size.log"

# Validacia vstupu
if (-not $Database -or $Database.Trim() -eq '') {
    Write-Log ERROR "Database parameter is empty"
    Write-Output 0
    exit 0
}

Write-Log INFO "Getting data size for database: $Database"

# SQL dotaz pre velkost dat
$q = "SELECT SUM(size)*8/1024.0 FROM sys.master_files WHERE database_id=DB_ID('$Database') AND type_desc='ROWS'"

# Volaj spolocnu funkciu
$result = Invoke-MSSQLScalar -Server $Server -Port $Port -User $User -Password $Password -Query $q

Write-Output $result
