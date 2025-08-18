if (-not (Get-Module -Name ActiveDirectory -ErrorAction SilentlyContinue)) {
    Install-WindowsFeature RSAT-AD-PowerShell  # Pre Windows Server
    # Alebo pre klientov: 
    # Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0
    Import-Module ActiveDirectory
}

# Nastavenia
$remoteServer = "FSRS21"      # Nahraďte názvom servera
$shareName = "Rada$"         # Napr. "Data"
$remotePath = "D:\Rada"  # Napr. "D:\Shared\Data"
$outputXlsx = "C:\Temp\Permissions_Report-$(Get-Date -Format 'yyyyMMdd_HHmm').xlsx"  # Výstupný Excel súbor

# Prihlasovacie údaje (zabezpečené)
$cred = Get-Credential -Message "Zadajte doménové meno a heslo pre pripojenie k $remoteServer"

# Spustenie skriptu na vzdialenom serveri
$results = Invoke-Command -ComputerName $remoteServer -Credential $cred -ScriptBlock {
    param($share, $path)

    # 1. Získanie SMB Share oprávnení
    $smbPermissions = Get-SmbShareAccess -Name $share | 
        Select-Object Name, AccountName, AccessRight, AccessControlType

    # 2. Získanie NTFS oprávnení pre root adresár
    $ntfsRootAcl = Get-Acl -Path $path
    $ntfsRootPermissions = $ntfsRootAcl.Access | 
        Where-Object { $_.IdentityReference -like "TAURIS\*" } |
        Select-Object IdentityReference, FileSystemRights, AccessControlType, IsInherited

    # 3. Získanie NTFS oprávnení pre podadresáre (1. úroveň)
    $subDirs = Get-ChildItem -Path $path -Directory
    $subDirPermissions = @()
    $subDirList = @()
    foreach ($dir in $subDirs) {
        $acl = Get-Acl -Path $dir.FullName
        $perms = $acl.Access | 
            Where-Object { $_.IdentityReference -like "TAURIS\*" } |
            Select-Object @{Name="Folder";Expression={$dir.Name}}, IdentityReference, FileSystemRights, AccessControlType, IsInherited
        $groups = $acl.Access | 
            Where-Object { $_.IdentityReference -like "TAURIS\DL*" } |
            Select-Object IdentityReference
        $subDirList += $groups -replace '^TAURIS',''
        Write-Host $subDirList
        $subDirPermissions += $perms
    }
    
    $subListGroups = @()
    foreach ($group in $subDirList) {
        $groupmeno = Get-ADGroup -Filter { Name -eq $group } -SearchBase "OU=Rada,OU=Resources,OU=HQ TG,DC=tauris,DC=local"
        $groupMembers = Get-ADGroupMember -Identity $groupmeno -Recursive | 
                    Where-Object {$_.objectClass -eq 'user'} |
                    Get-ADUser -Properties Name, SamAccountName, UserPrincipalName, Enabled, DistinguishedName |
                    Select-Object Name, SamAccountName, UserPrincipalName, Enabled, 
                        @{Name="OrganizationalUnit";Expression={($_.DistinguishedName -split ',',2)[1]}}
       $subListGroups += $groupmeno + ',' + $groupMembers
    }

    # Vrátenie výsledkov
    return @{
        SmbPermissions = $smbPermissions
        NtfsRootPermissions = $ntfsRootPermissions
        SubDirPermissions = $subDirPermissions
        ListGroupMembers = $subListGroups
    }
} -ArgumentList $shareName, $remotePath


$results.SmbPermissions | Export-Csv -Path "C:\Temp\smb_root_permissions.csv" -NoTypeInformation
$results.NtfsRootPermissions | Export-Csv -Path "C:\Temp\ntfs_root_permissions.csv" -NoTypeInformation
$results.SubDirPermissions | Export-Csv -Path "C:\Temp\ntfs_subdir_permissions.csv" -NoTypeInformation
$results.ListGroupMembers | Export-Csv -Path "C:\Temp\list-group-members.csv" -NoTypeInformation

# Načítanie modulu pre prácu s Excelom
if (-not (Get-Module -Name ImportExcel -ErrorAction SilentlyContinue)) {
    Install-Module -Name ImportExcel -Scope CurrentUser -Force
}
Import-Module ImportExcel

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