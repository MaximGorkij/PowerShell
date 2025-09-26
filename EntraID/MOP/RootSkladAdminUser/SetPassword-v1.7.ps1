<#
.SYNOPSIS
    MOP Password Management Script v1.7-C (certifikatom sifrovane hesla)

.DESCRIPTION
    Root & Admin hesla su ulozene ako AES-sifrovany obsah, kde AES kľúč je zašifrovaný s verejnym kľúčom X.509 certifikátu.
    Skript dekryptyje pomocou privátneho kľúča certifikátu (musí byt nainstalovany na cielovom stroji) a nastaví heslá.
    Sklad heslo je generovane lokalne ako "TaurisXXXX" z nazvu PC (MOPXXXX).
    Zachovava LogHelper, nastavenie password policy a vytvaranie scheduled task.

USAGE NOTES
    - Nasad certifikat (s private key) do LocalMachine\My store na vsetky stroje.
    - V skripte nastav $EncryptionCertThumbprint a umiestnenia sifrovanych suborov.
#>

# === GLOBALNE NASTAVENIA ===
$ScriptFolder = "C:\TaurisIT\skript"
$LogFolder = "C:\TaurisIT\Log"
$BackupFolder = "C:\TaurisIT\Backup"
$EventLogName = "IntuneAppInstall"
$EventSource = "MOP Password Change"
$ScriptFileName = "SetPasswords_v1.7-C.ps1"
$ScriptPath = Join-Path $ScriptFolder $ScriptFileName
$ComputerName = $env:COMPUTERNAME

# Thumbprint certifikatu, ktory ma privatny kluc (musis upravit)
$EncryptionCertThumbprint = "PUT_CERT_THUMBPRINT_HERE"  # => napr. "AB12CD34EF..."

# Centralna konfiguracia
$UserConfig = @{
    root  = @{
        UserName      = "root"
        Display       = "ROOT"
        EncryptedFile = Join-Path $ScriptFolder "RootPwd.enc.json"
        LogFile       = Join-Path $LogFolder "PasswordRoot.log"
        EnsureAdmin   = $true
    }
    admin = @{
        UserName      = "admin"
        Display       = "ADMIN"
        EncryptedFile = Join-Path $ScriptFolder "AdminPwd.enc.json"
        LogFile       = Join-Path $LogFolder "PasswordAdmin.log"
        EnsureAdmin   = $true
    }
    sklad = @{
        UserName      = "sklad"
        Display       = "SKLAD"
        EncryptedFile = $null
        LogFile       = Join-Path $LogFolder "PasswordSklad.log"
        EnsureAdmin   = $false
    }
}

# Scheduled Task config
$TaskConfig = @{
    StartupTaskName = "MOP_PasswordCheck_Startup"
    DailyTaskName   = "MOP_PasswordCheck_Daily"
    DailyTime       = "22:30"
}

# === IMPORT LOGHELPER MODULU (ak dostupny) ===
try { Import-Module LogHelper -ErrorAction Stop; $Global:LogHelperAvailable = $true }
catch { Write-Warning "LogHelper modul nie je dostupny. Pouzije sa fallback logovanie."; $Global:LogHelperAvailable = $false }

# === HELPER FUNKCIE ===

function Write-SecureLog {
    param([string]$Message, [string]$Type = "Information", [string]$LogFile = (Join-Path $LogFolder "PasswordRoot.log"))
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] [$Type] $Message"
    try {
        $dir = Split-Path $LogFile -Parent
        if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
        Add-Content -Path $LogFile -Value $entry -Encoding UTF8 -ErrorAction Stop
    }
    catch { Write-Warning "Nepodarilo sa zapisat do log suboru  $_" }
    if ($Global:LogHelperAvailable) {
        try { Write-CustomLog -Message $Message -Type $Type -EventSource $EventSource -EventLogName $EventLogName -LogFileName $LogFile -ErrorAction Stop } catch {}
    }
    try {
        if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) { New-EventLog -LogName $EventLogName -Source $EventSource -ErrorAction SilentlyContinue }
        $entryType = switch ($Type) { "Error" { [System.Diagnostics.EventLogEntryType]::Error } "Warning" { [System.Diagnostics.EventLogEntryType]::Warning } default { [System.Diagnostics.EventLogEntryType]::Information } }
        Write-EventLog -LogName $EventLogName -Source $EventSource -EntryType $entryType -EventId 1000 -Message $Message -ErrorAction SilentlyContinue
    }
    catch {}
}

