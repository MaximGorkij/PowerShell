#
# .SYNOPSIS
#     Spolocny skript na migraciu dat do Edge/Firefox a odstranenie Chrome.
# .DESCRIPTION
#     0. Skontroluje a zastavi beziacu instanciu Google Chrome.
#     1. Kopiruje Chrome zalozky priamo do Edge profilu (zlucenie).
#     2. Exportuje Chrome zalozky do HTML zalohy (pre Firefox import).
#     3. Exportuje Chrome hesla do CSV zalohy (vyzaduje kontext daneho usera).
#     4. Nastavi registre pre Microsoft Edge.
#     5. Nastavi registre pre Mozilla Firefox.
#     6. Odinstaluje vsetky verzie Google Chrome.
#     7. Nastavi Edge ako default prehliadac (DISM + GPO registry).
# .NOTES
#     Verzia: 5.0
#     Autor: TaurisIT
#     Pozadovane moduly: LogHelper, PSSQLite
#     Logovanie: C:\TaurisIT\Log\FullMigration.txt
#

$ModulePath = "C:\Program Files\WindowsPowerShell\Modules\LogHelper\LogHelper.psm1"
$LogFile = "C:\TaurisIT\Log\FullMigration.txt"
$Source = "MultiBrowserMigration"
$BackupRoot = "C:\TaurisIT\ChromeBackup"

# ---------------------------------------------------------------------------
# Import modulu LogHelper
# ---------------------------------------------------------------------------
if (Test-Path $ModulePath) {
    Import-Module $ModulePath -Force
}
else {
    Write-Host "[ERROR] Modul LogHelper nebol najdeny na ceste $ModulePath" -ForegroundColor Red
    exit 1
}

