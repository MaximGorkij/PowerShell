<#
.SYNOPSIS
    Hromadné premenovanie počítačov v Active Directory podľa OU a typu zariadenia.
.DESCRIPTION
    Skript premenúva počítače podľa OU a pôvodného názvu na nový formát:
    - Notebooky: NTB + dve písmená z OU + 4-miestne číslo
    - Desktopy: DSK + dve písmená z OU + 4-miestne číslo  
    - Ostatné: COM + dve písmená z OU + 4-miestne číslo
.PARAMETER WhatIf
    Simulácia zmien bez skutočného vykonania.
.AUTHOR
    Upravené podľa LogHelper modulu
.CREATED
    2025-10-03
.VERSION
    3.0.0
.NOTES
    - Vyžaduje Active Directory modul
    - Vyžaduje administrátorské oprávnenia
    - Backup sa ukladá do: C:\TaurisIT\Backup\AD_Rename
    - Logy sa ukladajú do: C:\TaurisIT\Log
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$WhatIf
)

#region LogHelper Module
function Write-CustomLog {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [Parameter(Mandatory = $true)]
        [string]$EventSource,
        [string]$EventLogName = "IntuneScript",
        [Parameter(Mandatory = $true)]
        [string]$LogFileName,
        [ValidateSet("Information", "Warning", "Error")]
        [string]$Type = "Information"
    )
    
    $LogDirectory = "C:\TaurisIT\Log"
    if (-not (Test-Path $LogDirectory)) {
        New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
    }
    
    # Cistenie starych logov (>30 dni)
    try {
        Get-ChildItem -Path $LogDirectory -Filter "*.txt" -ErrorAction SilentlyContinue | Where-Object {
            $_.LastWriteTime -lt (Get-Date).AddDays(-30)
        } | Remove-Item -Force -ErrorAction SilentlyContinue
    }
    catch {
        # Ignoruj chyby pri mazani starych logov
    }
    
    $LogFilePath = Join-Path $LogDirectory $LogFileName
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$Timestamp [$Type] - $Message" | Out-File -FilePath $LogFilePath -Append -Encoding UTF8
    
    # Vytvorenie Event Source, ak neexistuje
    if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
        try {
            New-EventLog -LogName $EventLogName -Source $EventSource -ErrorAction SilentlyContinue
        }
        catch {
            # Ak sa nepodari vytvorit event source, iba loguj do suboru
            "$Timestamp - WARNING: Cannot create Event Source '$EventSource'. $_" | Out-File -FilePath $LogFilePath -Append -Encoding UTF8
        }
    }
    
    # Zapis do Event Logu
    try {
        $EventId = switch ($Type) {
            "Information" { 1000 }
            "Warning" { 2000 }
            "Error" { 3000 }
            default { 9999 }
        }
        Write-EventLog -LogName $EventLogName -Source $EventSource -EntryType $Type -EventId $EventId -Message $Message -ErrorAction SilentlyContinue
    }
    catch {
        # Ak sa nepodari zapisat do event logu, iba loguj do suboru
        "$Timestamp - WARNING: Cannot write to Event Log. $_" | Out-File -FilePath $LogFilePath -Append -Encoding UTF8
    }
}
#endregion

#region Inicializacia
$ErrorActionPreference = "Stop"
$ScriptName = "AD-ComputerRename"
$LogFileName = "AD_Rename_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$EventSource = "AD_Rename_Script"
$BackupDirectory = "C:\TaurisIT\Backup\AD_Rename"

Write-CustomLog -Message "========== SPUSTENIE SKRIPTU ==========" -EventSource $EventSource -LogFileName $LogFileName -Type Information
Write-CustomLog -Message "Rezim: $(if($WhatIf){'SIMULACIA (WhatIf)'}else{'PRODUKCNY'})" -EventSource $EventSource -LogFileName $LogFileName -Type Information

# Kontrola AD modulu
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    $errorMsg = "CRITICAL: Active Directory modul nie je nainstalovany!"
    Write-CustomLog -Message $errorMsg -EventSource $EventSource -LogFileName $LogFileName -Type Error
    Write-Host "ERROR: $errorMsg" -ForegroundColor Red
    exit 1
}

try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-CustomLog -Message "Active Directory modul uspesne nacitany" -EventSource $EventSource -LogFileName $LogFileName -Type Information
}
catch {
    $errorMsg = "CRITICAL: Chyba pri nacitani Active Directory modulu: $($_.Exception.Message)"
    Write-CustomLog -Message $errorMsg -EventSource $EventSource -LogFileName $LogFileName -Type Error
    Write-Host "ERROR: $errorMsg" -ForegroundColor Red
    exit 1
}
#endregion

