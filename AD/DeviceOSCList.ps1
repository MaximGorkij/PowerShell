<#
.SYNOPSIS
    Skript pre kontrolu kompatibility zariadení medzi OCS Inventory, Microsoft Entra ID a Microsoft Intune

.DESCRIPTION
    Tento skript vyberie zariadenia z OCS Inventory podla specifickych podmienok a overi ich existenciu
    v Microsoft Entra ID a Microsoft Intune. Vysledkom je prehlad o kompliantnych a nekompliantnych zariadeniach.

.PARAMETER OcsDBServer
    MySQL server pre OCS Inventory databazu

.PARAMETER OcsDBName
    Nazov OCS Inventory databazy

.PARAMETER OcsDBUser
    Uzivatelske meno pre pripojenie k OCS databaze

.PARAMETER OcsDBPassword
    Heslo pre pripojenie k OCS databaze

.PARAMETER TenantId
    Azure AD Tenant ID

.PARAMETER ClientId
    App Registration Client ID

.PARAMETER ClientSecret
    App Registration Client Secret

.PARAMETER ExportPath
    Cesta pre export vysledkov (volitelne)

.PARAMETER AutoInstallModules
    Automaticky nainstaluje chybajuce moduly bez potvrdenia

.EXAMPLE
    .\OCS_Compliance_Check_MySQL.ps1

.EXAMPLE
    .\OCS_Compliance_Check_MySQL.ps1 -OcsDBServer "mysqlserver" -ExportPath "C:\Reports"

.EXAMPLE
    .\OCS_Compliance_Check_MySQL.ps1 -AutoInstallModules

.NOTES
    Autor: IT Admin
    Verzia: 2.5
    Datum vytvorenia: $(Get-Date -Format "dd.MM.yyyy")
    Potrebne moduly: Microsoft.Graph.Authentication, Microsoft.Graph.Identity.DirectoryManagement, Microsoft.Graph.DeviceManagement
    MySQL: Vyžaduje sa MySQL Connector/NET
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OcsDBServer = "rkefs01",
    
    [Parameter(Mandatory = $false)]
    [string]$OcsDBName = "ocsweb",
    
    [Parameter(Mandatory = $false)]
    [string]$OcsDBUser = "ocs",
    
    [Parameter(Mandatory = $false)]
    [string]$OcsDBPassword = "ocs",
    
    [Parameter(Mandatory = $false)]
    [string]$TenantId = "ebf9edb5-a5f7-4d70-9a59-501865f222ee",
    
    [Parameter(Mandatory = $false)]
    [string]$ClientId = "c5072861-a7e6-41f8-92e8-708a588abf30",
    
    [Parameter(Mandatory = $false)]
    [string]$ClientSecret = "QAN8Q~o9kEcQRaw_~FNcEk_bh6yw6DlrLIH1DbBg",
    
    [Parameter(Mandatory = $false)]
    [string]$ExportPath = ".",
    
    [Parameter(Mandatory = $false)]
    [switch]$AutoInstallModules
)

#Requires -Version 5.1

# ============================================================================
# KONFIGURACNA SEKCIA
# ============================================================================

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'Continue'

# OCS Inventory SQL query pre MySQL - OPRAVENA VERZIA
$ocsQuery = @"
SELECT 
    h.NAME AS 'Computer',
    h.OSNAME AS 'OperatingSystem',
    h.LASTDATE AS 'LastInventory',
    a.TAG AS 'AccountTag'
FROM hardware h
LEFT JOIN accountinfo a ON h.ID = a.HARDWARE_ID
WHERE h.ID IN (
    SELECT DISTINCT h2.ID
    FROM hardware h2
    LEFT JOIN accountinfo a2 ON h2.ID = a2.HARDWARE_ID
    LEFT JOIN archive ar ON h2.ID = ar.HARDWARE_ID
    WHERE 
        h2.USERAGENT = 'OCS-NG_WINDOWS_AGENT_v2.1.0.3' AND
        h2.OSNAME NOT LIKE '%Server%' AND
        ar.HARDWARE_ID IS NULL AND
        (a2.TAG IS NULL OR a2.TAG != 'NoIntune')
)
ORDER BY h.NAME
"@

