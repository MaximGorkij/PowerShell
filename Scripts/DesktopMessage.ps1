<#
================================================================================
        ALCOHOL WARNING SYSTEM - DESKTOP MESSAGE (TAURIS BRANDED)
================================================================================
Version:        1.3 (PRODUCTION)
Date:           2026-01-16
Author:         TaurisIT
Modifikácia:    Zobrazenie na 75% hlavného monitora
================================================================================
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ==============================================================================
# CONFIG
# ==============================================================================
$LogRoot = "C:\TaurisIT\Log\DesktopMessage"
$BrandRoot = "C:\TaurisIT\Branding"
$LogoPath = Join-Path $BrandRoot "tauris-logov2.png"

$AutoCloseTimeoutSec = 300
$BlinkIntervalMs = 500
$SoundPath = "C:\Windows\Media\Alarm01.wav"

# TAURIS BRAND COLORS
$ColorRedPrimary = [System.Drawing.Color]::FromArgb(227, 6, 19)   # #E30613
$ColorRedDark = [System.Drawing.Color]::FromArgb(180, 0, 0)
$ColorWhite = [System.Drawing.Color]::White

$SessionId = [guid]::NewGuid().ToString()

# ==============================================================================
# LOGGING
# ==============================================================================
function Write-Log {
    param([string]$Message)

    if (-not (Test-Path $LogRoot)) {
        New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
    }

    $logFile = Join-Path $LogRoot "AlcoholWarning_$(Get-Date -Format 'yyyy-MM').log"

    if (-not (Test-Path $logFile)) {
        @"
================================================================================
ALCOHOL WARNING SYSTEM - LOG FILE
================================================================================
Format: Date | Computer | User | SessionID | Event
================================================================================
"@ | Add-Content -Path $logFile -Encoding UTF8
    }

    Add-Content -Path $logFile -Encoding UTF8 -Value (
        "{0} | {1} | {2} | {3} | {4}" -f
        (Get-Date -Format "yyyy-MM-dd HH:mm:ss"),
        $env:COMPUTERNAME,
        [System.Security.Principal.WindowsIdentity]::GetCurrent().Name,
        $SessionId,
        $Message
    )
}

Write-Log "SESSION START - WARNING DISPLAYED"

# ==============================================================================
# DETEKCIA HLAVNÉHO MONITORA A VÝPOČET VEĽKOSTI 75%
# ==============================================================================
# Získanie všetkých monitorov
$screens = [System.Windows.Forms.Screen]::AllScreens

# Hľadanie hlavného monitora (Primary)
$primaryScreen = $screens | Where-Object { $_.Primary -eq $true }

if ($null -eq $primaryScreen) {
    $primaryScreen = $screens[0]  # Fallback na prvý monitor
}

$primaryBounds = $primaryScreen.WorkingArea  # Pracovná plocha bez taskbaru

# Výpočet 75% veľkosti
$windowWidth = [math]::Round($primaryBounds.Width * 0.75)
$windowHeight = [math]::Round($primaryBounds.Height * 0.75)

# Výpočet pozície pre vycentrovanie
$windowLeft = $primaryBounds.Left + [math]::Round(($primaryBounds.Width - $windowWidth) / 2)
$windowTop = $primaryBounds.Top + [math]::Round(($primaryBounds.Height - $windowHeight) / 2)

Write-Log "PRIMARY SCREEN: $($primaryScreen.DeviceName), Size: ${windowWidth}x${windowHeight}, Position: ${windowLeft},${windowTop}"

# ==============================================================================
# FORM - NASTAVENIE VEĽKOSTI A POZÍCIE
# ==============================================================================
$form = New-Object System.Windows.Forms.Form
$form.FormBorderStyle = 'FixedDialog'  # Zmenené z 'None' na 'FixedDialog' pre lepšie centrovanie
$form.StartPosition = 'Manual'  # Ručne nastavená pozícia
$form.Bounds = New-Object System.Drawing.Rectangle($windowLeft, $windowTop, $windowWidth, $windowHeight)
$form.BackColor = $ColorRedPrimary
$form.TopMost = $true
$form.KeyPreview = $true
$form.AutoScaleMode = 'None'
$form.MinimizeBox = $false
$form.MaximizeBox = $false
$form.ControlBox = $false  # Skryť tlačidlá na zatvorenie

# ==============================================================================
# LOGO (TOP LEFT)
# ==============================================================================
if (Test-Path $LogoPath) {
    $logoBox = New-Object System.Windows.Forms.PictureBox
    $logoBox.Image = [System.Drawing.Image]::FromFile($LogoPath)
    $logoBox.SizeMode = 'Zoom'
    $logoBox.Size = New-Object System.Drawing.Size(260, 120)
    $logoBox.Location = New-Object System.Drawing.Point(20, 20)
    $logoBox.BackColor = [System.Drawing.Color]::Transparent
    $form.Controls.Add($logoBox)
    Write-Log "LOGO LOADED"
}
else {
    Write-Log "LOGO NOT FOUND - SKIPPED"
}