function Test-AdminRights {
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Output "ERROR: Skript musi byt spusteny ako Administrator."
        Write-SecureLog -Message "Skript spusteny bez admin prav" -Type "Error" -LogFile (Join-Path $LogFolder "PasswordRoot.log")
        exit 1
    }
}

function Find-CertificateByThumbprint {
    param([string]$Thumbprint)
    if ([string]::IsNullOrWhiteSpace($Thumbprint)) { throw "Thumbprint nie je nastaveny." }
    $tp = $Thumbprint -replace '\s', ''
    # Najskor LocalMachine\My, potom CurrentUser\My
    $stores = @(
        @{StoreLocation = "LocalMachine"; StoreName = "My" },
        @{StoreLocation = "CurrentUser"; StoreName = "My" }
    )
    foreach ($s in $stores) {
        try {
            $store = New-Object System.Security.Cryptography.X509Certificates.X509Store($s.StoreName, [System.Security.Cryptography.X509Certificates.StoreLocation]::$($s.StoreLocation))
            $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly)
            $certs = $store.Certificates | Where-Object { ($_.Thumbprint -replace '\s', '').ToUpper() -eq $tp.ToUpper() }
            if ($certs.Count -gt 0) {
                $c = $certs[0]
                $store.Close()
                return $c
            }
            $store.Close()
        }
        catch { }
    }
    return $null
}

function Decrypt-PasswordFile {
    param([string]$Path, [string]$CertThumbprint)
    if (-not (Test-Path $Path)) { throw "Encrypted file not found: $Path" }
    $cert = Find-CertificateByThumbprint -Thumbprint $CertThumbprint
    if (-not $cert) { throw "Certificate with thumbprint $CertThumbprint not found on this machine." }

    # Read JSON
    $json = Get-Content -Path $Path -Raw
    $obj = $null
    try { $obj = ConvertFrom-Json -InputObject $json } catch { throw "Invalid encrypted file format (not JSON): $_" }

    # Expect fields EncryptedKey, IV, CipherText (Base64)
    foreach ($f in @('EncryptedKey', 'IV', 'CipherText')) { if (-not $obj.PSObject.Properties.Name -contains $f) { throw "Missing field $f in encrypted file." } }

    $encryptedKey = [Convert]::FromBase64String($obj.EncryptedKey)
    $iv = [Convert]::FromBase64String($obj.IV)
    $cipher = [Convert]::FromBase64String($obj.CipherText)

    # Use RSA private key from certificate to decrypt AES key
    $rsa = $cert.GetRSAPrivateKey()
    if (-not $rsa) { throw "Certificate does not expose a usable private RSA key." }

    # Choose padding: try OAEP SHA256, fallback to OAEP (SHA1)
    $aesKey = $null
    try {
        $aesKey = $rsa.Decrypt($encryptedKey, [System.Security.Cryptography.RSAEncryptionPadding]::OaepSHA256)
    }
    catch {
        try { $aesKey = $rsa.Decrypt($encryptedKey, [System.Security.Cryptography.RSAEncryptionPadding]::Oaep) } catch { throw "RSA decryption failed: $_" }
    }

    # Decrypt AES (CBC)
    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
    $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
    $aes.Key = $aesKey
    $aes.IV = $iv

    $decryptor = $aes.CreateDecryptor()
    $plainBytes = $decryptor.TransformFinalBlock($cipher, 0, $cipher.Length)
    $plainText = [System.Text.Encoding]::UTF8.GetString($plainBytes)

    # Return SecureString
    $secure = ConvertTo-SecureString -String $plainText -AsPlainText -Force
    return $secure
}

# Admin helper: encrypt plain text with cert public key and save to file (run on admin machine)
function Encrypt-PlainTextToFile {
    param([string]$PlainText, [string]$CertThumbprint, [string]$OutPath)
    $cert = Find-CertificateByThumbprint -Thumbprint $CertThumbprint
    if (-not $cert) { throw "Certificate with thumbprint $CertThumbprint not found." }

    # Generate random AES key & IV
    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.KeySize = 256
    $aes.GenerateKey()
    $aes.GenerateIV()
    $key = $aes.Key
    $iv = $aes.IV

    # Encrypt plaintext with AES (CBC)
    $encryptor = $aes.CreateEncryptor()
    $plainBytes = [System.Text.Encoding]::UTF8.GetBytes($PlainText)
    $cipherBytes = $encryptor.TransformFinalBlock($plainBytes, 0, $plainBytes.Length)

    # Encrypt AES key with cert public RSA key
    $rsaPub = $cert.GetRSAPublicKey()
    if (-not $rsaPub) { throw "Certificate does not expose a usable RSA public key." }

    # Try OAEP SHA256 then fallback
    try {
        $encryptedKey = $rsaPub.Encrypt($key, [System.Security.Cryptography.RSAEncryptionPadding]::OaepSHA256)
    }
    catch {
        $encryptedKey = $rsaPub.Encrypt($key, [System.Security.Cryptography.RSAEncryptionPadding]::Oaep)
    }

    $outObj = @{
        EncryptedKey = [Convert]::ToBase64String($encryptedKey)
        IV           = [Convert]::ToBase64String($iv)
        CipherText   = [Convert]::ToBase64String($cipherBytes)
    }
    $json = $outObj | ConvertTo-Json -Depth 5
    $dir = Split-Path $OutPath -Parent
    if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
    Set-Content -Path $OutPath -Value $json -Encoding UTF8 -Force
    Write-Output "Encrypted file written to $OutPath"
}

