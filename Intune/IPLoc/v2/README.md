# IP Location Detection for Intune

**Version:** 3.0 (Enhanced)  
**Author:** TaurisIT  
**Date:** December 2025

## 📋 Overview

Automatický systém na detekciu lokality zariadení na základe IP adresy a aktualizáciu Entra ID (Azure AD) cez Microsoft Graph API. Optimalizovaný pre Microsoft Intune deployment.

### ✨ Nové funkcie vo verzii 3.0

- ✅ **Exponential backoff retry logic** pre Graph API volania
- ✅ **VPN detekcia** - automatické rozpoznanie VPN pripojenia
- ✅ **Token caching** - efektívnejšie Graph API volania
- ✅ **Secure registry handling** - ACL permissions na registry path
- ✅ **Enhanced error handling** - lepšie error messages a diagnostika
- ✅ **Configuration file** - centrálna konfigurácia namiesto hardcoded values
- ✅ **Health check script** - komplexná diagnostika systému
- ✅ **Log rotation** - automatické čistenie starých logov
- ✅ **Event log integration** - Windows Event Log pre monitoring
- ✅ **Pagination support** - podpora pre organizácie s >100 zariadeniami

---

## 🏗️ Architektúra

```
C:\TaurisIT\IPcheck\
│
├── detection.ps1              # Intune Detection Script
├── remediation.ps1            # Intune Remediation Script  
├── install.ps1                # Installation Script
├── uninstall.ps1              # Uninstallation Script
├── health-check.ps1           # Health Check & Diagnostics
│
├── CommonFunctions.psm1       # Shared Functions Module
├── GraphHelper.psm1           # Graph API Helper Module
│
├── config.json                # Configuration File
├── IPLocationMap.json         # IP to Location Mapping
└── .env                       # Graph API Credentials (SECURE!)

C:\Program Files\WindowsPowerShell\Modules\
└── LogHelper\
    └── LogHelper.psm1         # Centralized Logging Module

C:\TaurisIT\Log\IPcheck\
├── IPcheck_Detection.log      # Detection logs
├── IPcheck_Remediation.log    # Remediation logs
├── GraphUpdate_Success.log    # Graph API success log
└── GraphUpdate_Errors.log     # Graph API error log
```

---

## 🚀 Quick Start

### 1. Príprava Azure AD App Registration

#### Vytvorenie App Registration:
```powershell
# Connect to Microsoft Graph
Connect-MgGraph -Scopes "Application.ReadWrite.All"

# Create app registration
$appReg = New-MgApplication -DisplayName "IPLocationDetection-Prod" `
    -SignInAudience "AzureADMyOrg"

# Create service principal
$sp = New-MgServicePrincipal -AppId $appReg.AppId

# Create client secret
$secret = Add-MgApplicationPassword -ApplicationId $appReg.Id `
    -PasswordCredential @{ DisplayName = "IPLocationSecret" }

Write-Host "Tenant ID: $((Get-MgOrganization).Id)"
Write-Host "Client ID: $($appReg.AppId)"
Write-Host "Client Secret: $($secret.SecretText)"
```

#### Nastavenie Permissions:

V Azure Portal → App registrations → [Your App] → API permissions:

1. Kliknite **Add a permission**
2. Vyberte **Microsoft Graph**
3. Vyberte **Application permissions**
4. Pridajte:
   - ✅ `Device.ReadWrite.All` (Required)
   - ✅ `Directory.Read.All` (Optional - lepšie vyhľadávanie)
5. Kliknite **Grant admin consent**

### 2. Inštalácia

#### A. Lokálna inštalácia (testovanie):

```powershell
# 1. Stiahnite všetky súbory do jedného adresára
cd C:\Temp\IPLocationDetection

# 2. Vytvorte .env súbor s credentials
@"
GRAPH_TENANT_ID=your-tenant-id-here
GRAPH_CLIENT_ID=your-client-id-here
GRAPH_CLIENT_SECRET=your-client-secret-here
"@ | Set-Content .env

# 3. Upravte IPLocationMap.json podľa vašej siete

# 4. Spustite inštaláciu (ako Administrator)
.\install.ps1

# 5. Overte inštaláciu
.\health-check.ps1 -Detailed -TestGraphAPI
```

