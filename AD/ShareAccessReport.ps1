<#
.SYNOPSIS
Zisťuje, ktoré AD skupiny z danej OU majú prístup k zdieľanému adresáru a jeho podadresárom.
Vyžaduje doménové poverenia.
#>

# Import modulov
Import-Module ActiveDirectory

# Funkcia na získanie poverení
function Get-Credentials {
    param (
        [string]$domain
    )
    $username = Read-Host "Zadajte doménové meno ($domain\username)"
    $password = Read-Host "Zadajte heslo" -AsSecureString
    $credentials = New-Object System.Management.Automation.PSCredential("$domain\$username", $password)
    return $credentials
}

# Hlavné parametre
$domain = "tauris"  # Nahraďte napr. "contoso.com"
$targetOU = "OU=Rada,OU=Resources,OU=HQ TG,DC=tauris,DC=local"  # Napr. "OU=Skupiny,DC=contoso,DC=com"
$sharePath = "\\FSRS21\Rada$"  # Cesta k zdieľanému adresáru
$checkSubfolders = $true  # Kontrolovať aj podadresáre?

# Získanie poverení
$credentials = Get-Credentials -domain $domain

# Získanie všetkých skupín z cieľovej OU
$groups = Get-ADGroup -SearchBase $targetOU -Filter * -Credential $credentials

# Výsledky
$results = @()

# Kontrola prístupových práv pre každú skupinu
foreach ($group in $groups) {
    $groupName = $group.Name
    $groupSID = $group.SID.Value

    # Kontrola hlavného adresára
    $acl = Get-Acl -Path $sharePath
    $accessRules = $acl.Access | Where-Object { $_.IdentityReference -like "*\$groupName" -or $_.IdentityReference -eq $groupSID }

    if ($accessRules) {
        foreach ($rule in $accessRules) {
            $results += [PSCustomObject]@{
                GroupName = $groupName
                Path = $sharePath
                Permission = $rule.FileSystemRights
                AccessType = $rule.AccessControlType
                IsInherited = $rule.IsInherited
                Type = "Direct"
            }
        }
    }

    # Kontrola podadresárov (ak je požadovaná)
    if ($checkSubfolders) {
        $subfolders = Get-ChildItem -Path $sharePath -Depth 2 -Directory -Recurse -ErrorAction SilentlyContinue
        foreach ($folder in $subfolders) {
            $folderPath = $folder.FullName
            $acl = Get-Acl -Path $folderPath
            $accessRules = $acl.Access | Where-Object { $_.IdentityReference -like "*\$groupName" -or $_.IdentityReference -eq $groupSID }

            if ($accessRules) {
                foreach ($rule in $accessRules) {
                    $results += [PSCustomObject]@{
                        GroupName = $groupName
                        Path = $folderPath
                        Permission = $rule.FileSystemRights
                        AccessType = $rule.AccessControlType
                        IsInherited = $rule.IsInherited
                        Type = "Subfolder"
                    }
                }
            }
            $smbShare = Get-SmbShareAccess -Name "ShareName" -ErrorAction SilentlyContinue
            $smbAccess = $smbShare | Where-Object { $_.AccountName -like "*\$groupName" }
            if ($smbAccess) {
                $results += [PSCustomObject]@{
                    GroupName = $groupName
                    Path = "SMB Share"
                    Permission = $smbAccess.AccessRight
                    AccessType = "Allow"
                    IsInherited = $false
                    Type = "SMB"
    }
}
        }
    }
}

# Export výsledkov
$results | Export-Csv -Path "ShareAccessReport.csv" -NoTypeInformation -Encoding UTF8
$results | Format-Table -AutoSize

Write-Host "Hotovo! Výsledky sú uložené v ShareAccessReport.csv" -ForegroundColor Green