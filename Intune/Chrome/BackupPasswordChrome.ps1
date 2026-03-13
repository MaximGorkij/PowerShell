#
# .SYNOPSIS
#     Intune skript - detekcia Chrome a zaloha hesiel prihlaseneho uzivatela.
# .DESCRIPTION
#     Bezi ako SYSTEM (Intune default). Detekuje Chrome, potom spusti
#     docasny skript v kontexte prihlaseneho uzivatela cez ScheduledTask
#     pre DPAPI desifrovanie hesiel. Vyzaduje PSSQLite modul.
# .NOTES
#     Verzia   : 2.0
#     Logovanie: C:\TaurisIT\Log\ChromePasswordBackup.txt
#     Vystup   : C:\TaurisIT\ChromeBackup\<username>\<profil>\Passwords.csv
#

$ModulePath = "C:\Program Files\WindowsPowerShell\Modules\LogHelper\LogHelper.psm1"
$LogFile = "C:\TaurisIT\Log\ChromePasswordBackup.txt"
$Source = "ChromePasswordBackup"
$BackupRoot = "C:\TaurisIT\ChromeBackup"
$TaskName = "TaurisIT_ChromePwdBackup"
$TempScript = "$env:ProgramData\TaurisIT\ChromePwdBackup_user.ps1"

# ---------------------------------------------------------------------------
# Import LogHelper + wrapper funkcia
# ---------------------------------------------------------------------------
if (Test-Path $ModulePath) {
    Import-Module $ModulePath -Force
}
else {
    Write-Host "[ERROR] Modul LogHelper nebol najdeny: $ModulePath" -ForegroundColor Red
    exit 1
}

function Write-Log {
    param([string]$Message, [string]$Type = "Information")
    $Color = switch ($Type) {
        "Error" { "Red" }
        "Warning" { "Yellow" }
        default { "Cyan" }
    }
    Write-Host "[$Type] $Message" -ForegroundColor $Color
    Write-CustomLog -Message $Message -EventSource $Source -LogFileName $LogFile -Type $Type
}

# ---------------------------------------------------------------------------
# KROK 1: Zisti prihlaseneho uzivatela
# ---------------------------------------------------------------------------
Write-Log "Zistujem prihlaseneho uzivatela."

$LoggedUser = $null
try {
    $Sessions = Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty UserName
    if ($Sessions -and $Sessions -ne "") { $LoggedUser = $Sessions }
}
catch { }

# Fallback cez query user
if (!$LoggedUser) {
    try {
        $QueryResult = query user 2>$null
        $ActiveLine = $QueryResult | Where-Object { $_ -match "Active" } | Select-Object -First 1
        if ($ActiveLine -match "^>?\s*(\S+)") { $LoggedUser = $matches[1] }
    }
    catch { }
}

if (!$LoggedUser) {
    Write-Log "Ziadny prihlaseny uzivatel nebol najdeny. Skript konci." "Warning"
    exit 0
}

$UserName = $LoggedUser -replace ".*\\", ""
Write-Log "Prihlaseny uzivatel: $LoggedUser (username: $UserName)"

# ---------------------------------------------------------------------------
# KROK 2: Over ci ma uzivatel nainstalovany Chrome
# ---------------------------------------------------------------------------
Write-Log "Kontrolujem instalaciu Google Chrome."

$ChromeInstalled = $false

$RegPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)
foreach ($P in $RegPaths) {
    if (Get-ItemProperty $P -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like "*Google Chrome*" }) {
        $ChromeInstalled = $true
        break
    }
}

# Fallback cez User Data priecinok
if (!$ChromeInstalled) {
    $UserSID = (Get-CimInstance Win32_UserAccount | Where-Object { $_.Name -eq $UserName }).SID
    $UserLocal = (Get-CimInstance Win32_UserProfile | Where-Object { $_.SID -eq $UserSID }).LocalPath
    if ($UserLocal -and (Test-Path "$UserLocal\AppData\Local\Google\Chrome\User Data")) {
        $ChromeInstalled = $true
    }
}