#### B. Intune Deployment:

1. **Vytvorte Win32 App Package:**
```powershell
# Použite Microsoft Win32 Content Prep Tool
IntuneWinAppUtil.exe -c "C:\Source\IPLocationDetection" `
                     -s "install.ps1" `
                     -o "C:\Output" `
                     -q
```

2. **Upload do Intune:**
   - Intune Admin Center → Apps → Windows → Add
   - App type: Windows app (Win32)
   - Install command: `powershell.exe -ExecutionPolicy Bypass -File install.ps1`
   - Uninstall command: `powershell.exe -ExecutionPolicy Bypass -File uninstall.ps1`
   - Detection rule: Registry
     - Key: `HKEY_LOCAL_MACHINE\SOFTWARE\TaurisIT\IPcheck`
     - Value: `CurrentLocation`
     - Detection method: Key exists

3. **Vytvorte Proactive Remediation:**
   - Intune Admin Center → Devices → Remediations → Create
   - Detection script: `detection.ps1`
   - Remediation script: `remediation.ps1`
   - Run as: System
   - Schedule: Daily

---

## ⚙️ Konfigurácia

### config.json

```json
{
    "Paths": {
        "LogDirectory": "C:\\TaurisIT\\Log\\IPcheck",
        "ScriptDirectory": "C:\\TaurisIT\\IPcheck",
        "RegistryPath": "HKLM:\\SOFTWARE\\TaurisIT\\IPcheck",
        "LogModulePath": "C:\\Program Files\\WindowsPowerShell\\Modules\\LogHelper\\LogHelper.psm1"
    },
    "GraphAPI": {
        "RetryAttempts": 3,
        "RetryDelaySeconds": 2,
        "Timeout": 30,
        "UseExponentialBackoff": true,
        "MaxDeviceSearchResults": 1000
    },
    "Detection": {
        "CacheValidityHours": 24,
        "RequireGraphUpdate": false,
        "AllowVPNDetection": true,
        "FallbackToLastKnownLocation": true
    },
    "Logging": {
        "EnableFileLogging": true,
        "EnableEventLogging": true,
        "EnableConsoleLogging": true,
        "MaxLogSizeMB": 10,
        "LogRetentionDays": 30
    },
    "Security": {
        "UseKeyVault": false,
        "KeyVaultName": "",
        "SecureRegistryPath": true
    }
}
```

### IPLocationMap.json

```json
{
    "10.10.0.": "RS",
    "10.20.20.": "Server",
    "10.30.0.": "SNV",
    "10.40.0.": "NR",
    "192.168.1.": "HomeOffice"
}
```

**Formát:**
- Kľúč: IP prefix (3 oktety + bodka)
- Hodnota: Kód lokality (max 64 znakov)

---

## 🔐 Bezpečnosť

### ⚠️ KRITICKÉ BEZPEČNOSTNÉ UPOZORNENIA

1. **NIKDY** nezdieľajte `.env` súbor publicky
2. **NIKDY** necommitujte `.env` do Git
3. **PRAVIDELNE** rotujte Client Secret (každých 90 dní)
4. **VŽDY** používajte Azure Key Vault v produkcii

### Odporúčané bezpečnostné praktiky:

```powershell
# 1. Nastavte správne NTFS permissions na .env
$envPath = "C:\TaurisIT\IPcheck\.env"
$acl = Get-Acl $envPath
$acl.SetAccessRuleProtection($true, $false)

# SYSTEM - Full Control
$systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    "NT AUTHORITY\SYSTEM", "FullControl", "Allow"
)
$acl.AddAccessRule($systemRule)

# Administrators - Full Control  
$adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    "BUILTIN\Administrators", "FullControl", "Allow"
)
$acl.AddAccessRule($adminRule)

Set-Acl -Path $envPath -AclObject $acl