#region Backup Funkcia
function New-ADComputerBackup {
    param($BackupPath)
    
    try {
        if (-not (Test-Path $BackupPath)) {
            New-Item -Path $BackupPath -ItemType Directory -Force | Out-Null
        }
        
        $BackupFile = Join-Path $BackupPath "AD_Computers_Backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
        
        Write-Host "`n[BACKUP] Vytvaranie zalohy do: $BackupFile" -ForegroundColor Cyan
        Write-CustomLog -Message "Zacinam vytvaranie backupu: $BackupFile" -EventSource $EventSource -LogFileName $LogFileName -Type Information
        
        $allComputers = Get-ADComputer -Filter * -Properties Name, DistinguishedName, Description, Created, Modified, Enabled, LastLogonDate
        $allComputers | Select-Object Name, DistinguishedName, Description, Enabled, Created, Modified, LastLogonDate | Export-Csv -Path $BackupFile -NoTypeInformation -Encoding UTF8
        
        Write-Host "[BACKUP] OK Zaloha vytvorena: $($allComputers.Count) pocitacov" -ForegroundColor Green
        Write-CustomLog -Message "Backup uspesne vytvoreny: $($allComputers.Count) pocitacov do $BackupFile" -EventSource $EventSource -LogFileName $LogFileName -Type Information
        
        # Cistenie starych backupov (>90 dni)
        try {
            $oldBackups = Get-ChildItem -Path $BackupPath -Filter "*.csv" -ErrorAction SilentlyContinue | Where-Object {
                $_.LastWriteTime -lt (Get-Date).AddDays(-90)
            }
            
            if ($oldBackups) {
                $oldBackups | Remove-Item -Force
                Write-CustomLog -Message "Odstranene stare backupy: $($oldBackups.Count)" -EventSource $EventSource -LogFileName $LogFileName -Type Information
            }
        }
        catch {
            Write-CustomLog -Message "Chyba pri cisteni starych backupov: $($_.Exception.Message)" -EventSource $EventSource -LogFileName $LogFileName -Type Warning
        }
        
        return $BackupFile
    }
    catch {
        $errorMsg = "Chyba pri vytvarani backupu: $($_.Exception.Message)"
        Write-Host "[BACKUP] ERROR: $errorMsg" -ForegroundColor Red
        Write-CustomLog -Message "CHYBA pri backupe: $errorMsg" -EventSource $EventSource -LogFileName $LogFileName -Type Error
        throw
    }
}
#endregion

#region Transformacne pravidla pre OU
$transformationRules = @{
    "OU=Workstations,OU=UBYKA,DC=tauris,DC=local"    = "UB"
    "OU=Workstations,OU=NITRIA,DC=tauris,DC=local"   = "NI" 
    "OU=Workstations,OU=HQ TG,DC=tauris,DC=local"    = "HQ"
    "OU=Workstations,OU=CASSOVIA,DC=tauris,DC=local" = "CA"
    "OU=Workstations,OU=TAURIS,DC=tauris,DC=local"   = "TA"
    "OU=Workstations,OU=RYBA,DC=tauris,DC=local"     = "RY"
}

Write-CustomLog -Message "Nacitane transformacne pravidla: $($transformationRules.Count) OU" -EventSource $EventSource -LogFileName $LogFileName -Type Information

# Kontrola ci OU existuju
foreach ($ou in $transformationRules.Keys) {
    try {
        $testOU = Get-ADOrganizationalUnit -Identity $ou -ErrorAction Stop
        Write-CustomLog -Message "OU kontrola: $ou - OK" -EventSource $EventSource -LogFileName $LogFileName -Type Information
    }
    catch {
        Write-CustomLog -Message "VAROVANIE: OU '$ou' neexistuje alebo nie je pristupna!" -EventSource $EventSource -LogFileName $LogFileName -Type Warning
    }
}
#endregion

#region Globalne ciselnanie
$globalCounterFile = "C:\TaurisIT\Backup\AD_Rename\global_counter.txt"

function Get-GlobalSequenceNumber {
    try {
        $counterDirectory = Split-Path $globalCounterFile -Parent
        if (-not (Test-Path $counterDirectory)) {
            New-Item -Path $counterDirectory -ItemType Directory -Force | Out-Null
        }
        
        if (Test-Path $globalCounterFile) {
            $currentNumber = [int](Get-Content $globalCounterFile -ErrorAction Stop)
        }
        else {
            $currentNumber = 1
        }
        
        if ($currentNumber -gt 9999) {
            throw "Globalny pocitadlo prekrocilo maximalnu hodnotu 9999"
        }
        
        # Zvysenie a ulozenie
        $newNumber = $currentNumber + 1
        if (-not $WhatIf) {
            $newNumber | Out-File -FilePath $globalCounterFile -Force -Encoding UTF8
        }
        
        return $newNumber.ToString("0000")
    }
    catch {
        Write-CustomLog -Message "Chyba v Get-GlobalSequenceNumber: $($_.Exception.Message)" -EventSource $EventSource -LogFileName $LogFileName -Type Error
        throw
    }
}

