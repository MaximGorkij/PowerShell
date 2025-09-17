<#
.SYNOPSIS
    Export pouzivatelov z Microsoft Entra ID

.DESCRIPTION
    Skript nacita prihlasovacie udaje z XML, pripoji sa k Microsoft Graph,
    ziska pouzivatelov, priradi licencie a datum posledneho prihlasenia,
    ulozi CSV a zapisuje chyby do logu.

.AUTHOR
    Marek Findrik

.CREATED
    2025-09-17

.VERSION
    4.3
#>

# Zistenie adresara skriptu
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $scriptDirectory) {
    $scriptDirectory = Get-Location
}

# Cesty k suborom
$authXmlPath = Join-Path $scriptDirectory 'GraphAuth.xml'
$logPath     = Join-Path $scriptDirectory 'Export_ErrorLog.txt'
$timestamp   = Get-Date -Format "yyyyMMdd_HHmmss"
$csvPath     = Join-Path $scriptDirectory "Entra_Users_Export_$timestamp.csv"

# Funkcia na zapis do logu
function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    $logTimestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "$logTimestamp - $Level - $Message"
    Add-Content -Path $logPath -Value $logEntry
    
    switch ($Level) {
        "ERROR" { Write-Host $logEntry -ForegroundColor Red }
        "WARNING" { Write-Host $logEntry -ForegroundColor Yellow }
        "INFO" { Write-Host $logEntry -ForegroundColor Green }
        "DEBUG" { Write-Host $logEntry -ForegroundColor Gray }
        default { Write-Host $logEntry -ForegroundColor White }
    }
}

# Funkcia pre export CSV so spravnym kodovanim
function Export-CsvWithEncoding {
    param (
        [object]$Data,
        [string]$Path,
        [string]$Delimiter = ";",
        [string]$Encoding = "Windows-1250"
    )
    
    try {
        # Konverzia na UTF8 s BOM a potom na Windows-1250
        $tempPath = [System.IO.Path]::GetTempFileName()
        $Data | Export-Csv -Path $tempPath -NoTypeInformation -Delimiter $Delimiter -Encoding UTF8
        
        # Precitat UTF8 subor a ulozit ako Windows-1250
        $content = Get-Content -Path $tempPath -Encoding UTF8
        $content | Out-File -FilePath $Path -Encoding $Encoding -Force
        
        Remove-Item -Path $tempPath -Force
        return $true
    }
    catch {
        Write-Log "Chyba pri exporte CSV: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# Inicializacia log suboru
Write-Log "=== SPUSTENIE EXPORTU POUZIVATELOV ===" "INFO"
Write-Log "Skript verzia 4.3" "INFO"
Write-Log "Startovaci adresar: $scriptDirectory" "INFO"

# Kontrola existencie XML suboru
if (-not (Test-Path $authXmlPath)) {
    Write-Log "CHYBA: XML subor s autentifikaciou neexistuje: $authXmlPath" "ERROR"
    Write-Log "Vytvorte prosim subor GraphAuth.xml s nasledujucou strukturou:" "ERROR"
    Write-Log "<?xml version=`"1.0`" encoding=`"utf-8`"?>" "ERROR"
    Write-Log "<GraphAuth>" "ERROR"
    Write-Log "    <TenantId>your_tenant_id_here</TenantId>" "ERROR"
    Write-Log "    <ClientId>your_client_id_here</ClientId>" "ERROR"
    Write-Log "    <ClientSecret>your_client_secret_here</ClientSecret>" "ERROR"
    Write-Log "</GraphAuth>" "ERROR"
    exit 1
}

# Nacitanie autentifikacnych udajov z XML
try {
    [xml]$authData = Get-Content -Path $authXmlPath -ErrorAction Stop
    $tenantId     = $authData.GraphAuth.TenantId.Trim()
    $clientId     = $authData.GraphAuth.ClientId.Trim()
    $clientSecret = $authData.GraphAuth.ClientSecret.Trim()

    # Validacia povinnych parametrov
    $requiredNodes = @('TenantId', 'ClientId', 'ClientSecret')
    foreach ($node in $requiredNodes) {
        if ([string]::IsNullOrEmpty($authData.GraphAuth.$node)) {
            throw "Chybajuci povinny parameter v XML: $node"
        }
    }

    Write-Log "Autentifikacne udaje uspesne nacitane" "INFO"
}
catch {
    Write-Log "Nepodarilo sa nacitat XML s autentifikaciou: $($_.Exception.Message)" "ERROR"
    exit 1
}

# Import modulu Microsoft.Graph
try {
    $requiredModules = @(
        'Microsoft.Graph.Authentication',
        'Microsoft.Graph.Users',
        'Microsoft.Graph.Identity.DirectoryManagement',
        'Microsoft.Graph.Identity.SignIns'
    )
    
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -ListAvailable -Name $module -ErrorAction SilentlyContinue)) {
            Write-Log "Modul $module nie je nainstalovany, instalacia..." "INFO"
            Install-Module $module -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
        }
        
        Import-Module $module -Force -ErrorAction Stop
    }
    
    Write-Log "Vsetky moduly Microsoft Graph uspesne nacitane" "INFO"
}
catch {
    Write-Log "Nepodarilo sa nacitat moduly Microsoft.Graph: $($_.Exception.Message)" "ERROR"
    exit 1
}