# === OTHER FUNCTIONS (policy, set user, tasks) ===

function Set-PasswordPolicy {
    param([string]$LogFile = (Join-Path $LogFolder "PasswordRoot.log"))
    $infPath = Join-Path $env:TEMP ("PasswordPolicy_{0}.inf" -f (Get-Random))
    $dbPath = Join-Path $env:TEMP ("secedit_{0}.sdb" -f (Get-Random))
    $policyContent = @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[System Access]
MinimumPasswordLength = 4
PasswordComplexity = 1
PasswordHistorySize = 1
MaximumPasswordAge = 365
MinimumPasswordAge = 0
ClearTextPassword = 0
LockoutBadCount = 0
RequireLogonToChangePassword = 0
ForceLogoffWhenHourExpire = 0
[Profile Description]
Description=TaurisIT Password Policy Updated
"@
    try {
        if (-not (Test-Path $BackupFolder)) { New-Item -Path $BackupFolder -ItemType Directory -Force | Out-Null }
        $backupPath = Join-Path $BackupFolder ("secedit_backup_{0}.inf" -f (Get-Date -Format 'yyyyMMddHHmmss'))
        secedit /export /cfg $backupPath /quiet 2>$null
        $policyContent | Set-Content -Path $infPath -Encoding Unicode -Force
        $result = secedit /configure /db $dbPath /cfg $infPath /overwrite /quiet 2>&1
        if ($LASTEXITCODE -ne 0) { throw "secedit zlyhalo s kodom $LASTEXITCODE. Vystup: $result" }
        Start-Sleep -Seconds 2
        gpupdate /force /target:computer 2>&1 | Out-Null
        Write-SecureLog -Message "Password policy aplikovana" -Type "Information" -LogFile $LogFile
    }
    catch {
        Write-SecureLog -Message "Chyba pri aplikacii password policy: $_" -Type "Error" -LogFile $LogFile
        throw $_
    }
    finally {
        if (Test-Path $infPath) { Remove-Item $infPath -Force -ErrorAction SilentlyContinue }
        if (Test-Path $dbPath) { Remove-Item $dbPath -Force -ErrorAction SilentlyContinue }
    }
}

function Set-UserPassword {
    param([string]$UserName, [System.Security.SecureString]$SecurePassword, [string]$LogFile, [string]$DisplayName = $null, [bool]$EnsureAdmin = $false)
    if (-not $DisplayName) { $DisplayName = $UserName }
    try {
        $user = Get-LocalUser -Name $UserName -ErrorAction Stop
        if (-not $user.Enabled) { Enable-LocalUser -Name $UserName -ErrorAction Stop; Write-SecureLog -Message "$DisplayName aktivovany" -Type "Information" -LogFile $LogFile }
        $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
        try {
            $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
            if ($plain.Length -lt 4) { throw "Heslo prilis kratke" }
        }
        finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
        Set-LocalUser -Name $UserName -Password $SecurePassword -ErrorAction Stop
        Set-LocalUser -Name $UserName -PasswordNeverExpires $true -ErrorAction Stop
        Write-SecureLog -Message "$DisplayName - Heslo nastavené" -Type "Information" -LogFile $LogFile
        return $true
    }
    catch [Microsoft.PowerShell.Commands.UserNotFoundException] {
        try {
            Write-SecureLog -Message "$DisplayName neexistuje - vytvaram" -Type "Warning" -LogFile $LogFile
            New-LocalUser -Name $UserName -Password $SecurePassword -FullName $DisplayName -Description "MOP System User - $DisplayName" -PasswordNeverExpires -ErrorAction Stop
            if ($EnsureAdmin) { Add-LocalGroupMember -Group "Administrators" -Member $UserName -ErrorAction Stop; Write-SecureLog -Message "$DisplayName pridan do Administrators" -Type "Information" -LogFile $LogFile }
            Write-SecureLog -Message "$DisplayName vytvoreny" -Type "Information" -LogFile $LogFile
            return $true
        }
        catch { Write-SecureLog -Message "Chyba pri vytvarani $DisplayName : $_" -Type "Error" -LogFile $LogFile; return $false }
    }
    catch { Write-SecureLog -Message "Chyba pri nastavovani hesla pre $DisplayName : $_" -Type "Error" -LogFile $LogFile; return $false }
}