function Write-LogProgress {
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
# Rekurzivna funkcia pre konverziu Chrome Bookmarks JSON -> HTML
# ---------------------------------------------------------------------------
function Convert-BookmarkNode {
    param($Node, [int]$Indent = 1)
    $Pad = "    " * $Indent
    if ($Node.type -eq "folder") {
        $Script:HtmlLines += "$Pad<DT><H3>$($Node.name)</H3>"
        $Script:HtmlLines += "$Pad<DL><p>"
        foreach ($Child in $Node.children) {
            Convert-BookmarkNode -Node $Child -Indent ($Indent + 1)
        }
        $Script:HtmlLines += "$Pad</DL><p>"
    }
    elseif ($Node.type -eq "url") {
        $Script:HtmlLines += "$Pad<DT><A HREF=`"$($Node.url)`">$($Node.name)</A>"
    }
}

# ---------------------------------------------------------------------------
# Funkcia na AES-GCM desifrovanie Chrome hesla (Windows 10+)
# ---------------------------------------------------------------------------
function Unprotect-ChromePassword {
    param([byte[]]$Encrypted, [byte[]]$AesKey)
    try {
        # Format v10: 3B prefix + 12B nonce + ciphertext + 16B tag
        if ($Encrypted.Length -lt 31) { return "" }
        $Nonce = $Encrypted[3..14]
        $Tag = $Encrypted[($Encrypted.Length - 16)..($Encrypted.Length - 1)]
        $Cipher = $Encrypted[15..($Encrypted.Length - 17)]
        $Aes = [System.Security.Cryptography.AesGcm]::new($AesKey)
        $Plain = New-Object byte[] $Cipher.Length
        $Aes.Decrypt($Nonce, $Cipher, $Tag, $Plain)
        $Aes.Dispose()
        return [System.Text.Encoding]::UTF8.GetString($Plain)
    }
    catch { return "" }
}

Write-LogProgress "Zacinam proces hromadnej migracie a cistenia."
Add-Type -AssemblyName System.Security

$ChromeBase = "$env:LOCALAPPDATA\Google\Chrome\User Data"
$EdgeBase = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"

# ============================================================
# KROK 0: Kontrola a zastavenie beziacej instancie Chrome
# ============================================================
Write-LogProgress "KROK 0: Kontrolujem ci bezi Google Chrome."

$ChromeProcs = Get-Process -Name "chrome" -ErrorAction SilentlyContinue

if ($ChromeProcs) {
    Write-LogProgress "Chrome bezi ($($ChromeProcs.Count) procesov). Pokusam sa ho zastavit." "Warning"

    # Faza 1: Graceful ukoncenie cez hlavne okno
    $ChromeProcs | ForEach-Object { $_.CloseMainWindow() | Out-Null }
    Start-Sleep -Seconds 5

    # Faza 2: Force kill ak graceful nezafungoval
    $ChromeProcs = Get-Process -Name "chrome" -ErrorAction SilentlyContinue
    if ($ChromeProcs) {
        Write-LogProgress "Chrome neodpovedal na CloseMainWindow, pouzivam Stop-Process." "Warning"
        $ChromeProcs | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
    }

    # Faza 3: Finalna kontrola
    $ChromeProcs = Get-Process -Name "chrome" -ErrorAction SilentlyContinue
    if ($ChromeProcs) {
        Write-LogProgress "Chrome sa nepodarilo zastavit. Migracia pokracuje ale DB moze byt zamknuta." "Warning"
    }
    else {
        Write-LogProgress "Chrome bol uspesne zastaveny."
    }
}
else {
    Write-LogProgress "Chrome nebezi, pokracujem."
}

# ============================================================
# KROK 1: Kopirovanie a zlucenie zaloziek Chrome -> Edge
# ============================================================
Write-LogProgress "KROK 1: Kopируjem a zlucujem Chrome zalozky do Edge profilu."

if (Test-Path $ChromeBase) {
    $Profiles = Get-ChildItem $ChromeBase -Directory |
    Where-Object { $_.Name -match "^(Default|Profile \d+)$" }

    foreach ($Prof in $Profiles) {
        $SrcBookmarks = Join-Path $Prof.FullName "Bookmarks"
        if (!(Test-Path $SrcBookmarks)) { continue }

        $EdgeProf = Join-Path $EdgeBase $Prof.Name
        $DstBookmarks = Join-Path $EdgeProf "Bookmarks"

        if (!(Test-Path $EdgeProf)) {
            Write-LogProgress "Edge profil $($Prof.Name) neexistuje, preskakujem." "Warning"
            continue
        }

        try {
            $ChromeData = Get-Content $SrcBookmarks -Raw -Encoding UTF8 | ConvertFrom-Json

            if (Test-Path $DstBookmarks) {
                # Edge uz ma zalozky - zlucime (Chrome bookmark_bar ako subpriecinok)
                $EdgeData = Get-Content $DstBookmarks -Raw -Encoding UTF8 | ConvertFrom-Json
                $NewFolder = [PSCustomObject]@{
                    type     = "folder"
                    name     = "Chrome Import"
                    children = $ChromeData.roots.bookmark_bar.children
                }
                $EdgeData.roots.bookmark_bar.children += $NewFolder
                $EdgeData | ConvertTo-Json -Depth 50 | Out-File $DstBookmarks -Encoding UTF8
                Write-LogProgress "Zalozky zlucene do Edge profilu: $($Prof.Name)"
            }
            else {
                # Edge nema zalozky - priama kopia
                Copy-Item $SrcBookmarks $DstBookmarks -Force
                Write-LogProgress "Zalozky skopirovane do Edge profilu: $($Prof.Name)"
            }
        }
        catch {
            Write-LogProgress "Chyba pri zlucovani zaloziek ($($Prof.Name)): $($_.Exception.Message)" "Warning"
        }
    }
}
else {
    Write-LogProgress "Chrome User Data nebol najdeny, preskakujem KROK 1." "Warning"
}

# ============================================================
# KROK 2: Export zaloziek do HTML zalohy (pre Firefox import)
# ============================================================
Write-LogProgress "KROK 2: Exportujem Chrome zalozky do HTML (zaloha + Firefox import)."

if (Test-Path $ChromeBase) {
    $Profiles = Get-ChildItem $ChromeBase -Directory |
    Where-Object { $_.Name -match "^(Default|Profile \d+)$" }

    foreach ($Prof in $Profiles) {
        $SrcBookmarks = Join-Path $Prof.FullName "Bookmarks"
        if (!(Test-Path $SrcBookmarks)) { continue }

        try {
            $Json = Get-Content $SrcBookmarks -Raw -Encoding UTF8 | ConvertFrom-Json
            $Script:HtmlLines = @()
            $Script:HtmlLines += "<!DOCTYPE NETSCAPE-Bookmark-file-1>"
            $Script:HtmlLines += "<META HTTP-EQUIV='Content-Type' CONTENT='text/html; charset=UTF-8'>"
            $Script:HtmlLines += "<TITLE>Chrome Bookmarks - $($Prof.Name)</TITLE>"
            $Script:HtmlLines += "<H1>Bookmarks</H1>"
            $Script:HtmlLines += "<DL><p>"

            foreach ($Section in @("bookmark_bar", "other", "synced")) {
                $RootNode = $Json.roots.$Section
                if ($RootNode) { Convert-BookmarkNode -Node $RootNode }
            }
            $Script:HtmlLines += "</DL><p>"

            $OutDir = Join-Path $BackupRoot $Prof.Name
            if (!(Test-Path $OutDir)) { New-Item $OutDir -ItemType Directory -Force | Out-Null }
            $OutFile = Join-Path $OutDir "Bookmarks.html"
            $Script:HtmlLines | Out-File $OutFile -Encoding UTF8
            Write-LogProgress "HTML zaloha zaloziek ulozena: $OutFile"
        }
        catch {
            Write-LogProgress "Chyba pri HTML exporte profilu $($Prof.Name): $($_.Exception.Message)" "Warning"
        }
    }
}
else {
    Write-LogProgress "Chrome User Data nebol najdeny, preskakujem KROK 2." "Warning"
}

# ============================================================
# KROK 3: Export hesiel do CSV zalohy
# Poznamka: vyzaduje beh v kontexte daneho usera (nie SYSTEM)
# Po importe do Edge/Firefox CSV okamzite zmazat!
# ============================================================
Write-LogProgress "KROK 3: Exportujem Chrome hesla do CSV (vyzaduje kontext daneho usera)."

$LocalStatePath = Join-Path $ChromeBase "Local State"

if (!(Test-Path $LocalStatePath)) {
    Write-LogProgress "Chrome Local State nebol najdeny, export hesiel sa preskakuje." "Warning"
}
else {
    # Ziskaj AES kluc desifrovanim cez DPAPI
    $AesKey = $null
    try {
        $LocalStateJson = Get-Content $LocalStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $EncKeyB64 = $LocalStateJson.os_crypt.encrypted_key
        $EncKeyBytes = [Convert]::FromBase64String($EncKeyB64)
        # Prvy 5 bajtov je ASCII prefix "DPAPI" - odstranime
        $EncKeyBytes = $EncKeyBytes[5..($EncKeyBytes.Length - 1)]
        $AesKey = [System.Security.Cryptography.ProtectedData]::Unprotect(
            $EncKeyBytes, $null,
            [System.Security.Cryptography.DataProtectionScope]::CurrentUser
        )
        Write-LogProgress "AES kluc uspesne desifrovaný cez DPAPI."
    }
    catch {
        Write-LogProgress "Nepodarilo sa desifrovat AES kluc: $($_.Exception.Message)" "Error"
    }

    if ($AesKey) {
        $SQLiteDll = "C:\Program Files\WindowsPowerShell\Modules\PSSQLite\System.Data.SQLite.dll"
        if (!(Test-Path $SQLiteDll)) {
            Write-LogProgress "PSSQLite DLL nenajdena ($SQLiteDll). Nainstaluj: Install-Module PSSQLite" "Error"
            $AesKey = $null
        }
        else {
            try { Add-Type -Path $SQLiteDll -ErrorAction Stop }
            catch {
                Write-LogProgress "Nepodarilo sa nacitat SQLite driver: $($_.Exception.Message)" "Error"
                $AesKey = $null
            }
        }
    }

    if ($AesKey) {
        $Profiles = Get-ChildItem $ChromeBase -Directory |
        Where-Object { $_.Name -match "^(Default|Profile \d+)$" }

        foreach ($Prof in $Profiles) {
            $LoginDataPath = Join-Path $Prof.FullName "Login Data"
            if (!(Test-Path $LoginDataPath)) { continue }

            # Chrome zamyka DB pocas behu - pracujeme s kopiou
            $TempDb = "$env:TEMP\ChromeLoginData_$($Prof.Name).db"
            Copy-Item $LoginDataPath $TempDb -Force

            try {
                $ConnStr = "Data Source=$TempDb;Version=3;Read Only=True;"
                $Conn = New-Object System.Data.SQLite.SQLiteConnection($ConnStr)
                $Conn.Open()

                $Cmd = $Conn.CreateCommand()
                $Cmd.CommandText = "SELECT origin_url, username_value, password_value FROM logins WHERE blacklisted_by_user = 0"
                $Reader = $Cmd.ExecuteReader()

                $Results = @()
                while ($Reader.Read()) {
                    $Url = $Reader["origin_url"]
                    $User = $Reader["username_value"]
                    $EncPass = [byte[]]$Reader["password_value"]
                    $Pass = Unprotect-ChromePassword -Encrypted $EncPass -AesKey $AesKey
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

                $OutDir = Join-Path $BackupRoot $Prof.Name
                if (!(Test-Path $OutDir)) { New-Item $OutDir -ItemType Directory -Force | Out-Null }
                $OutFile = Join-Path $OutDir "Passwords.csv"
                $Results | Export-Csv -Path $OutFile -NoTypeInformation -Encoding UTF8
                Write-LogProgress "Hesla exportovane ($($Results.Count) zaznamov): $OutFile"
                Write-LogProgress "UPOZORNENIE: CSV zmazat ihned po importe do Edge/Firefox!" "Warning"
            }
            catch {
                Write-LogProgress "Chyba pri exporte hesiel ($($Prof.Name)): $($_.Exception.Message)" "Warning"
            }
            finally {
                Remove-Item $TempDb -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

# ============================================================
# KROK 4: Nastavenie registrov pre Microsoft Edge
# ============================================================
Write-LogProgress "KROK 4: Konfigurujem registre pre Microsoft Edge."

$EdgePath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
if (!(Test-Path $EdgePath)) { New-Item -Path $EdgePath -Force | Out-Null }

$EdgeSettings = @{
    "AutoImportAtFirstRun"   = 1
    "ImportBookmarks"        = 1
    "ImportSavedPasswords"   = 1
    "ImportAutofillFormData" = 1
}

foreach ($EKey in $EdgeSettings.Keys) {
    New-ItemProperty -Path $EdgePath -Name $EKey -Value $EdgeSettings[$EKey] `
        -PropertyType DWord -Force | Out-Null
}
Write-LogProgress "Edge registre nastavene."

# ============================================================
# KROK 5: Nastavenie registrov pre Mozilla Firefox
# ============================================================
Write-LogProgress "KROK 5: Konfigurujem registre pre Mozilla Firefox."

$FFPath = "HKLM:\SOFTWARE\Policies\Mozilla\Firefox"
if (!(Test-Path $FFPath)) { New-Item -Path $FFPath -Force | Out-Null }

try {
    New-ItemProperty -Path $FFPath -Name "ImportSettings" -Value 1 `
        -PropertyType DWord -Force | Out-Null
    Write-LogProgress "Firefox registre nastavene."
}
catch {
    Write-LogProgress "Nepodarilo sa nastavit registre pre Firefox: $($_.Exception.Message)" "Warning"
}

# ============================================================
# KROK 6: Odinstalacia Google Chrome
# ============================================================
Write-LogProgress "KROK 6: Odinstalovavam Google Chrome."

$RegPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

$ChromeFound = $false
foreach ($P in $RegPaths) {
    $Apps = Get-ItemProperty $P -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -like "*Google Chrome*" }

    foreach ($App in $Apps) {
        $ChromeFound = $true
        Write-LogProgress "Odinstalovavam: $($App.DisplayName)" "Warning"

        if ($App.UninstallString -like "*msiexec*") {
            $Proc = Start-Process msiexec.exe `
                -ArgumentList "/x $($App.PSChildName) /qn /norestart" `
                -Wait -PassThru
        }
        else {
            $UStr = $App.UninstallString
            $PathOnly = if ($UStr -match '"([^"]+)"') { $matches[1] } else { $UStr.Split(' ')[0] }
            $Proc = Start-Process $PathOnly `
                -ArgumentList "--uninstall --system-level --force-uninstall" `
                -Wait -PassThru
        }

        if ($Proc.ExitCode -eq 0 -or $Proc.ExitCode -eq 3010) {
            Write-LogProgress "Chrome ($($App.DisplayName)) uspesne odstraneny."
        }
        else {
            Write-LogProgress "Odinstalacia $($App.DisplayName) zlyhala, kod: $($Proc.ExitCode)" "Error"
        }
    }
}

if (!$ChromeFound) { Write-LogProgress "Ziadna instalacia Google Chrome nebola najdena." }

# ============================================================
# KROK 7: Nastavenie Edge ako default prehliadac
# Metoda: DefaultAssociations XML + DISM (funguje system-wide cez Intune/SYSTEM)
# ============================================================
Write-LogProgress "KROK 7: Nastavujem Microsoft Edge ako default prehliadac."

$AssocXmlPath = "C:\TaurisIT\EdgeDefaultAssoc.xml"

$AssocXml = @'
<?xml version="1.0" encoding="UTF-8"?>
<DefaultAssociations>
    <Association Identifier=".htm"   ProgId="MSEdgeHTM" ApplicationName="Microsoft Edge"/>
    <Association Identifier=".html"  ProgId="MSEdgeHTM" ApplicationName="Microsoft Edge"/>
    <Association Identifier=".pdf"   ProgId="MSEdgeHTM" ApplicationName="Microsoft Edge"/>
    <Association Identifier=".svg"   ProgId="MSEdgeHTM" ApplicationName="Microsoft Edge"/>
    <Association Identifier=".webp"  ProgId="MSEdgeHTM" ApplicationName="Microsoft Edge"/>
    <Association Identifier="http"   ProgId="MSEdgeHTM" ApplicationName="Microsoft Edge"/>
    <Association Identifier="https"  ProgId="MSEdgeHTM" ApplicationName="Microsoft Edge"/>
    <Association Identifier="ftp"    ProgId="MSEdgeHTM" ApplicationName="Microsoft Edge"/>
</DefaultAssociations>
'@

try {
    $AssocXml | Out-File $AssocXmlPath -Encoding UTF8 -Force

    # Aplikuj asociacie cez DISM (vyzaduje SYSTEM / elevovane prava)
    $DismProc = Start-Process "dism.exe" `
        -ArgumentList "/Online /Import-DefaultAppAssociations:`"$AssocXmlPath`"" `
        -Wait -PassThru -WindowStyle Hidden

    if ($DismProc.ExitCode -eq 0) {
        Write-LogProgress "DISM asociacie uspesne aplikovane."
    }
    else {
        Write-LogProgress "DISM skoncil s kodom $($DismProc.ExitCode)." "Warning"
    }

    # GPO registry - zabezpeci zachovanie asociacii aj po dalsich prihlaseniach
    $WinSysPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
    if (!(Test-Path $WinSysPath)) { New-Item $WinSysPath -Force | Out-Null }
    New-ItemProperty -Path $WinSysPath -Name "DefaultAssociationsConfiguration" `
        -Value $AssocXmlPath -PropertyType String -Force | Out-Null

    Write-LogProgress "Edge nastaveny ako default prehliadac (DISM + GPO registry)."
}
catch {
    Write-LogProgress "Chyba pri nastaveni default prehliadaca: $($_.Exception.Message)" "Error"
}
finally {
    Remove-Item $AssocXmlPath -Force -ErrorAction SilentlyContinue
}

Write-LogProgress "Vsetky operacie su ukoncene."