# ============================================================================
# POMOCNE FUNKCIE
# ============================================================================

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $colorMap = @{
        'Info'    = 'White'
        'Success' = 'Green'
        'Warning' = 'Yellow'
        'Error'   = 'Red'
    }
    
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $colorMap[$Level]
}

function Test-RequiredModules {
    param(
        [switch]$AutoInstall
    )
    
    $requiredModules = @(
        'Microsoft.Graph.Authentication',
        'Microsoft.Graph.Identity.DirectoryManagement',
        'Microsoft.Graph.DeviceManagement'
    )
    
    Write-Log "Kontrola potrebnych modulov..." -Level Info
    
    $missingModules = @()
    $modulesToImport = @()
    
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -ListAvailable -Name $module)) {
            $missingModules += $module
        }
        else {
            $modulesToImport += $module
        }
    }
    
    # Instalacia chybajucich modulov
    if ($missingModules.Count -gt 0) {
        Write-Log "Chybajuce moduly: $($missingModules -join ', ')" -Level Warning
        
        if ($AutoInstall) {
            Write-Log "Automaticka instalacia chybajucich modulov..." -Level Info
            
            foreach ($module in $missingModules) {
                try {
                    Write-Log "Instalujem modul: $module" -Level Info
                    Install-Module -Name $module -Scope CurrentUser -Force -AllowClobber -Repository PSGallery -ErrorAction Stop
                    Write-Log "Modul $module uspesne nainstalovany" -Level Success
                    $modulesToImport += $module
                }
                catch {
                    Write-Log "Chyba pri instalacii modulu ${module}: $($_.Exception.Message)" -Level Error
                    return $false
                }
            }
        }
        else {
            $response = Read-Host "Chcete automaticky nainštalovať chýbajúce moduly? (A/N)"
            if ($response -eq 'A' -or $response -eq 'a') {
                foreach ($module in $missingModules) {
                    try {
                        Write-Log "Instalujem modul: $module" -Level Info
                        Install-Module -Name $module -Scope CurrentUser -Force -AllowClobber -Repository PSGallery -ErrorAction Stop
                        Write-Log "Modul $module uspesne nainstalovany" -Level Success
                        $modulesToImport += $module
                    }
                    catch {
                        Write-Log "Chyba pri instalacii modulu ${module}: $($_.Exception.Message)" -Level Error
                        return $false
                    }
                }
            }
            else {
                Write-Log "Instalacia zrusena pouzivatelom" -Level Warning
                Write-Log "Manualna instalacia: Install-Module -Name <ModuleName> -Scope CurrentUser" -Level Info
                return $false
            }
        }
    }
    
    # Import modulov
    Write-Log "Import potrebnych modulov..." -Level Info
    foreach ($module in $modulesToImport) {
        try {
            if (-not (Get-Module -Name $module)) {
                Import-Module -Name $module -ErrorAction Stop
                Write-Log "Modul $module importovany" -Level Success
            }
        }
        catch {
            Write-Log "Chyba pri importe modulu ${module}: $($_.Exception.Message)" -Level Error
            return $false
        }
    }
    
    Write-Log "Vsetky potrebne moduly su pripravene" -Level Success
    return $true
}