function Generate-SkladPasswordFromComputer { param([string]$ComputerName) if ($ComputerName -match '^MOP(\d{4})$') { return "Tauris$($matches[1])" } else { throw "Neplatny format nazvu pocitaca: $ComputerName" } }

function Find-PowerShellExe {
    $candidates = @("C:\Program Files\PowerShell\7\pwsh.exe", "C:\Program Files\PowerShell\pwsh.exe", "$env:ProgramFiles\PowerShell\7\pwsh.exe", "powershell.exe")
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }; return "powershell.exe"
}

function New-GenericScheduledTask {
    param([string]$TaskName, [string]$PowerShellExe, [string]$ScriptFullPath, [string]$TriggerType = "Startup", [string]$Time = "")
    try {
        $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($existing) { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue; Write-SecureLog -Message "Odstraneny existujuci task: $TaskName" -Type "Information" -LogFile (Join-Path $LogFolder "PasswordRoot.log") }
        $arg = "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptFullPath`""
        $action = New-ScheduledTaskAction -Execute $PowerShellExe -Argument $arg
        switch ($TriggerType) { "Startup" { $trigger = New-ScheduledTaskTrigger -AtStartup } "Daily" { if ([string]::IsNullOrEmpty($Time)) { $Time = $TaskConfig.DailyTime }; $trigger = New-ScheduledTaskTrigger -Daily -At $Time } default { throw "Nepodporovany trigger typ: $TriggerType" } }
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest -LogonType ServiceAccount
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -DontStopOnIdleEnd
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -ErrorAction Stop
        $vt = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
        if ($vt.State -eq "Ready") { Write-SecureLog -Message "Task $TaskName vytvoreny a v stave Ready" -Type "Information" -LogFile (Join-Path $LogFolder "PasswordRoot.log"); return $true } else { Write-SecureLog -Message "Task $TaskName vytvoreny, stav: $($vt.State)" -Type "Warning" -LogFile (Join-Path $LogFolder "PasswordRoot.log"); return $false }
    }
    catch { Write-SecureLog -Message "Chyba pri vytvarani tasku $TaskName : $_" -Type "Error" -LogFile (Join-Path $LogFolder "PasswordRoot.log"); return $false }
}

# === HLAVNY BEH SKRIPTU ===

Write-Output "=== MOP Password Management Script v1.7-C (cert) ==="
Write-Output "INFO: Spustam skript..."

# Ensure folders
foreach ($d in @($ScriptFolder, $LogFolder, $BackupFolder)) { if (-not (Test-Path $d)) { New-Item -Path $d -ItemType Directory -Force | Out-Null; Write-Output "INFO: Vytvoreny priecinok: $d" } }

# Admin rights
Test-AdminRights

# Verify cert present early
try {
    $cert = Find-CertificateByThumbprint -Thumbprint $EncryptionCertThumbprint
    if (-not $cert) { throw "Certificate with thumbprint $EncryptionCertThumbprint not found. Install the cert (with private key) to LocalMachine\My." }
    Write-SecureLog -Message "Encryption certificate found: $($cert.Subject) [$($cert.Thumbprint)]" -Type "Information" -LogFile (Join-Path $LogFolder "PasswordRoot.log")
}
catch {
    Write-SecureLog -Message "Kriticka chyba: $_" -Type "Error" -LogFile (Join-Path $LogFolder "PasswordRoot.log")
    Write-Output "ERROR: Certifikát s privátnym kľúčom nie je nainštalovaný. Skontroluj Thumbprint."
    exit 1
}

# Apply password policy
try { Set-PasswordPolicy -LogFile (Join-Path $LogFolder "PasswordRoot.log") } catch { Write-SecureLog -Message "Warning: Password policy nebyla plne aplikovana: $_" -Type "Warning" -LogFile (Join-Path $LogFolder "PasswordRoot.log") }