if (!$ChromeInstalled) {
    Write-Log "Google Chrome nebol najdeny pre uzivatela $UserName. Skript konci."
    exit 0
}

Write-Log "Google Chrome bol detekovany pre uzivatela $UserName."

# ---------------------------------------------------------------------------
# KROK 3: Ziskaj SID a cestu profilu prihlaseneho uzivatela
# ---------------------------------------------------------------------------
$UserSID = $null
try {
    $UserSID = (New-Object System.Security.Principal.NTAccount($LoggedUser)).Translate(
        [System.Security.Principal.SecurityIdentifier]
    ).Value
}
catch {
    Write-Log "Nepodarilo sa ziskat SID uzivatela: $($_.Exception.Message)" "Error"
    exit 1
}

$UserProfilePath = (Get-CimInstance Win32_UserProfile | Where-Object { $_.SID -eq $UserSID }).LocalPath

if (!$UserProfilePath) {
    Write-Log "Nepodarilo sa najst profil uzivatela $LoggedUser." "Error"
    exit 1
}

Write-Log "Profil uzivatela: $UserProfilePath"

# ---------------------------------------------------------------------------
# KROK 4: Priprav docasny skript pre user kontext (DPAPI vyzaduje usera)
#          Docasny skript pouziva LogHelper samostatne v user kontexte.
# ---------------------------------------------------------------------------
Write-Log "Pripravujem docasny skript pre user kontext."

$TempDir = Split-Path $TempScript
if (!(Test-Path $TempDir)) { New-Item $TempDir -ItemType Directory -Force | Out-Null }

# Poznamka: here-string @'...'@ neexpanduje premenne - $env:* expanduje az pri
# spusteni v user kontexte, co je spravne chovanie pre tento use-case.
$UserScriptContent = @'
#
# Docasny skript - spusteny v kontexte prihlaseneho uzivatela.
# Nespustaj rucne. Vygenerovany automaticky skriptom ChromePasswordBackup.
#

Add-Type -AssemblyName System.Security

$UModulePath = "C:\Program Files\WindowsPowerShell\Modules\LogHelper\LogHelper.psm1"
$ULogFile    = "C:\TaurisIT\Log\ChromePasswordBackup.txt"
$USource     = "ChromePasswordBackup_User"
$BackupRoot  = "C:\TaurisIT\ChromeBackup"
$ChromeBase  = "$env:LOCALAPPDATA\Google\Chrome\User Data"
$StatusFile  = "$env:ProgramData\TaurisIT\ChromePwdBackup_status.txt"
$SQLiteDll   = "C:\Program Files\WindowsPowerShell\Modules\PSSQLite\System.Data.SQLite.dll"

# Import LogHelper v user kontexte, fallback na plain status subor
$LogHelperLoaded = $false
if (Test-Path $UModulePath) {
    try {
        Import-Module $UModulePath -Force
        $LogHelperLoaded = $true
    }
    catch { }
}

function Write-UserLog {
    param([string]$Message, [string]$Type = "Information")
    $Stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $StatusFile -Value "[$Stamp][$Type] $Message" -Encoding UTF8
    if ($LogHelperLoaded) {
        Write-CustomLog -Message $Message -EventSource $USource -LogFileName $ULogFile -Type $Type
    }
}

Write-UserLog "Docasny user skript spusteny ako: $env:USERNAME"

if (!(Test-Path $ChromeBase)) {
    Write-UserLog "Chrome User Data nebol najdeny." "Error"
    exit 1
}

$LocalStatePath = Join-Path $ChromeBase "Local State"
if (!(Test-Path $LocalStatePath)) {
    Write-UserLog "Local State nebol najdeny." "Error"
    exit 1
}