function Reset-GlobalCounter {
    param([int]$StartValue = 1)
    
    try {
        $counterDirectory = Split-Path $globalCounterFile -Parent
        if (-not (Test-Path $counterDirectory)) {
            New-Item -Path $counterDirectory -ItemType Directory -Force | Out-Null
        }
        
        $StartValue | Out-File -FilePath $globalCounterFile -Force -Encoding UTF8
        Write-Host "Globalne pocitadlo resetovane na: $StartValue" -ForegroundColor Green
    }
    catch {
        Write-Host "Chyba pri resetovani pocitadla: $($_.Exception.Message)" -ForegroundColor Red
    }
}
#endregion

#region Funkcia na urcenie typu zariadenia
function Get-DeviceType {
    param([string]$ComputerName)
    
    # Notebooky - zaciatok NB- alebo NBR
    if ($ComputerName -match "^(NB-|NBR)") {
        return "NTB"
    }
    # Desktopy - zaciatok PCR alebo PC-
    elseif ($ComputerName -match "^(PCR|PC-)") {
        return "DSK"
    }
    # Vsetky ostatne
    else {
        return "COM"
    }
}
#endregion

#region Hlavny proces
try {
    # Vytvorenie backupu pred zmenami
    if (-not $WhatIf) {
        $backupFile = New-ADComputerBackup -BackupPath $BackupDirectory
    }
    else {
        Write-Host "`n[WHATIF] Backup sa nevytvara v simulacnom rezime" -ForegroundColor Yellow
        Write-CustomLog -Message "WhatIf rezim: Backup preskoceny" -EventSource $EventSource -LogFileName $LogFileName -Type Warning
    }
    
    # Moznost resetu globalneho pocitadla
    if (-not $WhatIf) {
        $resetChoice = Read-Host "`nChcete resetovat globalne pocitadlo? (A/N) [N]"
        if ($resetChoice -eq "A" -or $resetChoice -eq "a") {
            $startValue = Read-Host "Zadajte zaciatocnu hodnotu [1]"
            if (-not $startValue) { $startValue = 1 }
            Reset-GlobalCounter -StartValue $startValue
        }
    }
    
    Write-Host "`n" + "="*60 -ForegroundColor Cyan
    Write-Host "   PREMENOVANIE POCITACOV PODLA OU A TYPU" -ForegroundColor Cyan
    Write-Host "="*60 -ForegroundColor Cyan
    Write-Host ""
    
    $totalRenamed = 0
    $totalSkipped = 0
    $totalErrors = 0
    $processedOU = 0
    
    foreach ($rule in $transformationRules.GetEnumerator()) {
        $OU = $rule.Key
        $siteCode = $rule.Value  # Dve pismena z OU
        
        Write-Host "Spracuvam OU: $OU" -ForegroundColor Green
        Write-Host "Site kod: $siteCode" -ForegroundColor Gray
        Write-CustomLog -Message "Spracuvanie OU: $OU (Site kod: $siteCode)" -EventSource $EventSource -LogFileName $LogFileName -Type Information
        
        try {
            $computers = Get-ADComputer -Filter * -SearchBase $OU -Properties Name, DistinguishedName, Description, Enabled -ErrorAction Stop
            $processedOU++
        }
        catch {
            $errorMsg = "Chyba pri citani OU '$OU': $($_.Exception.Message)"
            Write-Host "ERROR: $errorMsg`n" -ForegroundColor Red
            Write-CustomLog -Message "CHYBA pri citani OU $OU : $errorMsg" -EventSource $EventSource -LogFileName $LogFileName -Type Error
            $totalErrors++
            continue
        }
        
        if ($computers.Count -eq 0) {
            Write-Host "  INFO: Ziadne pocitace v tejto OU`n" -ForegroundColor Yellow
            Write-CustomLog -Message "OU $OU je prazdna" -EventSource $EventSource -LogFileName $LogFileName -Type Warning
            continue
        }
        
        Write-Host "  Pocet pocitacov: $($computers.Count)" -ForegroundColor Gray
        
        foreach ($computer in $computers) {
            $oldName = $computer.Name
            
            # Určenie typu zariadenia
            $deviceType = Get-DeviceType -ComputerName $oldName
            
            # Kontrola ci uz ma novy format
            $newFormatPattern = "^($deviceType)-$siteCode-\d{4}$"
            if ($oldName -match $newFormatPattern) {
                Write-Host "  SKIP: $oldName uz ma spravny format - preskakujem" -ForegroundColor Gray
                Write-CustomLog -Message "Preskoceny $oldName - uz ma spravny format" -EventSource $EventSource -LogFileName $LogFileName -Type Information
                $totalSkipped++
                continue
            }
            
            # Preskocenie vypnutych pocitacov (volitelne)
            if (-not $computer.Enabled) {
                Write-Host "  WARNING: $oldName je disabled - preskakujem" -ForegroundColor DarkYellow
                Write-CustomLog -Message "Preskoceny $oldName - pocitac je disabled" -EventSource $EventSource -LogFileName $LogFileName -Type Warning
                $totalSkipped++
                continue
            }
            
            try {
                # Ziskanie globalneho sekvencneho cisla
                $sequenceNumber = Get-GlobalSequenceNumber
                $newComputerName = "$deviceType-$siteCode-$sequenceNumber"
                
                if ($WhatIf) {
                    Write-Host "  [WHATIF] Premenoval by som: $oldName -> $newComputerName" -ForegroundColor Yellow
                    Write-CustomLog -Message "[WHATIF] $oldName -> $newComputerName" -EventSource $EventSource -LogFileName $LogFileName -Type Information
                    $totalRenamed++
                }
                else {
                    Write-Host "  RENAME: $oldName -> $newComputerName" -ForegroundColor Yellow
                    
                    # Premenovanie pomocou Rename-ADComputer
                    Rename-ADComputer -Identity $computer.DistinguishedName -NewName $newComputerName -ErrorAction Stop
                    
                    # Aktualizacia description
                    $newDescription = if ($computer.Description) {
                        "$($computer.Description) | Premenovany z '$oldName' dna $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
                    }
                    else {
                        "Premenovany z '$oldName' dna $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
                    }
                    
                    Set-ADComputer -Identity $newComputerName -Description $newDescription -ErrorAction Stop
                    
                    Write-Host "  OK: Uspesne premenovany: $newComputerName" -ForegroundColor Green
                    Write-CustomLog -Message "USPECH: $oldName -> $newComputerName" -EventSource $EventSource -LogFileName $LogFileName -Type Information
                    $totalRenamed++
                }
            }
            catch {
                $errorMsg = "Chyba pri premenovavani $oldName : $($_.Exception.Message)"
                Write-Host "  ERROR: $errorMsg" -ForegroundColor Red
                Write-CustomLog -Message "CHYBA pri premenovavani $oldName : $errorMsg" -EventSource $EventSource -LogFileName $LogFileName -Type Error
                $totalErrors++
            }
        }
        
        Write-Host ""
    }
    
    # Zhrnutie
    Write-Host "="*60 -ForegroundColor Cyan
    Write-Host "   ZHRNUTIE" -ForegroundColor Cyan
    Write-Host "="*60 -ForegroundColor Cyan
    Write-Host "Rezim: $(if($WhatIf){'SIMULACIA'}else{'PRODUKCNY'})" -ForegroundColor $(if ($WhatIf) { "Yellow" } else { "Green" })
    Write-Host "Spracovanych OU: $processedOU/$($transformationRules.Count)" -ForegroundColor Cyan
    Write-Host "Premenovanych: $totalRenamed" -ForegroundColor Green
    Write-Host "Preskocenych: $totalSkipped" -ForegroundColor Gray
    Write-Host "Chyby: $totalErrors" -ForegroundColor $(if ($totalErrors -gt 0) { "Red" } else { "Green" })
    
    if (-not $WhatIf -and (Test-Path $globalCounterFile)) {
        $currentGlobalCounter = Get-Content $globalCounterFile
        Write-Host "Aktualne globalne pocitadlo: $currentGlobalCounter" -ForegroundColor Magenta
    }
    
    Write-Host "="*60 -ForegroundColor Cyan
    Write-Host ""
    
    $summaryMessage = "ZHRNUTIE: SpracovanychOU=$processedOU/$($transformationRules.Count), Premenovanych=$totalRenamed, Preskocenych=$totalSkipped, Chyby=$totalErrors, Rezim=$(if($WhatIf){'WhatIf'}else{'Production'})"
    Write-CustomLog -Message $summaryMessage -EventSource $EventSource -LogFileName $LogFileName -Type Information
    
    if (-not $WhatIf -and $backupFile) {
        Write-Host "[INFO] Backup subor: $backupFile" -ForegroundColor Cyan
    }
    
    Write-CustomLog -Message "========== SKRIPT UKONCENY ==========" -EventSource $EventSource -LogFileName $LogFileName -Type Information
    
    # Navratovy kod
    if ($totalErrors -gt 0) {
        exit 1
    }
    else {
        exit 0
    }
}
catch {
    $errorMsg = "KRITICKA CHYBA: $($_.Exception.Message)"
    Write-Host "`nERROR: $errorMsg" -ForegroundColor Red
    Write-CustomLog -Message $errorMsg -EventSource $EventSource -LogFileName $LogFileName -Type Error
    exit 1
}
#endregion