# 2. Zabezpečte registry path
$regPath = "HKLM:\SOFTWARE\TaurisIT\IPcheck"
$regAcl = Get-Acl $regPath
$regAcl.SetAccessRuleProtection($true, $false)
# ... podobne ako vyššie
```

### Azure Key Vault integrácia (budúcnosť):

```json
{
    "Security": {
        "UseKeyVault": true,
        "KeyVaultName": "kv-iplocation-prod",
        "TenantIdSecretName": "GraphTenantId",
        "ClientIdSecretName": "GraphClientId",
        "ClientSecretName": "GraphClientSecret"
    }
}
```

---

## 🔧 Použitie

### Manuálne testovanie:

```powershell
# Test detection
.\detection.ps1 -Verbose

# Test remediation
.\remediation.ps1 -Verbose

# Health check
.\health-check.ps1 -Detailed -TestGraphAPI -ExportReport
```

### Exit kódy:

| Kód | Význam | Akcia |
|-----|--------|-------|
| 0 | Success / Compliant | Žiadna akcia |
| 1 | Remediation Required | Spusti remediation |

---

## 📊 Monitoring & Diagnostika

### Health Check

```powershell
# Základný health check
.\health-check.ps1

# Detailný check s Graph API testom
.\health-check.ps1 -Detailed -TestGraphAPI

# Export reportu
.\health-check.ps1 -ExportReport
```

### Windows Event Log

Všetky kritické udalosti sa logujú do:
- **Log Name:** Application
- **Source:** TaurisIT-IPCheck
- **Event IDs:**
  - 1000: Information
  - 1001: Critical
  - 1002: Error
  - 1003: Warning

### Kontrola logov:

```powershell
# Zobraziť posledných 50 záznamov
Get-Content "C:\TaurisIT\Log\IPcheck\IPcheck_Detection.log" -Tail 50

# Zobraziť Graph API chyby
Get-Content "C:\TaurisIT\Log\IPcheck\GraphUpdate_Errors.log"

# Zobraziť Windows Event Log
Get-EventLog -LogName Application -Source "TaurisIT-IPCheck" -Newest 20
```

### Štatistiky logov:

```powershell
Import-Module "C:\Program Files\WindowsPowerShell\Modules\LogHelper\LogHelper.psm1"
Get-LogStatistics
```

---

## 🐛 Troubleshooting

### Problém: "Could not detect IP address"

**Možné príčiny:**
1. VPN pripojenie aktívne
2. Žiadny sieťový adaptér
3. APIPA adresa (169.254.x.x)

**Riešenie:**
```powershell
# Skontrolujte sieťové adaptéry
Get-NetAdapter | Where-Object Status -eq 'Up'

# Skontrolujte IP adresy
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { 
    $_.IPAddress -notmatch '^(169\.254\.|127\.)'
}

# Vypnite VPN detection ak potrebujete
# V config.json nastavte: "AllowVPNDetection": false
```

### Problém: "Device not found in Entra ID"

**Možné príčiny:**
1. Zariadenie nie je Azure AD Joined
2. Zariadenie ešte nie je synchronizované
3. Nesprávne permissions

**Riešenie:**
```powershell
# Skontrolujte Azure AD join status
dsregcmd /status

# Skontrolujte Device ID
$regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin\JoinInfo"
Get-ChildItem $regPath | ForEach-Object {
    Get-ItemProperty $_.PSPath | Select-Object DeviceId
}

# Skontrolujte permissions v Azure Portal
# App Registration → API permissions → Device.ReadWrite.All
```

### Problém: "Graph API 401 Unauthorized"

**Možné príčiny:**
1. Nesprávne credentials v .env
2. Client Secret expirovaný
3. Chýbajúce admin consent

**Riešenie:**
```powershell
# Test credentials
.\health-check.ps1 -TestGraphAPI

# Regenerujte Client Secret:
# Azure Portal → App registrations → Certificates & secrets → New client secret

# Overte admin consent:
# Azure Portal → App registrations → API permissions → Grant admin consent
```

### Problém: "Scheduled task not running"

**Riešenie:**
```powershell
# Skontrolujte task
Get-ScheduledTask -TaskName "TaurisIT-IPLocation-Detection"

# Skontrolujte history
Get-ScheduledTaskInfo -TaskName "TaurisIT-IPLocation-Detection"