# Pripojenie k Microsoft Graph pomocou ClientSecretCredential
try {
    $context = Get-MgContext -ErrorAction SilentlyContinue
    if (-not $context -or $context.TenantId -ne $tenantId) {
        Write-Log "Pripojenie k Microsoft Graph pomocou Client Secret..." "INFO"
        
        # Vytvorenie credential objektu
        $secureSecret = ConvertTo-SecureString $clientSecret -AsPlainText -Force
        $credential = [System.Management.Automation.PSCredential]::new($clientId, $secureSecret)
        
        # Pripojenie pomocou Connect-MgGraph s parametrami
        $connectionParams = @{
            ClientSecretCredential = $credential
            TenantId               = $tenantId
            ErrorAction            = 'Stop'
        }
        
        Connect-MgGraph @connectionParams
        Write-Log "USPECH - Pripojenie k Microsoft Graph uspesne" "INFO"
    }
    else {
        Write-Log "Uz pripojene k Microsoft Graph" "INFO"
    }
}
catch {
    Write-Log "Nepodarilo sa pripojit k Microsoft Graph: $($_.Exception.Message)" "ERROR"
    exit 1
}

# Ziskanie pouzivatelov
try {
    Write-Log "Ziskavanie zoznamu pouzivatelov..." "INFO"
    
    $userProperties = @(
        "id",
        "displayName",
        "userPrincipalName",
        "mail",
        "jobTitle",
        "department",
        "accountEnabled",
        "createdDateTime",
        "lastPasswordChangeDateTime",
        "userType"
    )
    
    $users = Get-MgUser -All -Property $userProperties -ErrorAction Stop
    Write-Log "Nacitanych pouzivatelov: $($users.Count)" "INFO"
    
    if ($users.Count -eq 0) {
        Write-Log "Neboli najdeni ziadni pouzivatelia" "WARNING"
        exit 0
    }
}
catch {
    Write-Log "Nepodarilo sa nacitat pouzivatelov: $($_.Exception.Message)" "ERROR"
    Disconnect-MgGraph -ErrorAction SilentlyContinue
    exit 1
}

# Priprava vysledkov
$results = @()
$counter = 0
$totalUsers = $users.Count
$errorCount = 0

Write-Log "Spracovavanie pouzivatelov..." "INFO"

