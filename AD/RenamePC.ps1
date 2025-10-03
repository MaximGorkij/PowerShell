<#
.SYNOPSIS
    Hromadné premenovanie počítačov v Active Directory podľa OU.
.DESCRIPTION
    Skript premenúva počítače v špecifikovaných OU podľa definovaných pravidiel.
    Obsahuje WhatIf režim, logovanie, automatický backup a ochranu pred duplicitami.
.PARAMETER WhatIf
    Simulácia zmien bez skutočného vykonania.
.AUTHOR
    Upravené podľa LogHelper modulu
.CREATED
    2025-10-03
.VERSION
    2.0.0
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
    Get-ChildItem -Path $LogDirectory -Filter *.txt | Where-Object {
        $_.LastWriteTime -lt (Get-Date).AddDays(-30)
    } | Remove-Item -Force
    $LogFilePath = Join-Path $LogDirectory $LogFileName
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$Timestamp [$Type] - $Message" | Out-File -FilePath $LogFilePath -Append -Encoding UTF8
    # Vytvorenie Event Source, ak neexistuje
    if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
        try {
            New-EventLog -LogName $EventLogName -Source $EventSource
        }
        catch {
            "$Timestamp - ERROR: Cannot create Event Source '$EventSource'. $_" | Out-File -FilePath $LogFilePath -Append -Encoding UTF8
            return
        }
    }
    # Dynamicke EventId podla typu
    switch ($Type) {
        "Information" { $EventId = 1000 }
        "Warning" { $EventId = 2000 }
        "Error" { $EventId = 3000 }
        default { $EventId = 9999 }
    }
    # Zapis do Event Logu
    try {
        Write-EventLog -LogName $EventLogName -Source $EventSource -EntryType $Type -EventId $EventId -Message $Message
    }
    catch {
        "$Timestamp - ERROR: Cannot write to Event Log. $_" | Out-File -FilePath $LogFilePath -Append -Encoding UTF8
    }
}
#endregion

#region Inicializacia
$ErrorActionPreference = "Stop"
$ScriptName = "AD-ComputerRename"
$LogFileName = "AD_Rename_$(Get-Date -Format 'yyyyMMdd').txt"
$EventSource = "AD_Rename_Script"
$BackupDirectory = "C:\TaurisIT\Backup\AD_Rename"

Write-CustomLog -Message "========== SPUSTENIE SKRIPTU ==========" -EventSource $EventSource -LogFileName $LogFileName -Type Information
Write-CustomLog -Message "Rezim: $(if($WhatIf){'SIMULACIA (WhatIf)'}else{'PRODUKCNY'})" -EventSource $EventSource -LogFileName $LogFileName -Type Information

# Kontrola AD modulu
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-CustomLog -Message "CRITICAL: Active Directory modul nie je nainstalovany!" -EventSource $EventSource -LogFileName $LogFileName -Type Error
    Write-Host "✗ Active Directory modul nie je dostupny. Ukoncujem." -ForegroundColor Red
    exit 1
}

Import-Module ActiveDirectory
Write-CustomLog -Message "Active Directory modul uspesne nacitany" -EventSource $EventSource -LogFileName $LogFileName -Type Information
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
        
        $allComputers = Get-ADComputer -Filter * -Properties Name, DistinguishedName, Description, Created, Modified
        $allComputers | Export-Csv -Path $BackupFile -NoTypeInformation -Encoding UTF8
        
        Write-Host "[BACKUP] ✓ Zaloha vytvorena: $($allComputers.Count) pocitacov" -ForegroundColor Green
        Write-CustomLog -Message "Backup uspesne vytvoreny: $($allComputers.Count) pocitacov do $BackupFile" -EventSource $EventSource -LogFileName $LogFileName -Type Information
        
        # Cistenie starych backupov (>90 dni)
        $oldBackups = Get-ChildItem -Path $BackupPath -Filter "*.csv" | Where-Object {
            $_.LastWriteTime -lt (Get-Date).AddDays(-90)
        }
        
        if ($oldBackups) {
            $oldBackups | Remove-Item -Force
            Write-CustomLog -Message "Odstranene stare backupy: $($oldBackups.Count)" -EventSource $EventSource -LogFileName $LogFileName -Type Information
        }
        
        return $BackupFile
    }
    catch {
        Write-Host "[BACKUP] ✗ Chyba pri vytvarani backupu: $($_.Exception.Message)" -ForegroundColor Red
        Write-CustomLog -Message "CHYBA pri backupe: $($_.Exception.Message)" -EventSource $EventSource -LogFileName $LogFileName -Type Error
        throw
    }
}
#endregion

#region Transformacne pravidla
$transformationRules = @{
    "OU=Predajna,OU=Pocitace,DC=domain,DC=com" = "SALES-PC"
    "OU=Uctaren,OU=Pocitace,DC=domain,DC=com"  = "ACCT-PC"
    "OU=Vyroba,OU=Pocitace,DC=domain,DC=com"   = "PROD-PC"
    "OU=IT,OU=Pocitace,DC=domain,DC=com"       = "IT-PC"
    "OU=Manazers,OU=Pocitace,DC=domain,DC=com" = "MGR-PC"
}

Write-CustomLog -Message "Nacitane transformacne pravidla: $($transformationRules.Count) OU" -EventSource $EventSource -LogFileName $LogFileName -Type Information
#endregion