function Initialize-MySQLConnector {
    Write-Log "Inicializacia MySQL .NET connector..." -Level Info
    
    $connectorPaths = @(
        "C:\Program Files (x86)\MySQL\MySQL Connector NET 9.4\MySql.Data.dll",
        "C:\Program Files (x86)\MySQL\MySQL Connector NET 8.0\MySql.Data.dll",
        "C:\Program Files (x86)\MySQL\MySQL Connector NET 6.10\Assemblies\net4.5.2\MySql.Data.dll",
        "C:\Program Files (x86)\MySQL\MySQL Connector NET 6.9\Assemblies\net4.5.2\MySql.Data.dll",
        "C:\Program Files (x86)\MySQL\MySQL Connector NET 6.8\Assemblies\net4.5.2\MySql.Data.dll",
        "C:\Program Files (x86)\MySQL\MySQL Connector NET 8.0\Assemblies\netstandard2.0\MySql.Data.dll"
    )
    
    foreach ($path in $connectorPaths) {
        if (Test-Path $path) {
            try {
                Add-Type -Path $path -ErrorAction Stop
                Write-Log "MySQL connector nacitany z: $path" -Level Success
                return $true
            }
            catch {
                Write-Log "Nepodarilo sa nacitat MySQL connector z: $path" -Level Warning
                continue
            }
        }
    }
    
    throw "MySQL .NET connector nie je nainstalovany alebo nie je najdeny. Nainstalujte MySQL Connector/NET."
}

# ============================================================================
# MYSQL FUNKCIE
# ============================================================================

function Get-OCSComputers {
    param(
        [string]$Server = "rkefs01",
        [string]$Database = "ocsweb",
        [string]$Username = "ocs",
        [string]$Password = "ocs"
    )
    
    Write-Log "Pripajam sa k MySQL OCS databaze na serveri: $Server..." -Level Info

    # Test MySQL portu 3306
    Write-Log "Kontrolujem MySQL port 3306..." -Level Info
    try {
        $tcpTest = Test-NetConnection -ComputerName $Server -Port 3306 -InformationLevel Quiet -ErrorAction SilentlyContinue
        if ($tcpTest) {
            Write-Log "MySQL port 3306 je otvoreny" -Level Success
        }
        else {
            Write-Log "MySQL port 3306 nie je dostupny" -Level Warning
        }
    }
    catch {
        Write-Log "Nepodarilo sa otestovat MySQL port 3306" -Level Warning
    }

    # MySQL connection stringy
    $connectionStrings = @(
        "Server=$Server;Database=$Database;Uid=$Username;Pwd=$Password;Connection Timeout=10;",
        "Server=$Server;Port=3306;Database=$Database;Uid=$Username;Pwd=$Password;Connection Timeout=10;",
        "Server=$Server;Database=$Database;Uid=$Username;Pwd=$Password;Connection Timeout=10;SslMode=None;",
        "Server=$Server;Database=$Database;Uid=$Username;Pwd=$Password;Connection Timeout=10;Allow User Variables=True;",
        "Server=$Server;Database=$Database;Uid=$Username;Pwd=$Password;Connection Timeout=10;CharSet=utf8;",
        "Server=$Server;Database=$Database;Uid=$Username;Pwd=$Password;Connection Timeout=15;Pooling=false;"
    )
    
    $connection = $null
    $connectionSuccess = $false
    $lastError = ""

    # Skúsme získať IP adresu servera
    try {
        $ipAddress = [System.Net.Dns]::GetHostAddresses($Server) | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | Select-Object -First 1
        if ($ipAddress) {
            Write-Log "IP adresa servera: $($ipAddress.IPAddressToString)" -Level Info
            $connectionStrings += "Server=$($ipAddress.IPAddressToString);Database=$Database;Uid=$Username;Pwd=$Password;Connection Timeout=10;"
        }
    }
    catch {
        Write-Log "Nepodarilo sa ziskat IP adresu servera" -Level Warning
    }
    
    foreach ($connString in $connectionStrings) {
        try {
            Write-Log "Pokus o pripojenie s MySQL..." -Level Info
            
            $connection = New-Object MySql.Data.MySqlClient.MySqlConnection($connString)
            $connection.Open()
            
            if ($connection.State -eq 'Open') {
                Write-Log "Uspesne pripojene k MySQL OCS databaze!" -Level Success
                $connectionSuccess = $true
                break
            }
        }
        catch {
            $lastError = $_.Exception.Message
            Write-Log "MySQL pripojenie zlyhalo: $lastError" -Level Warning
            if ($connection) {
                $connection.Dispose()
                $connection = $null
            }
            continue
        }
    }
    
    if (-not $connectionSuccess) {
        Write-Log "Vsetky pokusy o pripojenie zlyhali. Posledna chyba: $lastError" -Level Error
        Write-Log "Overte:" -Level Info
        Write-Log "1. Ci MySQL server bezi na $Server" -Level Info
        Write-Log "2. Ci su prihlasovacie udaje spravne" -Level Info
        Write-Log "3. Ci je databaza $Database vytvorena" -Level Info
        Write-Log "4. Ci ma uzivatel $Username pristup k databaze" -Level Info
        throw "Nepodarilo sa pripojit k MySQL OCS databaze"
    }
    
    try {
        Write-Log "Vykonavam SQL query..." -Level Info
        $command = New-Object MySql.Data.MySqlClient.MySqlCommand($ocsQuery, $connection)
        $command.CommandTimeout = 60
        
        $adapter = New-Object MySql.Data.MySqlClient.MySqlDataAdapter($command)
        $dataset = New-Object System.Data.DataSet
        [void]$adapter.Fill($dataset)
        
        $rowCount = $dataset.Tables[0].Rows.Count
        Write-Log "Uspesne nacitane data z MySQL OCS databazy - $rowCount zariadeni" -Level Success
        
        return $dataset.Tables[0]
    }
    catch {
        Write-Log "Chyba pri vykonavani SQL query: $($_.Exception.Message)" -Level Error
        throw "Chyba pri citani z MySQL OCS databazy: $($_.Exception.Message)"
    }
    finally {
        if ($connection -and $connection.State -eq 'Open') {
            $connection.Close()
            $connection.Dispose()
            Write-Log "MySQL pripojenie uzavrete" -Level Info
        }
    }
}

