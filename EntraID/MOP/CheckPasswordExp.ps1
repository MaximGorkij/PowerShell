<#
.SYNOPSIS
    Detekcia skriptu na kontrolu a zmenu hesla pre root, admin a sklad

.DESCRIPTION
    Overi, ci hesla su take ako by mali byt nastavene

.AUTHOR
    Marek Findrik

.CREATED
    2025-09-04

.VERSION
    1.5 - Opravená detekcia expirácie hesiel

.NOTES
    Skript je urceny pre lokalne Windows konta mimo domeny. Obsahuje kontrolu expiracie hesla a emailove upozornenie cez SMTP bez autentifikacie.
    Oprava: Používa Get-LocalUser PasswordExpires vlastnosť namiesto komplexných ADSI výpočtov.
#>

# Nastavenie
$warningThresholdDays = 7
$usersToCheck = @("sklad", "root")

# Email konfiguracia
$smtpServer = "tauris-sk.mail.protection.outlook.com"
$smtpPort = 25
$from = "servisit@tauris.sk"
$to = "findrik@tauris.sk"
$subject = "Upozornenie na expiraciu hesla"

# Cesty
$scriptBasePath = "C:\TaurisIT\skripty\CheckPasswordExp"
$logBasePath = "C:\TaurisIT\Log\CheckPasswordExp"
$logPath = Join-Path $logBasePath "PasswordCheck.log"

# Overenie existencie adresarov
if (-not (Test-Path $scriptBasePath)) {
    New-Item -Path $scriptBasePath -ItemType Directory -Force | Out-Null
}
if (-not (Test-Path $logBasePath)) {
    New-Item -Path $logBasePath -ItemType Directory -Force | Out-Null
}

# Overenie existencie logovacieho suboru
if (-not (Test-Path $logPath)) {
    New-Item -Path $logPath -ItemType File | Out-Null
}

# Funkcia na zapis do logu
function Write-Log {
    param (
        [string]$Message
    )
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $entry = "$timestamp - $Message"
    Add-Content -Path $logPath -Value $entry
}

# Oddelovac medzi spusteniami
Add-Content -Path $logPath -Value "`n--- Spustenie skriptu: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ---"
Write-Log "Skript sa spusta z cesty: $PSCommandPath"

# Zozbieraj upozornenia
$emailBody = ""

foreach ($userName in $usersToCheck) {
    $user = Get-LocalUser -Name $userName -ErrorAction SilentlyContinue

    if ($null -eq $user) {
        $msg = "Uzivatel '$userName' neexistuje."
        $emailBody += "$msg<br>"
        Write-Log $msg
        continue
    }

    Write-Log "Kontrolujem uzivatela: $userName"
    Write-Log "  PasswordLastSet: $($user.PasswordLastSet)"
    Write-Log "  PasswordExpires: $($user.PasswordExpires)"

    # Zjednodušená kontrola pomocou PasswordExpires vlastnosti
    if ($null -ne $user.PasswordExpires) {
        # Heslo má nastavený dátum expirácie
        $expirationDate = $user.PasswordExpires
        $daysRemaining = ($expirationDate - (Get-Date)).Days

        Write-Log "  Heslo expiruje za $daysRemaining dni ($expirationDate)"

        if ($daysRemaining -le 0) {
            $msg = "Heslo pre uzivatela '$userName' uz expiralo ($expirationDate)!"
            $emailBody += "$msg<br>"
            Write-Log "  UPOZORNENIE: $msg"
        }
        elseif ($daysRemaining -le $warningThresholdDays) {
            $msg = "Heslo pre uzivatela '$userName' vyprsi o $daysRemaining dni (expiruje $expirationDate)."
            $emailBody += "$msg<br>"
            Write-Log "  UPOZORNENIE: $msg"
        }
        else {
            Write-Log "  Heslo je platne este $daysRemaining dni."
        }
    }
    else {
        # PasswordExpires je null - heslo nikdy neexpiruje
        $msg = "Uzivatel '$userName' ma heslo nastavene ako 'nikdy nevyprsi'."
        Write-Log "  $msg"
        # Nepridávame do emailu, lebo to nie je upozornenie
    }
}

# Posli email, ak je co oznamit
if ($emailBody -ne "") {
    try {
        Write-Log "Pripravujem email s upozorneniami..."
        
        $mail = New-Object System.Net.Mail.MailMessage
        $mail.From = $from
        $mail.To.Add($to)
        $mail.Subject = $subject
        $mail.Body = @"
<html>
<head>
    <style>
        body { font-family: Arial, sans-serif; }
        .warning { color: #d9534f; font-weight: bold; }
        .info { color: #5bc0de; }
    </style>
</head>
<body>
    <h3>Upozornenie na expiraciu hesiel</h3>
    <p>Pocitac: <strong>$env:COMPUTERNAME</strong></p>
    <p>Datum kontroly: <strong>$(Get-Date -Format 'dd.MM.yyyy HH:mm:ss')</strong></p>
    <hr>
    <div class="warning">$emailBody</div>
    <hr>
    <p class="info">Tento email bol automaticky vygenerovany skriptom CheckPasswordExp.</p>
</body>
</html>
"@
        $mail.IsBodyHtml = $true

        $smtp = New-Object System.Net.Mail.SmtpClient($smtpServer, $smtpPort)
        $smtp.Send($mail)

        Write-Log "Email bol uspesne odoslany na adresu: $to"
    }
    catch {
        Write-Log "CHYBA pri odosielani emailu: $($_.Exception.Message)"
    }
    finally {
        # Uvolnenie objektov
        if ($mail) { $mail.Dispose() }
        if ($smtp) { $smtp.Dispose() }
    }
}
else {
    Write-Log "Ziadne upozornenia neboli vygenerovane - vsetky hesla su v poriadku."
}

Write-Log "Skript ukonceny."
Add-Content -Path $logPath -Value "--- Koniec spustenia ---`n"