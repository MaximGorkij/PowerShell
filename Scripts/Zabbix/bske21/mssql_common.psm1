########################################
# MSSQL Common Module for Zabbix
# Modul: mssql_common.psm1
# Path: C:\Program Files\Zabbix Agent 2\scripts\mssql_common.psm1
########################################

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Cesty k sqlcmd.exe v poradi priority
$script:SqlCmds = @(
  "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\sqlcmd.exe",
  "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\150\Tools\Binn\sqlcmd.exe",
  "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\130\Tools\Binn\sqlcmd.exe"
)

# Centralizovany log adresar
$script:LogBaseDir = "C:\TaurisIT\Log\Zabbix"
$script:LogFile = $null

function Initialize-LogDir {
    # Vytvor log adresar ak neexistuje
    if (-not (Test-Path $script:LogBaseDir)) {
        try {
            New-Item -Path $script:LogBaseDir -ItemType Directory -Force | Out-Null
        }
        catch {
            # Fallback na script adresar
            $script:LogBaseDir = $PSScriptRoot
        }
    }
}

function Get-SqlCmd {
    # Najdi prvu existujucu cestu k sqlcmd.exe
    foreach ($p in $script:SqlCmds) {
        if (Test-Path $p) { return $p }
    }
    throw "sqlcmd.exe not found in any expected location"
}

function Initialize-Log {
    param([string]$LogFileName)
    
    # Zabezpec ze log adresar existuje
    Initialize-LogDir
    
    # Nastav plnu cestu k log suboru
    $script:LogFile = Join-Path $script:LogBaseDir $LogFileName
    
    # Test ci mozeme zapisat do log suboru
    try {
        Add-Content -Path $script:LogFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [INFO] Log initialized" -ErrorAction Stop
    }
    catch {
        # Fallback na TEMP adresar
        $script:LogFile = Join-Path $env:TEMP $LogFileName
    }
}

function Write-Log {
    param(
        [string]$Level,
        [string]$Message
    )
    
    # Ak log nie je inicializovany, skipni
    if (-not $script:LogFile) {
        return
    }
    
    try {
        $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
        Add-Content -Path $script:LogFile -Value $line -ErrorAction Stop
    }
    catch {
        # Ticho ignoruj chyby zapisu
    }
}

function Invoke-MSSQLScalar {
    param(
        [string]$Server,
        [string]$Port,
        [string]$User,
        [string]$Password,
        [string]$Query
    )
    
    Write-Log INFO "Invoke-MSSQLScalar: server=$Server,$Port"
    Write-Log INFO "Query: $Query"
    
    $sqlcmd = Get-SqlCmd
    $serverPort = "$Server,$Port"
    
    try {
        # Spusti sqlcmd a zachyt vystup
        $out = & $sqlcmd `
            -S $serverPort `
            -U $User `
            -P $Password `
            -Q "SET NOCOUNT ON;$Query" `
            -h -1 -W -s ";" -b 2>&1
        
        Write-Log INFO "SQLCMD exit code: $LASTEXITCODE"
        
        # Kontrola chyby
        if ($LASTEXITCODE -ne 0 -or -not $out) {
            Write-Log ERROR "sqlcmd failed. Exit code: $LASTEXITCODE, Output: $($out -join ' ')"
            return 0
        }
        
        # Ziskaj prvy neprazdny riadok
        $line = $out | Where-Object { $_ -and $_.Trim() } | Select-Object -First 1
        
        if (-not $line) {
            Write-Log ERROR "No scalar value returned"
            return 0
        }
        
        # Parsuj numericky vysledok
        try {
            $result = [double]::Parse($line.Trim(), [cultureinfo]::InvariantCulture)
            Write-Log INFO "Result: $result"
            return $result
        }
        catch {
            Write-Log ERROR "Parse error for value: '$line'"
            return 0
        }
    }
    catch {
        Write-Log ERROR "Exception: $_"
        return 0
    }
}

# Export funkcii pre pouzitie v inych skriptoch
Export-ModuleMember -Function Get-SqlCmd, Initialize-Log, Write-Log, Invoke-MSSQLScalar