# Manuálne spustite
Start-ScheduledTask -TaskName "TaurisIT-IPLocation-Detection"

# Skontrolujte logy
Get-EventLog -LogName Application -Source "TaurisIT-IPCheck" -Newest 10
```

---

## 📈 Performance & Limity

### Graph API Rate Limits

- **Read operations:** 1,200 requests / minute
- **Write operations:** 600 requests / minute
- **Token lifetime:** ~60 minút (cached 50 minút)

**Optimalizácie v v3.0:**
- Token caching
- Exponential backoff
- Batch operations ready

### Odporúčania pre veľké organizácie (>1000 zariadení)

```json
{
    "GraphAPI": {
        "MaxDeviceSearchResults": 5000,
        "RetryAttempts": 5,
        "UseExponentialBackoff": true
    },
    "Detection": {
        "CacheValidityHours": 48
    }
}
```

---

## 🔄 Aktualizácia

### Z verzie 2.x na 3.0:

```powershell
# 1. Záloha
Copy-Item "C:\TaurisIT\IPcheck" "C:\TaurisIT\IPcheck.backup" -Recurse

# 2. Odinštalovanie starej verzie
.\uninstall.ps1 -KeepLogs -KeepRegistry

# 3. Inštalácia novej verzie
.\install.ps1

# 4. Migrácia konfigurácie (ak potrebné)
# config.json a IPLocationMap.json by mali byť kompatibilné
```

---

## 🧪 Testing

### Unit Testing:

```powershell
# Test IP detection
$ip = Get-PrimaryIPAddress
Write-Host "Detected IP: $ip"

# Test location mapping
$map = Load-IPLocationMap
$location = Get-LocationFromIP -IPAddress $ip -Map $map
Write-Host "Location: $location"

# Test Azure AD Device ID
$deviceId = Get-AzureADDeviceId
Write-Host "Device ID: $deviceId"

# Test Graph API connection
Import-Module .\GraphHelper.psm1
$creds = Load-EnvCredentials
$token = Get-GraphToken @creds
Test-GraphConnection -AccessToken $token
```

### Integration Testing:

```powershell
# Full cycle test
1. .\detection.ps1 -Verbose    # Should return exit code 1 (first run)
2. .\remediation.ps1 -Verbose  # Should set location
3. .\detection.ps1 -Verbose    # Should return exit code 0 (compliant)
4. .\health-check.ps1 -Detailed # All checks should pass
```

---

## 📝 Changelog

### Version 3.0 (December 2025)
- ✨ Complete rewrite with modular architecture
- ✅ Exponential backoff retry logic
- ✅ VPN detection
- ✅ Token caching
- ✅ Secure registry handling
- ✅ Configuration file support
- ✅ Health check script
- ✅ Enhanced error handling
- ✅ Log rotation
- ✅ Event log integration
- ✅ Pagination support

### Version 2.1 (Previous)
- LogHelper module integration
- Basic retry logic
- Registry caching

---

## 🤝 Support & Contributing

### Reporting Issues:

Pre reportovanie problémov použite:
```powershell
# Vygenerujte diagnostický report
.\health-check.ps1 -Detailed -TestGraphAPI -ExportReport

# Attach: C:\TaurisIT\Log\IPcheck\HealthCheck_[timestamp].txt
```

### Kontakt:
- **Email:** support@taurisit.com
- **Teams:** TaurisIT Support Channel

---

## 📄 License

Proprietary - TaurisIT © 2025  
Pre interné použitie v organizácii.

---

## ✅ Pre-Deployment Checklist

- [ ] Azure AD App Registration vytvorená
- [ ] Device.ReadWrite.All permission udelené
- [ ] Admin consent granted
- [ ] Client Secret zaznamenané
- [ ] .env súbor vytvorený a zabezpečený
- [ ] IPLocationMap.json nakonfigurovaná
- [ ] config.json skontrolovaná
- [ ] Lokálne testovanie úspešné
- [ ] Health check prejde
- [ ] Intune package vytvorený
- [ ] Pilot skupina definovaná
- [ ] Rollback plán pripravený
- [ ] Monitoring nastavený

---

**Happy Deploying! 🚀**