# Nacitaj a desifruj AES kluc cez DPAPI (vyzaduje user kontext)
$AesKey = $null
try {
    $LSJson      = Get-Content $LocalStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $EncKeyB64   = $LSJson.os_crypt.encrypted_key
    $EncKeyBytes = [Convert]::FromBase64String($EncKeyB64)
    # Odstran 5-bajtovy ASCII prefix "DPAPI"
    $EncKeyBytes = $EncKeyBytes[5..($EncKeyBytes.Length - 1)]
    $AesKey      = [System.Security.Cryptography.ProtectedData]::Unprotect(
        $EncKeyBytes, $null,
        [System.Security.Cryptography.DataProtectionScope]::CurrentUser
    )
    Write-UserLog "AES kluc uspesne desifrovaný cez DPAPI."
}
catch {
    Write-UserLog "DPAPI desifrovanie zlyhalo: $($_.Exception.Message)" "Error"
    exit 1
}

# Nacitaj SQLite driver
if (!(Test-Path $SQLiteDll)) {
    Write-UserLog "PSSQLite DLL nenajdena ($SQLiteDll). Nainstaluj: Install-Module PSSQLite" "Error"
    exit 1
}
try {
    Add-Type -Path $SQLiteDll -ErrorAction Stop
}
catch {
    Write-UserLog "Nepodarilo sa nacitat SQLite DLL: $($_.Exception.Message)" "Error"
    exit 1
}

# Funkcia na desifrovanie hesla (AES-GCM, Chrome v10 format)
function Decrypt-Password {
    param([byte[]]$Encrypted, [byte[]]$Key)
    try {
        if ($Encrypted.Length -lt 31) { return "" }
        $Nonce  = $Encrypted[3..14]
        $Tag    = $Encrypted[($Encrypted.Length - 16)..($Encrypted.Length - 1)]
        $Cipher = $Encrypted[15..($Encrypted.Length - 17)]
        $Aes    = [System.Security.Cryptography.AesGcm]::new($Key)
        $Plain  = New-Object byte[] $Cipher.Length
        $Aes.Decrypt($Nonce, $Cipher, $Tag, $Plain)
        $Aes.Dispose()
        return [System.Text.Encoding]::UTF8.GetString($Plain)
    }
    catch { return "" }
}

# Spracuj vsetky Chrome profily
$Profiles = Get-ChildItem $ChromeBase -Directory |
    Where-Object { $_.Name -match "^(Default|Profile \d+)$" }

$TotalExported = 0

foreach ($Prof in $Profiles) {
    $LoginDataPath = Join-Path $Prof.FullName "Login Data"
    if (!(Test-Path $LoginDataPath)) { continue }

    # Pracuj s kopiou - Chrome zamyka DB pocas behu
    $TempDb = "$env:TEMP\ChromeLoginTmp_$($Prof.Name).db"
    Copy-Item $LoginDataPath $TempDb -Force

    try {
        $ConnStr = "Data Source=$TempDb;Version=3;Read Only=True;"
        $Conn    = New-Object System.Data.SQLite.SQLiteConnection($ConnStr)
        $Conn.Open()

        $Cmd             = $Conn.CreateCommand()
        $Cmd.CommandText = "SELECT origin_url, username_value, password_value FROM logins WHERE blacklisted_by_user = 0"
        $Reader          = $Cmd.ExecuteReader()

        $Results = @()
        while ($Reader.Read()) {
            $Url     = $Reader["origin_url"]
            $User    = $Reader["username_value"]
            $EncPass = [byte[]]$Reader["password_value"]
            $Pass    = Decrypt-Password -Encrypted $EncPass -Key $AesKey
            if ($Pass -ne "") {
                $Results += [PSCustomObject]@{
                    name     = ""
                    url      = $Url
                    username = $User
                    password = $Pass
                }
            }
        }
        $Reader.Close()
        $Conn.Close()

        if ($Results.Count -gt 0) {
            $OutDir = Join-Path $BackupRoot "$env:USERNAME\$($Prof.Name)"
            if (!(Test-Path $OutDir)) { New-Item $OutDir -ItemType Directory -Force | Out-Null }
            $OutFile = Join-Path $OutDir "Passwords.csv"
            # Hlavicka name,url,username,password - kompatibilna s Edge aj Firefox importom
            $Results | Export-Csv -Path $OutFile -NoTypeInformation -Encoding UTF8
            Write-UserLog "Profil $($Prof.Name): $($Results.Count) hesiel exportovanych -> $OutFile"
            $TotalExported += $Results.Count
        }
        else {
            Write-UserLog "Profil $($Prof.Name): ziadne hesla nenajdene."
        }
    }
    catch {
        Write-UserLog "Chyba pri spracovani profilu $($Prof.Name): $($_.Exception.Message)" "Warning"
    }
    finally {
        Remove-Item $TempDb -Force -ErrorAction SilentlyContinue
    }
}

