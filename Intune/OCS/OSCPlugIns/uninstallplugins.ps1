<#
.SYNOPSIS
    Uninstall script pre OCS Inventory Plugins - Intune Package
.DESCRIPTION
    Odstrani PS1 plugin subory eventlogs.ps1, userinstalledapps.ps1 a winusers.ps1
    z cieloveho adresara OCS Inventory Agent.
    V pripade odstranenia suborov pokusi sa restartovat OCS Inventory Service.
.AUTHOR
    Marek Findrik
.CREATED
    2025-10-03
.VERSION
    1.0
.NOTES
    Pouziva sa ako uninstall script pre Win32 App v Intune.
    Skript vracia exit code 0 pri uspesnom odstraneni, inak 1.
#>

# --------------------------------------------------------------------
# Konfiguracia
# --------------------------------------------------------------------
$Config = @{
    TargetPath    = "C:\Program Files\OCS Inventory Agent\Plugins"
    FilesToRemove = @("eventlogs.ps1", "userinstalledapps.ps1", "winusers.ps1")
    ServiceName   = "OCS Inventory Service"
}

# --------------------------------------------------------------------
# Funkcie
# --------------------------------------------------------------------
function Restart-OCSService {
    param(
        [string]$ServiceName
    )
    
    try {
        Write-Host "Kontrola stavu sluzby: $ServiceName" -ForegroundColor Cyan
        $service = Get-Service -Name $ServiceName -ErrorAction Stop
        
        if ($service.Status -eq 'Running') {
            Write-Host "Restartujem sluzbu: $ServiceName" -ForegroundColor Yellow
            Restart-Service -Name $ServiceName -Force -ErrorAction Stop
            
            # Cakaj kym sa sluzba kompletne restartuje
            Start-Sleep -Seconds 5
            $service.Refresh()
            
            if ($service.Status -eq 'Running') {
                Write-Host "Sluzba uspesne restartovana: $ServiceName" -ForegroundColor Green
                return $true
            }
            else {
                Write-Host "Varovanie: Sluzba po restarte nie je spustena: $ServiceName" -ForegroundColor Yellow
                return $false
            }
        }
        else {
            Write-Host "Sluzba nie je spustena, restart nie je potrebny: $ServiceName" -ForegroundColor Gray
            return $true
        }
    }
    catch [Microsoft.PowerShell.Commands.ServiceCommandException] {
        if ($_.Exception.Message -like "*Cannot find any service*") {
            Write-Host "Sluzba nebola najdena: $ServiceName" -ForegroundColor Yellow
            return $null
        }
        else {
            throw
        }
    }
    catch {
        Write-Host "Chyba pri praci so sluzbou $ServiceName : $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# --------------------------------------------------------------------
# Hlavna logika
# --------------------------------------------------------------------
try {
    Write-Host "Spustenie odinstalacie OCS Inventory pluginov..." -ForegroundColor Cyan
    Write-Host "Cielovy adresar: $($Config.TargetPath)" -ForegroundColor Gray
    Write-Host "Subory na odstranenie: $($Config.FilesToRemove -join ', ')" -ForegroundColor Gray
    
    $removedCount = 0
    $removedFiles = @()
    
    foreach ($file in $Config.FilesToRemove) {
        $filePath = Join-Path $Config.TargetPath $file
        if (Test-Path $filePath) {
            try {
                Remove-Item -Path $filePath -Force -ErrorAction Stop
                $removedCount++
                $removedFiles += $file
                Write-Host "USPESNE odstraneny subor: $file" -ForegroundColor Green
            }
            catch {
                Write-Host "CHYBA pri odstranovani suboru $file : $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        else {
            Write-Host "Subor neexistuje (preskoceny): $file" -ForegroundColor Gray
        }
    }
    
    # Restart service ak boli odstranene subory
    if ($removedCount -gt 0) {
        Write-Host "Boli odstranene subory, kontrola sluzby..." -ForegroundColor Yellow
        $serviceResult = Restart-OCSService -ServiceName $Config.ServiceName
        
        if ($serviceResult -eq $true) {
            Write-Host "Sluzba '$($Config.ServiceName)' bola uspesne restartovana" -ForegroundColor Green
        }
        elseif ($serviceResult -eq $false) {
            Write-Host "Nepodarilo sa restartovat sluzbu '$($Config.ServiceName)'" -ForegroundColor Red
        }
        else {
            Write-Host "Sluzba '$($Config.ServiceName)' nebola najdena" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "Neboli odstranene ziadne subory, restart sluzby nie je potrebny" -ForegroundColor Gray
    }
    
    # Finalna sprava
    $completionMessage = @"
Odinstalacia OCS Inventory pluginov dokoncena.
Odstranene subory: $removedCount z $($Config.FilesToRemove.Count)
$($removedFiles -join ', ')
"@
    
    Write-Host $completionMessage -ForegroundColor Cyan
    
    if ($removedCount -eq $Config.FilesToRemove.Count) {
        Write-Host "Odinstalacia USPESNA - Vsetky subory boli odstranene" -ForegroundColor Green
        exit 0
    }
    elseif ($removedCount -gt 0) {
        Write-Host "Odinstalacia CIASTOCNE USPESNA - Nie vsetky subory boli odstranene" -ForegroundColor Yellow
        exit 0
    }
    else {
        Write-Host "Odinstalacia NEUSPESNA - Ziadne subory neboli odstranene" -ForegroundColor Red
        exit 1
    }
}
catch {
    Write-Host "NECAKANA CHYBA pri odinstalacii: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}