foreach ($user in $users) {
    $counter++
    $percentComplete = [math]::Round(($counter / $totalUsers) * 100, 2)
    
    Write-Progress -Activity "Spracovavanie pouzivatelov" -Status "Pouzivatel $counter z $totalUsers ($percentComplete%)" -PercentComplete $percentComplete -CurrentOperation $user.UserPrincipalName

    try {
        # Ziskanie licencii
        $licenseString = "Ziaden"
        try {
            $licenseDetails = Get-MgUserLicenseDetail -UserId $user.Id -ErrorAction Stop
            if ($licenseDetails) {
                $licenseSkus = @()
                foreach ($license in $licenseDetails) {
                    $licenseSkus += $license.SkuPartNumber
                }
                $licenseString = $licenseSkus -join '; '
            }
        }
        catch {
            Write-Log "Nepodarilo sa ziskat licence pre pouzivatela $($user.UserPrincipalName): $($_.Exception.Message)" "WARNING"
        }

        # Ziskanie posledneho prihlasenia - OPRAVENE
        $lastSignIn = $null
        try {
            # Metoda 1: Pouzitie SignInActivity z user objektu (ak je dostupne)
            $userWithSignIn = Get-MgUser -UserId $user.Id -Property "signInActivity" -ErrorAction SilentlyContinue
            if ($userWithSignIn -and $userWithSignIn.SignInActivity -and $userWithSignIn.SignInActivity.LastSignInDateTime) {
                $lastSignIn = $userWithSignIn.SignInActivity.LastSignInDateTime
                Write-Log "LastSignIn najdene pre $($user.UserPrincipalName): $lastSignIn" "DEBUG"
            }
            else {
                # Metoda 2: Hladanie v audit logoch
                $signIns = Get-MgAuditLogSignIn -Filter "userDisplayName eq '$($user.DisplayName)'" -Top 1 -All -ErrorAction SilentlyContinue | 
                          Sort-Object CreatedDateTime -Descending
                if ($signIns -and $signIns.Count -gt 0) {
                    $lastSignIn = $signIns[0].CreatedDateTime
                    Write-Log "LastSignIn z audit logu pre $($user.UserPrincipalName): $lastSignIn" "DEBUG"
                }
                else {
                    # Metoda 3: Hladanie podla userPrincipalName
                    $signIns = Get-MgAuditLogSignIn -Filter "userPrincipalName eq '$($user.UserPrincipalName)'" -Top 1 -All -ErrorAction SilentlyContinue | 
                              Sort-Object CreatedDateTime -Descending
                    if ($signIns -and $signIns.Count -gt 0) {
                        $lastSignIn = $signIns[0].CreatedDateTime
                        Write-Log "LastSignIn z UPN pre $($user.UserPrincipalName): $lastSignIn" "DEBUG"
                    }
                }
            }
        }
        catch {
            Write-Log "Nepodarilo sa ziskat prihlasenia pre pouzivatela $($user.UserPrincipalName): $($_.Exception.Message)" "DEBUG"
        }

        $results += [PSCustomObject]@{
            DisplayName           = $user.DisplayName
            UserPrincipalName     = $user.UserPrincipalName
            Email                 = $user.Mail
            JobTitle              = $user.JobTitle
            Department            = $user.Department
            AccountEnabled        = $user.AccountEnabled
            CreatedDate           = $user.CreatedDateTime
            LastPasswordChange    = $user.LastPasswordChangeDateTime
            UserType              = $user.UserType
            Licenses              = $licenseString
            LastSignIn            = $lastSignIn
            UserId                = $user.Id
        }

        if ($counter % 100 -eq 0) {
            Write-Log "Spracovanych pouzivatelov: $counter/$totalUsers" "INFO"
        }
    }
    catch {
        $errorCount++
        Write-Log "Chyba pri spracovani pouzivatela $($user.UserPrincipalName): $($_.Exception.Message)" "ERROR"
        
        # Pridanie aspon zakladnych informacii aj pri chybe
        $results += [PSCustomObject]@{
            DisplayName           = $user.DisplayName
            UserPrincipalName     = $user.UserPrincipalName
            Email                 = $user.Mail
            JobTitle              = $user.JobTitle
            Department            = $user.Department
            AccountEnabled        = $user.AccountEnabled
            CreatedDate           = $user.CreatedDateTime
            LastPasswordChange    = $user.LastPasswordChangeDateTime
            UserType              = $user.UserType
            Licenses              = "CHYBA: $($_.Exception.Message)"
            LastSignIn            = $null
            UserId                = $user.Id
        }
    }
}

