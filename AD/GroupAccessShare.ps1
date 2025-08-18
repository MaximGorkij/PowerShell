# Ak modul ImportExcel ešte nemáte, nainštalujte ho
Install-Module -Name ImportExcel -Scope CurrentUser

# Pripojenie k vzdialenému serveru (ak nie ste priamo na ňom)
$remoteServer = "FSRS21"  # Nahraďte skutočným menom servera
$shareName = "Rada$"     # Napr. "Data"
$domain = "tauris"

function Get-Credentials {
    param (
        [string]$domain
    )
    $username = Read-Host "Zadajte doménové meno ($domain\username)"
    $password = Read-Host "Zadajte heslo" -AsSecureString
    $credentials = New-Object System.Management.Automation.PSCredential("$domain\$username", $password)
    return $credentials
}

$credentials = Get-Credentials -domain $domain

# Získanie SMB Share oprávnení
$smbPermissions = Invoke-Command -ComputerName $remoteServer -Credential $credentials -ScriptBlock {
    param($share)
    Get-SmbShareAccess -Name $share
} -ArgumentList $shareName

# Výpis oprávnení
$smbPermissions | Format-Table -AutoSize

# Cesta k zdieľanému priečinku na serveri (napr. "D:\Shared\Data")
$remotePath = "D:\Rada"  # Napr. "D:\Shared\Data"
$path = $remotePath

# Získanie NTFS oprávnení pre root adresár
$ntfsRootPermissions = Invoke-Command -ComputerName $remoteServer -Credential $credentials -ScriptBlock {
    param($path)
    (Get-Acl -Path $path).Access |  
    Where-Object { $_.IdentityReference -like "TAURIS\*" } | Select-Object IdentityReference, FileSystemRights, AccessControlType, IsInherited
} -ArgumentList $remotePath

# Výpis
$ntfsRootPermissions | Format-Table -AutoSize

$subDirectoriesPermissions = Invoke-Command -ComputerName $remoteServer -Credential $credentials -ScriptBlock {
    param($path)
    $subDirs = Get-ChildItem -Path $path -Directory
    $results = @()
    foreach ($dir in $subDirs) {
        $acl = Get-Acl -Path $dir.FullName 
        $perms = $acl.Access | 
        Where-Object { $_.IdentityReference -like "TAURIS\*" } | Select-Object @{Name="Folder";Expression={$dir.Name}}, IdentityReference, FileSystemRights, AccessControlType, IsInherited
        $results += $perms
    }
    return $results
} -ArgumentList $remotePath

# Výpis
$subDirectoriesPermissions | Format-Table -AutoSize

$smbPermissions | Export-Csv -Path "C:\Temp\smb_root_permissions.csv" -NoTypeInformation
$ntfsRootPermissions | Export-Csv -Path "C:\Temp\ntfs_root_permissions.csv" -NoTypeInformation
$subDirectoriesPermissions | Export-Csv -Path "C:\Temp\ntfs_subdir_permissions.csv" -NoTypeInformation

# Cesta k priečinku, kde sú CSV súbory
$csvFolder = "C:\Temp"  

# Výstupný Excel súbor
$outputXlsx = "C:\Users\findrik\OneDrive - Tauris, a.s\Documents\Excel\Combined_Permissions-$(Get-Date -Format 'yyyyMMdd_HHmm').xlsx"  

# Získajte všetky CSV súbory v priečinku
$csvFiles = Get-ChildItem -Path $csvFolder -Filter "*.csv"  

# Vytvorte nový Excel zošit a pridajte každé CSV ako samostatný list
$excelPackage = $null
foreach ($csv in $csvFiles) {
    $sheetName = $csv.BaseName  # Názov listu = názov CSV bez prípony
    $csvData = Import-Csv -Path $csv.FullName
    
    if (-not $excelPackage) {
        # Prvý CSV sa stane základom Excel súboru
        $excelPackage = $csvData | Export-Excel -Path $outputXlsx -WorksheetName $sheetName -PassThru
    } else {
        # Ďalšie CSV sa pridajú ako nové listy
        $excelPackage = $csvData | Export-Excel -ExcelPackage $excelPackage -WorksheetName $sheetName -PassThru
    }
}

# Uloženie a zatvorenie Excel súboru
Close-ExcelPackage -ExcelPackage $excelPackage -Show

Remove-Item -Path "C:\Temp\*.csv" -Force  # Rýchle zmazanie bez potvrdenia