# Load & decrypt root/admin
$LoadedPasswords = @{}

foreach ($k in @('root', 'admin')) {
    $cfg = $UserConfig[$k]
    if (-not $cfg.EncryptedFile) { Write-SecureLog -Message "Encrypted file not configured for $k" -Type "Error" -LogFile $cfg.LogFile; Write-Output "ERROR: Encrypted file not configured for $k"; exit 1 }
    try {
        $secure = Decrypt-PasswordFile -Path $cfg.EncryptedFile -CertThumbprint $EncryptionCertThumbprint
        $LoadedPasswords[$k] = $secure
    }
    catch {
        Write-SecureLog -Message "Chyba pri dekriptovani pre $k : $_" -Type "Error" -LogFile $cfg.LogFile
        Write-Output "ERROR: Chyba pri dekriptovani pre $k : $_"
        exit 1
    }
}

# Generate SKLAD password locally
try {
    $skladPlain = Generate-SkladPasswordFromComputer -ComputerName $ComputerName
    $LoadedPasswords['sklad'] = ConvertTo-SecureString $skladPlain -AsPlainText -Force
    Write-SecureLog -Message "SKLAD heslo vygenerovane pre $ComputerName" -Type "Information" -LogFile $UserConfig.sklad.LogFile
}
catch {
    Write-SecureLog -Message "Chyba pri generovani SKLAD hesla: $_" -Type "Error" -LogFile $UserConfig.sklad.LogFile
    Write-Output "ERROR: Nepodarilo sa vygenerovat SKLAD heslo: $_"; exit 1
}

# Apply passwords
$results = @()
foreach ($k in $UserConfig.Keys) {
    $cfg = $UserConfig[$k]
    if (-not $LoadedPasswords.ContainsKey($k)) { Write-SecureLog -Message "No password loaded for $k" -Type "Error" -LogFile $cfg.LogFile; $results += $false; continue }
    $ok = Set-UserPassword -UserName $cfg.UserName -SecurePassword $LoadedPasswords[$k] -LogFile $cfg.LogFile -DisplayName $cfg.Display -EnsureAdmin $cfg.EnsureAdmin
    $results += $ok
}

# Final report
$successCount = ($results | Where-Object { $_ -eq $true }).Count
$totalCount = $results.Count
Write-Output "INFO: Hesla nastavene: $successCount/$totalCount"
if ($successCount -eq $totalCount) { Write-SecureLog -Message "Vsetky hesla uspesne nastavene ($successCount/$totalCount)" -Type "Information" -LogFile (Join-Path $LogFolder "PasswordRoot.log") }
else { Write-SecureLog -Message "Nie vsetky hesla boli nastavene ($successCount/$totalCount)" -Type "Warning" -LogFile (Join-Path $LogFolder "PasswordRoot.log") }

# Create scheduled tasks
try {
    $pwshExe = Find-PowerShellExe
    $scriptFull = $ScriptPath
    if (-not (Test-Path $scriptFull)) {
        $currentPath = $MyInvocation.MyCommand.Definition
        if ($currentPath -and (Test-Path $currentPath)) { try { Copy-Item -Path $currentPath -Destination $scriptFull -Force -ErrorAction Stop; Write-SecureLog -Message "Skript skopirovany do $scriptFull" -LogFile (Join-Path $LogFolder "PasswordRoot.log") } catch { Write-SecureLog -Message "Nepodarilo sa skopirovat skript do $scriptFull $_" -Type "Warning" -LogFile (Join-Path $LogFolder "PasswordRoot.log") } }
    }
    New-GenericScheduledTask -TaskName $TaskConfig.StartupTaskName -PowerShellExe $pwshExe -ScriptFullPath $scriptFull -TriggerType "Startup" | Out-Null
    New-GenericScheduledTask -TaskName $TaskConfig.DailyTaskName -PowerShellExe $pwshExe -ScriptFullPath $scriptFull -TriggerType "Daily" -Time $TaskConfig.DailyTime | Out-Null
}
catch { Write-SecureLog -Message "Chyba pri vytvarani scheduled tasks: $_" -Type "Error" -LogFile (Join-Path $LogFolder "PasswordRoot.log") }

# Cleanup plaintext
try { if ($skladPlain) { Remove-Variable -Name skladPlain -ErrorAction SilentlyContinue }; [System.GC]::Collect() } catch {}

Write-Output "INFO: Skript dokonceny."
Write-SecureLog -Message "Skript v1.7-C dokonceny" -Type "Information" -LogFile (Join-Path $LogFolder "PasswordRoot.log")
