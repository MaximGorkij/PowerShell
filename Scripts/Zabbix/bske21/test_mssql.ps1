########################################
# Test script pre MSSQL monitorovanie
# Pouzitie: test_mssql.ps1
########################################

param(
    [string]$Server = "localhost",
    [string]$Port = "1433",
    [string]$User = "zabbix",
    [string]$Password = "heslo"
)

Write-Host "=== MSSQL Monitoring Test ===" -ForegroundColor Cyan
Write-Host ""

# 1. Test ci existuju skripty
Write-Host "1. Kontrola skriptov..." -ForegroundColor Yellow
$scriptPath = "C:\Program Files\Zabbix Agent 2\scripts"
$requiredFiles = @(
    "mssql_common.psm1",
    "mssql_wrapper.ps1",
    "mssql_lld.ps1",
    "mssql_data_size.ps1",
    "mssql_log_size.ps1"
)

foreach ($file in $requiredFiles) {
    $fullPath = Join-Path $scriptPath $file
    if (Test-Path $fullPath) {
        Write-Host "  [OK] $file" -ForegroundColor Green
    } else {
        Write-Host "  [CHYBA] $file NEEXISTUJE!" -ForegroundColor Red
    }
}
Write-Host ""

# 2. Test ci existuje sqlcmd.exe
Write-Host "2. Kontrola sqlcmd.exe..." -ForegroundColor Yellow
$sqlcmdPaths = @(
    "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\sqlcmd.exe",
    "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\150\Tools\Binn\sqlcmd.exe",
    "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\130\Tools\Binn\sqlcmd.exe"
)
$foundSqlcmd = $false
foreach ($path in $sqlcmdPaths) {
    if (Test-Path $path) {
        Write-Host "  [OK] Najdene: $path" -ForegroundColor Green
        $foundSqlcmd = $true
        break
    }
}
if (-not $foundSqlcmd) {
    Write-Host "  [CHYBA] sqlcmd.exe nenajdene!" -ForegroundColor Red
}
Write-Host ""

# 3. Test ci existuje log adresar
Write-Host "3. Kontrola log adresara..." -ForegroundColor Yellow
$logDir = "C:\TaurisIT\Log\Zabbix"
if (Test-Path $logDir) {
    Write-Host "  [OK] Adresar existuje: $logDir" -ForegroundColor Green
} else {
    Write-Host "  [INFO] Vytvorim adresar: $logDir" -ForegroundColor Yellow
    try {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        Write-Host "  [OK] Adresar vytvoreny" -ForegroundColor Green
    } catch {
        Write-Host "  [CHYBA] Nepodarilo sa vytvorit: $_" -ForegroundColor Red
    }
}
Write-Host ""

# 4. Test pripojenia k SQL serveru
Write-Host "4. Test SQL pripojenia..." -ForegroundColor Yellow
Write-Host "  Server: $Server,$Port" -ForegroundColor Gray
Write-Host "  User: $User" -ForegroundColor Gray

if ($foundSqlcmd) {
    $sqlcmd = $sqlcmdPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    try {
        $result = & $sqlcmd -S "$Server,$Port" -U $User -P $Password -Q "SELECT 1" -h -1 -W 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [OK] Pripojenie uspesne" -ForegroundColor Green
        } else {
            Write-Host "  [CHYBA] Pripojenie zlyhalo!" -ForegroundColor Red
            Write-Host "  Chyba: $result" -ForegroundColor Red
        }
    } catch {
        Write-Host "  [CHYBA] Exception: $_" -ForegroundColor Red
    }
} else {
    Write-Host "  [PRESKOCENE] sqlcmd.exe nenajdene" -ForegroundColor Yellow
}
Write-Host ""

# 5. Test wrapper skriptu
Write-Host "5. Test mssql_wrapper.ps1..." -ForegroundColor Yellow
$wrapperPath = Join-Path $scriptPath "mssql_wrapper.ps1"
if (Test-Path $wrapperPath) {
    try {
        $result = & $wrapperPath $Server $Port $User $Password "SELECT 1" "numeric"
        Write-Host "  Vysledok: $result" -ForegroundColor Cyan
        if ($result -eq 1) {
            Write-Host "  [OK] Wrapper funguje" -ForegroundColor Green
        } else {
            Write-Host "  [CHYBA] Ocakavany vysledok: 1, dostal som: $result" -ForegroundColor Red
        }
    } catch {
        Write-Host "  [CHYBA] Exception: $_" -ForegroundColor Red
    }
} else {
    Write-Host "  [PRESKOCENE] Wrapper neexistuje" -ForegroundColor Yellow
}
Write-Host ""

# 6. Test LLD skriptu
Write-Host "6. Test mssql_lld.ps1..." -ForegroundColor Yellow
$lldPath = Join-Path $scriptPath "mssql_lld.ps1"
if (Test-Path $lldPath) {
    try {
        $result = & $lldPath $Server $Port $User $Password
        Write-Host "  JSON vysledok:" -ForegroundColor Cyan
        Write-Host "  $result" -ForegroundColor Gray
        
        # Parsuj JSON
        $jsonObj = $result | ConvertFrom-Json
        if ($jsonObj.data) {
            $dbCount = @($jsonObj.data).Count
            Write-Host "  [OK] Najdenych databaz: $dbCount" -ForegroundColor Green
        } else {
            Write-Host "  [CHYBA] Nespravny JSON format" -ForegroundColor Red
        }
    } catch {
        Write-Host "  [CHYBA] Exception: $_" -ForegroundColor Red
    }
} else {
    Write-Host "  [PRESKOCENE] LLD skript neexistuje" -ForegroundColor Yellow
}
Write-Host ""

# 7. Kontrola log suborov
Write-Host "7. Kontrola log suborov..." -ForegroundColor Yellow
if (Test-Path $logDir) {
    $logs = Get-ChildItem -Path $logDir -Filter "mssql_*.log" -ErrorAction SilentlyContinue
    if ($logs) {
        foreach ($log in $logs) {
            Write-Host "  [OK] $($log.Name) - Velkost: $($log.Length) bytes" -ForegroundColor Green
            # Ukaz posledne 3 riadky
            $lastLines = Get-Content $log.FullName -Tail 3 -ErrorAction SilentlyContinue
            if ($lastLines) {
                Write-Host "    Posledne riadky:" -ForegroundColor Gray
                $lastLines | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
            }
        }
    } else {
        Write-Host "  [INFO] Ziadne log subory" -ForegroundColor Yellow
    }
}
Write-Host ""

Write-Host "=== Test dokonceny ===" -ForegroundColor Cyan