#region Funkcia na sekvencne cislo
function Get-NextSequenceNumber {
    param($BaseName, $OU)
    
    $existingComputers = Get-ADComputer -Filter "Name -like '$BaseName-*'" -SearchBase $OU
    
    if ($existingComputers.Count -eq 0) {
        return "001"
    }
    
    $usedNumbers = @()
    foreach ($comp in $existingComputers) {
        if ($comp.Name -match "$BaseName-(\d+)$") {
            $usedNumbers += [int]$matches[1]
        }
    }
    
    $usedNumbers = $usedNumbers | Sort-Object
    $nextNumber = 1
    foreach ($num in $usedNumbers) {
        if ($num -eq $nextNumber) {
            $nextNumber++
        }
        else {
            break
        }
    }
    
    return $nextNumber.ToString("000")
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
    
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "   PREMENOVANIE POCITACOV" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    $totalRenamed = 0
    $totalSkipped = 0
    $totalErrors = 0
    
    foreach ($rule in $transformationRules.GetEnumerator()) {
        $OU = $rule.Key
        $baseName = $rule.Value
        
        Write-Host "Spracuvam OU: $OU" -ForegroundColor Green
        Write-Host "Prefix: $baseName`n" -ForegroundColor Gray
        Write-CustomLog -Message "Spracuvanie OU: $OU (Prefix: $baseName)" -EventSource $EventSource -LogFileName $LogFileName -Type Information
        
        try {
            $computers = Get-ADComputer -Filter * -SearchBase $OU -Properties Name, DistinguishedName, Description
        }
        catch {
            Write-Host "✗ Chyba pri citani OU: $($_.Exception.Message)`n" -ForegroundColor Red
            Write-CustomLog -Message "CHYBA pri citani OU $OU : $($_.Exception.Message)" -EventSource $EventSource -LogFileName $LogFileName -Type Error
            $totalErrors++
            continue
        }
        
        if ($computers.Count -eq 0) {
            Write-Host "  Ziadne pocitace v tejto OU`n" -ForegroundColor Yellow
            Write-CustomLog -Message "OU $OU je prazdna" -EventSource $EventSource -LogFileName $LogFileName -Type Warning
            continue
        }
        
        foreach ($computer in $computers) {
            $oldName = $computer.Name
            
            # Preskocenie, ak uz ma spravny format
            if ($oldName -match "^$baseName-\d{3}$") {
                Write-Host "  ⊘ $oldName uz ma spravny format - preskakujem" -ForegroundColor Gray
                $totalSkipped++
                continue
            }
            
            try {
                $sequenceNumber = Get-NextSequenceNumber -BaseName $baseName -OU $OU
                $newComputerName = "$baseName-$sequenceNumber"
                
                if ($WhatIf) {
                    Write-Host "  [WHATIF] Premenoval by som: $oldName -> $newComputerName" -ForegroundColor Yellow
                    Write-CustomLog -Message "[WHATIF] $oldName -> $newComputerName" -EventSource $EventSource -LogFileName $LogFileName -Type Information
                    $totalRenamed++
                }
                else {
                    Write-Host "  → Premenuvam: $oldName -> $newComputerName" -ForegroundColor Yellow
                    
                    Rename-ADComputer -Identity $computer.DistinguishedName -NewName $newComputerName -ErrorAction Stop
                    
                    $newDN = "CN=$newComputerName," + ($computer.DistinguishedName -replace "^CN=[^,]+,", "")
                    Set-ADComputer -Identity $newDN -Description "Premenovany z '$oldName' dna $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ErrorAction Stop
                    
                    Write-Host "  ✓ Uspesne premenovany: $newComputerName" -ForegroundColor Green
                    Write-CustomLog -Message "USPECH: $oldName -> $newComputerName" -EventSource $EventSource -LogFileName $LogFileName -Type Information
                    $totalRenamed++
                }
                
            }
            catch {
                Write-Host "  ✗ Chyba pri premenovavani $oldName : $($_.Exception.Message)" -ForegroundColor Red
                Write-CustomLog -Message "CHYBA pri premenovavani $oldName : $($_.Exception.Message)" -EventSource $EventSource -LogFileName $LogFileName -Type Error
                $totalErrors++
            }
        }
        
        Write-Host ""
    }
    
    # Zhrnutie
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "   ZHRNUTIE" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Rezim: $(if($WhatIf){'SIMULACIA'}else{'PRODUKCNY'})" -ForegroundColor $(if ($WhatIf) { "Yellow" }else { "Green" })
    Write-Host "Premenovanych: $totalRenamed" -ForegroundColor Green
    Write-Host "Preskocenych: $totalSkipped" -ForegroundColor Gray
    Write-Host "Chyby: $totalErrors" -ForegroundColor $(if ($totalErrors -gt 0) { "Red" }else { "Green" })
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    $summaryMessage = "ZHRNUTIE: Premenovanych=$totalRenamed, Preskocenych=$totalSkipped, Chyby=$totalErrors, Rezim=$(if($WhatIf){'WhatIf'}else{'Production'})"
    Write-CustomLog -Message $summaryMessage -EventSource $EventSource -LogFileName $LogFileName -Type Information
    
    if (-not $WhatIf -and $totalErrors -eq 0) {
        Write-Host "[INFO] Backup subor: $backupFile" -ForegroundColor Cyan
    }
    
    Write-CustomLog -Message "========== SKRIPT UKONCENY ==========" -EventSource $EventSource -LogFileName $LogFileName -Type Information
    
}
catch {
    Write-Host "`n✗ KRITICKA CHYBA: $($_.Exception.Message)" -ForegroundColor Red
    Write-CustomLog -Message "KRITICKA CHYBA: $($_.Exception.Message)" -EventSource $EventSource -LogFileName $LogFileName -Type Error
    exit 1
}
#endregion