# ==============================================================================
# MAIN LABEL - UPRAVENÉ PRE 75% OKNO
# ==============================================================================
$label = New-Object System.Windows.Forms.Label
$label.Text = "⚠ UPOZORNENIE ⚠`n`nZAMESTNANEC BOL URČENÝ NA KONTROLU ALKOHOLU`n`nStlačte ENTER alebo kliknite na POTVRDIŤ"
$label.Font = New-Object System.Drawing.Font("Arial", 36, [System.Drawing.FontStyle]::Bold)  # Zmenšené z 42 na 36
$label.ForeColor = $ColorWhite
$label.TextAlign = 'MiddleCenter'
$label.BackColor = [System.Drawing.Color]::Transparent

# Nastavenie veľkosti a pozície nápisu
$label.Location = New-Object System.Drawing.Point(50, 150)
$label.Size = New-Object System.Drawing.Size(($windowWidth - 100), ($windowHeight - 300))
$form.Controls.Add($label)

# ==============================================================================
# BLINK TIMER
# ==============================================================================
$blinkTimer = New-Object System.Windows.Forms.Timer
$blinkTimer.Interval = $BlinkIntervalMs
$blinkTimer.Add_Tick({
        $form.BackColor = if ($form.BackColor -eq $ColorRedPrimary) { $ColorRedDark } else { $ColorRedPrimary }
    })
$blinkTimer.Start()

# ==============================================================================
# SOUND
# ==============================================================================
$player = New-Object System.Media.SoundPlayer
try {
    if (Test-Path $SoundPath) {
        $player.SoundLocation = $SoundPath
        $player.PlayLooping()
    }
    else {
        throw "Sound missing"
    }
}
catch {
    Write-Log "AUDIO FALLBACK - SYSTEM BEEP"
    [System.Media.SystemSounds]::Beep.Play()
}

# ==============================================================================
# CLOSE HANDLER
# ==============================================================================
$CloseForm = {
    Write-Log "SESSION END - CONFIRMED"
    $blinkTimer.Stop()
    $autoCloseTimer.Stop()
    $player.Stop()
    $form.Close()
}

# ==============================================================================
# BUTTON - UPRAVENÉ PRE 75% OKNO
# ==============================================================================
$button = New-Object System.Windows.Forms.Button
$button.Text = "POTVRDIŤ"
$button.Font = New-Object System.Drawing.Font("Arial", 20, [System.Drawing.FontStyle]::Bold)
$button.Size = New-Object System.Drawing.Size(300, 80)
$button.BackColor = $ColorWhite
$button.ForeColor = $ColorRedPrimary
$button.FlatStyle = 'Flat'
$button.Add_Click($CloseForm)

# Nastavenie pozície tlačidla - vycentrované v spodnej časti
$form.Add_Load({
        $button.Location = New-Object System.Drawing.Point(
            ($form.ClientSize.Width / 2 - $button.Width / 2),
            ($form.ClientSize.Height - $button.Height - 40)
        )
        $form.Controls.Add($button)
        $button.BringToFront()
    })

# ==============================================================================
# KEY + FAILSAFE
# ==============================================================================
$form.Add_KeyDown({ if ($_.KeyCode -in @('Enter', 'Return')) { & $CloseForm } })

$autoCloseTimer = New-Object System.Windows.Forms.Timer
$autoCloseTimer.Interval = $AutoCloseTimeoutSec * 1000
$autoCloseTimer.Add_Tick({
        Write-Log "SESSION AUTO CLOSED - TIMEOUT"
        & $CloseForm
    })
$autoCloseTimer.Start()

# ==============================================================================
# OPRAVA VIDITEĽNOSTI - ZABEZPEČENIE PORADIA VRSTIEV
# ==============================================================================
$form.Add_Load({
        # Zabezpečenie, že tlačidlo je v popredí
        $button.BringToFront()
        
        # Zabezpečenie, že logo je viditeľné
        if ($logoBox -ne $null) {
            $logoBox.BringToFront()
        }
    })

# ==============================================================================
# SHOW
# ==============================================================================
$form.Add_Shown({ 
        $form.Activate()
        $form.Focus()
        # Zabezpečenie, že okno je na vrchu
        $form.TopMost = $true
    })
[void]$form.ShowDialog()

# ==============================================================================
# CLEANUP
# ==============================================================================
$blinkTimer.Dispose()
$autoCloseTimer.Dispose()
$player.Dispose()
$form.Dispose()