Write-Progress -Activity "Spracovavanie pouzivatelov" -Completed

# Export do CSV so spravnym kodovanim pre slovensku diakritiku
try {
    Write-Log "Export do CSV suboru s kodovanim Windows-1250..." "INFO"
    
    if ($results.Count -eq 0) {
        throw "Ziadne data na export"
    }
    
    # Pouzitie vlastnej funkcie pre spravne kodovanie
    $exportSuccess = Export-CsvWithEncoding -Data $results -Path $csvPath -Delimiter ";" -Encoding "Windows-1250"
    
    if ($exportSuccess) {
        Write-Log "USPECH - Export dokonceny: $csvPath" "INFO"
        Write-Log "Celkovo exportovanych pouzivatelov: $($results.Count)" "INFO"
        Write-Log "Pocet chyb pri spracovani: $errorCount" "INFO"
        
        # Zobrazenie statistik
        $enabledUsers = ($results | Where-Object { $_.AccountEnabled -eq $true }).Count
        $usersWithLicenses = ($results | Where-Object { $_.Licenses -ne "Ziaden" -and $_.Licenses -notlike "CHYBA:*" }).Count
        $usersWithSignIn = ($results | Where-Object { $_.LastSignIn -ne $null }).Count
        
        Write-Log "Statistika:" "INFO"
        Write-Log "  - Povoleni ucty: $enabledUsers" "INFO"
        Write-Log "  - Ucty s licenciami: $usersWithLicenses" "INFO"
        Write-Log "  - Ucty s prihlasenim: $usersWithSignIn" "INFO"
        Write-Log "  - Ucty bez licencii: $($results.Count - $usersWithLicenses)" "INFO"
    }
    else {
        throw "Nepodarilo sa exportovat data"
    }
}
catch {
    Write-Log "Nepodarilo sa exportovat do CSV: $($_.Exception.Message)" "ERROR"
}

# Odpojenie od Graph API
try {
    Disconnect-MgGraph -ErrorAction SilentlyContinue
    Write-Log "Odpojene od Microsoft Graph" "INFO"
}
catch {
    Write-Log "Chyba pri odpojovani od Microsoft Graph: $($_.Exception.Message)" "WARNING"
}

# Zobrazenie finalneho statusu
Write-Log "=== KONIEC EXPORTU ===" "INFO"

if ($results.Count -gt 0) {
    $usersWithSignIn = ($results | Where-Object { $_.LastSignIn -ne $null }).Count
    Write-Host "`nEXPORT USPESNE DOKONCENY" -ForegroundColor Green
    Write-Host "Subor: $csvPath" -ForegroundColor Cyan
    Write-Host "Pocet zaznamov: $($results.Count)" -ForegroundColor Cyan
    Write-Host "Pouzivatelia s prihlasenim: $usersWithSignIn" -ForegroundColor Cyan
    Write-Host "Kodovanie: Windows-1250 (pre slovensku diakritiku)" -ForegroundColor Cyan
    Write-Host "Chybovy log: $logPath" -ForegroundColor Yellow
    Write-Host "Pocet chyb: $errorCount" -ForegroundColor $(if($errorCount -gt 0){"Red"}else{"Green"})
}
else {
    Write-Host "`nEXPORT ZLYHAL - Ziadne data neboli exportovane" -ForegroundColor Red
}

# Otvorenie adresara s vysledkami
if (Test-Path $csvPath) {
    try {
        $openFolder = Read-Host "Chcete otvorit adresar s vysledkami? (y/n)"
        if ($openFolder -eq 'y' -or $openFolder -eq 'Y') {
            Invoke-Item (Split-Path $csvPath -Parent)
        }
    }
    catch {
        Write-Log "Nepodarilo sa otvorit adresar: $($_.Exception.Message)" "WARNING"
    }
}

# Cakanie na ukoncenie
Write-Host "`nStlacte lubovolnu klavesu pre ukoncenie..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")