# ============================================================================
# MICROSOFT GRAPH FUNKCIE
# ============================================================================

function Connect-MgGraphWithApp {
    param(
        [string]$TenantId,
        [string]$ClientId,
        [string]$ClientSecret
    )
    
    try {
        # Vytvorenie credential objektu
        $secureSecret = ConvertTo-SecureString -String $ClientSecret -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential($ClientId, $secureSecret)
        
        # Pripojenie k Microsoft Graph
        Write-Log "Pripojujem sa k Microsoft Graph s App Registration..." -Level Info
        Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $credential -NoWelcome -ErrorAction Stop
        
        # Overenie pripojenia
        $context = Get-MgContext
        if ($context) {
            Write-Log "Uspesne pripojene k Microsoft Graph (Tenant: $($context.TenantId))" -Level Success
            return $true
        }
        return $false
    }
    catch {
        Write-Log "Chyba pri pripajani k Microsoft Graph: $($_.Exception.Message)" -Level Error
        return $false
    }
}

function Get-AllEntraDevices {
    Write-Log "Nacitavam vsetky zariadenia z Entra ID..." -Level Info
    
    try {
        $devices = Get-MgDevice -All -ErrorAction Stop
        Write-Log "Nacitanych $($devices.Count) zariadeni z Entra ID" -Level Success
        
        # Vytvorime hashtable pre rychle vyhladavanie
        $deviceHash = @{}
        foreach ($device in $devices) {
            if ($device.DisplayName) {
                $deviceHash[$device.DisplayName] = $device
            }
        }
        
        return $deviceHash
    }
    catch {
        Write-Log "Chyba pri nacitavani Entra zariadeni: $($_.Exception.Message)" -Level Error
        throw
    }
}

