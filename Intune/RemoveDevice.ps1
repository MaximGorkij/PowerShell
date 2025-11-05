# Skript na odstranenie zariadenia z Intune podla presneho DeviceName
# Jazyk: Slovak bez diakritiky

# 1. Instalacia modulu Microsoft.Graph (ak este nie je nainstalovany)
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
    Write-Host "Instalujem Microsoft.Graph modul..."
    Install-Module Microsoft.Graph -Scope CurrentUser -Force
}

# 2. Pripojenie k Microsoft Graph s opravneniami
Write-Host "Pripajam sa k Microsoft Graph..."
Connect-MgGraph -Scopes "DeviceManagementManagedDevices.ReadWrite.All"

# 3. Zadaj presny nazov zariadenia
$targetName = Read-Host "Zadaj presny nazov zariadenia (DeviceName)"

# 4. Vyhladanie zariadenia podla presneho nazvu
$device = Get-MgDeviceManagementManagedDevice | Where-Object { $_.DeviceName -eq $targetName }

if ($null -eq $device) {
    Write-Host "Zariadenie s nazvom '$targetName' nebolo najdene." -ForegroundColor Red
    return
}

# 5. Zobrazenie detailov a potvrdenie
Write-Host "`nNajdene zariadenie:"
$device | Select-Object Id, DeviceName, OperatingSystem, UserPrincipalName

$confirm = Read-Host "Zadaj 'ano' pre potvrdenie odstranenia"

if ($confirm -eq "ano") {
    try {
        Remove-MgDeviceManagementManagedDevice -ManagedDeviceId $device.Id
        Write-Host "Zariadenie '$targetName' bolo uspesne odstranene." -ForegroundColor Green
    }
    catch {
        Write-Host "Chyba pri odstraneni zariadenia: $_" -ForegroundColor Red
    }
}
else {
    Write-Host "Odstranenie zrusene uzivatelom." -ForegroundColor Yellow
}