Write-UserLog "Celkovo exportovanych $TotalExported hesiel."
Write-UserLog "UPOZORNENIE: CSV zmazat ihned po importe do Edge/Firefox!" "Warning"
'@

$UserScriptContent | Out-File $TempScript -Encoding UTF8 -Force
Write-Log "Docasny skript pripraveny: $TempScript"

# ---------------------------------------------------------------------------
# KROK 5: Spusti docasny skript ako prihlaseny uzivatel cez ScheduledTask
# ---------------------------------------------------------------------------
Write-Log "Registrujem ScheduledTask v kontexte uzivatela $LoggedUser."

$StatusFile = "$env:ProgramData\TaurisIT\ChromePwdBackup_status.txt"
Remove-Item $StatusFile -Force -ErrorAction SilentlyContinue

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

$Action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$TempScript`""
$Principal = New-ScheduledTaskPrincipal -UserId $LoggedUser -LogonType Interactive -RunLevel Highest
$Settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

Register-ScheduledTask -TaskName $TaskName -Action $Action `
    -Principal $Principal -Settings $Settings -Force | Out-Null

Start-ScheduledTask -TaskName $TaskName
Write-Log "ScheduledTask spustena. Cakam na dokoncenie (max 120s)."

$Timeout = 120
$Elapsed = 0
do {
    Start-Sleep -Seconds 3
    $Elapsed += 3
    $TaskState = (Get-ScheduledTask -TaskName $TaskName).State
} while ($TaskState -eq "Running" -and $Elapsed -lt $Timeout)

if ($TaskState -ne "Ready") {
    Write-Log "ScheduledTask nedobehla v limite ($Elapsed s), stav: $TaskState" "Warning"
}
else {
    Write-Log "ScheduledTask dokoncena po $Elapsed sekundach."
}

# ---------------------------------------------------------------------------
# KROK 6: Prelinkuj vystup user skriptu do hlavneho logu cez LogHelper
# ---------------------------------------------------------------------------
if (Test-Path $StatusFile) {
    Write-Log "--- Zacatek vystupu user skriptu ---"
    Get-Content $StatusFile | ForEach-Object {
        # Mapuj prefix zo status suboru na LogHelper Type
        $MsgType = "Information"
        if ($_ -match "\[Warning\]") { $MsgType = "Warning" }
        if ($_ -match "\[Error\]") { $MsgType = "Error" }
        Write-Log $_ $MsgType
    }
    Write-Log "--- Koniec vystupu user skriptu ---"
}
else {
    Write-Log "Status subor nebol najdeny - user skript nemusel prebehnut." "Warning"
}

# ---------------------------------------------------------------------------
# KROK 7: Cistenie
# ---------------------------------------------------------------------------
Write-Log "Cistim docasne subory a ScheduledTask."
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
Remove-Item $TempScript -Force -ErrorAction SilentlyContinue
Remove-Item $StatusFile -Force -ErrorAction SilentlyContinue

Write-Log "Skript dokonceny. Zaloha: $BackupRoot\$UserName"
exit 0