function Get-AllIntuneDevices {
    Write-Log "Nacitavam vsetky zariadenia z Intune..." -Level Info
    
    try {
        $devices = Get-MgDeviceManagementManagedDevice -All -ErrorAction Stop
        Write-Log "Nacitanych $($devices.Count) zariadeni z Intune" -Level Success
        
        # Vytvorime hashtable pre rychle vyhladavanie
        $deviceHash = @{}
        foreach ($device in $devices) {
            if ($device.DeviceName) {
                $deviceHash[$device.DeviceName] = $device
            }
        }
        
        return $deviceHash
    }
    catch {
        Write-Log "Chyba pri nacitavani Intune zariadeni: $($_.Exception.Message)" -Level Error
        throw
    }
}

# ============================================================================
# EXPORT A REPORTING FUNKCIE
# ============================================================================

function Export-Results {
    param(
        [Parameter(Mandatory)]
        [array]$Results,
        
        [Parameter(Mandatory)]
        [string]$Path
    )
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    
    # Vytvor priečinok ak neexistuje
    if (!(Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
    
    # Export CSV
    $csvPath = Join-Path $Path "OCS_Compliance_Check_$timestamp.csv"
    $Results | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
    Write-Log "CSV exportovany do: $csvPath" -Level Success
    
    # Export HTML reportu
    $htmlPath = Join-Path $Path "OCS_Compliance_Check_$timestamp.html"
    $htmlContent = New-HTMLReport -Results $Results
    $htmlContent | Out-File -FilePath $htmlPath -Encoding UTF8
    Write-Log "HTML report exportovany do: $htmlPath" -Level Success
    
    return @{
        CSV  = $csvPath
        HTML = $htmlPath
    }
}

function New-HTMLReport {
    param([array]$Results)
    
    $compliant = ($Results | Where-Object { $_.Status -eq 'COMPLIANT' }).Count
    $nonCompliant = ($Results | Where-Object { $_.Status -eq 'NON-COMPLIANT' }).Count
    $total = $Results.Count
    $successRate = if ($total -gt 0) { [math]::Round(($compliant / $total) * 100, 2) } else { 0 }
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>OCS Compliance Report</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .header { background-color: #0078d4; color: white; padding: 20px; border-radius: 5px; }
        .stats { display: flex; justify-content: space-around; margin: 20px 0; }
        .stat-box { background: white; padding: 20px; border-radius: 5px; text-align: center; box-shadow: 0 2px 4px rgba(0,0,0,0.1); flex: 1; margin: 0 10px; }
        .stat-value { font-size: 36px; font-weight: bold; }
        .compliant { color: #107c10; }
        .non-compliant { color: #d13438; }
        table { width: 100%; border-collapse: collapse; background: white; box-shadow: 0 2px 4px rgba(0,0,0,0.1); margin-top: 20px; }
        th { background-color: #0078d4; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f5f5f5; }
        .status-compliant { color: #107c10; font-weight: bold; }
        .status-non-compliant { color: #d13438; font-weight: bold; }
        .footer { margin-top: 20px; text-align: center; color: #666; font-size: 12px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>OCS Inventory Compliance Report</h1>
        <p>Generated: $(Get-Date -Format "dd.MM.yyyy HH:mm:ss")</p>
    </div>
    
    <div class="stats">
        <div class="stat-box">
            <div class="stat-value">$total</div>
            <div>Total Devices</div>
        </div>
        <div class="stat-box">
            <div class="stat-value compliant">$compliant</div>
            <div>Compliant</div>
        </div>
        <div class="stat-box">
            <div class="stat-value non-compliant">$nonCompliant</div>
            <div>Non-Compliant</div>
        </div>
        <div class="stat-box">
            <div class="stat-value">$successRate%</div>
            <div>Success Rate</div>
        </div>
    </div>
    
    <table>
        <thead>
            <tr>
                <th>Computer</th>
                <th>Operating System</th>
                <th>Last Inventory</th>
                <th>Account Tag</th>
                <th>In Entra</th>
                <th>In Intune</th>
                <th>Status</th>
            </tr>
        </thead>
        <tbody>
"@
    
    foreach ($result in $Results) {
        $statusClass = if ($result.Status -eq 'COMPLIANT') { 'status-compliant' } else { 'status-non-compliant' }
        $entraIcon = if ($result.InEntra) { '✓' } else { '✗' }
        $intuneIcon = if ($result.InIntune) { '✓' } else { '✗' }
        
        $html += @"
            <tr>
                <td>$($result.Computer)</td>
                <td>$($result.OperatingSystem)</td>
                <td>$($result.LastInventory)</td>
                <td>$($result.AccountTag)</td>
                <td>$entraIcon</td>
                <td>$intuneIcon</td>
                <td class="$statusClass">$($result.Status)</td>
            </tr>
"@
    }
    
    $html += @"
        </tbody>
    </table>
    
    <div class="footer">
        <p>OCS Inventory Compliance Checker v2.5 (MySQL Connector/NET)</p>
    </div>
</body>
</html>
"@
    
    return $html
}

# ============================================================================
# HLAVNA LOGIKA
# ============================================================================

try {
    Write-Host "`n"
    Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║     OCS INVENTORY COMPLIANCE CHECKER v2.5                  ║" -ForegroundColor Cyan
    Write-Host "║     MySQL Connector/NET Edition                           ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host "`n"
    
    # Kontrola modulov
    if (-not (Test-RequiredModules -AutoInstall:$AutoInstallModules)) {
        throw "Nepodarilo sa pripravit potrebne moduly"
    }
    
    # Inicializacia MySQL Connector
    Write-Log "Inicializujem MySQL Connector/NET..." -Level Info
    Initialize-MySQLConnector
    
    # Pripojenie k Microsoft Graph
    Write-Log "Pripajam sa k Microsoft Graph..." -Level Info
    $graphConnected = Connect-MgGraphWithApp -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret
    
    if (-not $graphConnected) {
        throw "Nepodarilo sa pripojit k Microsoft Graph"
    }
    
    # Ziskanie zariadeni z OCS
    Write-Log "Ziskavam zariadenia z MySQL OCS Inventory..." -Level Info
    $ocsComputers = Get-OCSComputers -Server $OcsDBServer -Database $OcsDBName -Username $OcsDBUser -Password $OcsDBPassword
    
    if ($null -eq $ocsComputers -or $ocsComputers.Rows.Count -eq 0) {
        Write-Log "Databaza vratila 0 zariadeni alebo ziadne zariadenia nesplnaju podmienky" -Level Warning
        $results = @()
    }
    else {
        # Nacitanie zariadeni z Entra a Intune
        Write-Log "Nacitavam zariadenia z Entra ID a Intune..." -Level Info
        $entraDevices = Get-AllEntraDevices
        $intuneDevices = Get-AllIntuneDevices
        
        # Spracovanie zariadeni
        Write-Log "Kontrola existencie v Entra ID a Intune..." -Level Info
        
        $results = @()
        $counter = 0
        $totalDevices = $ocsComputers.Rows.Count
        
        foreach ($row in $ocsComputers.Rows) {
            $counter++

            # Bezpecny pristup k hodnotam
            $computerName = if ($row["Computer"] -ne [DBNull]::Value) { $row["Computer"].ToString().Trim() } else { "Unknown" }
            $os = if ($row["OperatingSystem"] -ne [DBNull]::Value) { $row["OperatingSystem"].ToString().Trim() } else { "Unknown" }
            $lastInv = if ($row["LastInventory"] -ne [DBNull]::Value) { $row["LastInventory"].ToString().Trim() } else { "Never" }
            $tag = if ($row["AccountTag"] -ne [DBNull]::Value) { $row["AccountTag"].ToString().Trim() } else { "" }
            
            # Preskoc prazdne mena zariadeni
            if ([string]::IsNullOrWhiteSpace($computerName) -or $computerName -eq "Unknown") {
                Write-Log "Preskakujem zariadenie s prazdnym menom" -Level Warning
                continue
            }
            
            # Rychle vyhladavanie v hashtable
            $inEntra = $entraDevices.ContainsKey($computerName)
            $inIntune = $intuneDevices.ContainsKey($computerName)
            
            $result = [PSCustomObject]@{
                'Computer'        = $computerName
                'OperatingSystem' = $os
                'LastInventory'   = $lastInv
                'AccountTag'      = $tag
                'InEntra'         = $inEntra
                'InIntune'        = $inIntune
                'Status'          = if ($inEntra -and $inIntune) { 'COMPLIANT' } else { 'NON-COMPLIANT' }
            }
            
            $results += $result
            
            $percentComplete = [math]::Round(($counter / $totalDevices) * 100, 2)
            Write-Progress -Activity "Kontrola zariadeni" -Status "Spracovavam $computerName ($counter/$totalDevices)" -PercentComplete $percentComplete
        }
        
        Write-Progress -Activity "Kontrola zariadeni" -Completed
    }
    
    if ($results.Count -eq 0) {
        Write-Log "Ziadne zariadenia na spracovanie" -Level Warning
        Write-Log "Skontrolujte SQL query a podmienky v OCS databaze" -Level Info
        exit 0
    }
    
    # Zobrazenie vysledkov
    Write-Host "`n"
    Write-Log "=== VYSLEDKY ===" -Level Info
    $results | Format-Table -AutoSize
    
    # Export vysledkov
    $exportedFiles = Export-Results -Results $results -Path $ExportPath
    
    # Statistiky
    $total = $results.Count
    $compliant = ($results | Where-Object { $_.Status -eq 'COMPLIANT' }).Count
    $nonCompliant = ($results | Where-Object { $_.Status -eq 'NON-COMPLIANT' }).Count
    
    Write-Host "`n"
    Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                      STATISTIKY                            ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Log "Celkovy pocet zariadeni:    $total" -Level Info
    Write-Log "Kompliantne zariadenia:     $compliant" -Level Success
    Write-Log "Nekompliantne zariadenia:   $nonCompliant" -Level Error
    
    if ($total -gt 0) {
        $successRate = [math]::Round(($compliant / $total) * 100, 2)
        Write-Log "Uspesnost:                  $successRate%" -Level Info
        
        # Zobrazenie nekompliantnych zariadeni
        if ($nonCompliant -gt 0) {
            Write-Host "`n"
            Write-Log "=== NEKOMPLIANTNE ZARIADENIA ===" -Level Warning
            $nonCompliantDevices = $results | Where-Object { $_.Status -eq 'NON-COMPLIANT' }
            $nonCompliantDevices | Select-Object Computer, OperatingSystem, InEntra, InIntune | Format-Table -AutoSize
            
            Write-Log "Pocet zariadeni chybajucich v Entra: $(($nonCompliantDevices | Where-Object { -not $_.InEntra }).Count)" -Level Warning
            Write-Log "Pocet zariadeni chybajucich v Intune: $(($nonCompliantDevices | Where-Object { -not $_.InIntune }).Count)" -Level Warning
        }
    }
    
    Write-Host "`n"
    Write-Log "Skript ukonceny uspesne" -Level Success
    Write-Log "Vysledky najdete v: $ExportPath" -Level Success
    Write-Log "CSV: $($exportedFiles.CSV)" -Level Info
    Write-Log "HTML: $($exportedFiles.HTML)" -Level Info
}
catch {
    Write-Log "KRITICKA CHYBA: $($_.Exception.Message)" -Level Error
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Level Error
    exit 1
}
finally {
    # Cleanup
    try {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        Write-Log "Odpojene od Microsoft Graph" -Level Success
    }
    catch {
        # Ignorujeme chyby pri odpajani
    }
}

Write-Host "`n"