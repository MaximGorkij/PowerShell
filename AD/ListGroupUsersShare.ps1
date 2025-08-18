# Prerequisites
if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
    Install-Module -Name ImportExcel -Scope CurrentUser -Force
}

Import-Module ActiveDirectory
Import-Module ImportExcel

$sharePath = "\\fsrs21\rada$"  # <== Zmeň na tvoju UNC cestu
$tempDir = "$env:TEMP\ADGroupAudit"
$outputExcel = "C:\Users\findrik\OneDrive - Tauris, a.s\Documents\Excel\SharePermissionsReport$(Get-Date -Format 'yyyyMMdd_HHmm').xlsx"

# Čistý priečinok
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $tempDir
New-Item -ItemType Directory -Path $tempDir | Out-Null

# $credentials = Get-ADCredentials -Validate
function Get-ADGroupMembersRecursive {
    param (
        [string]$GroupName
    )

    try {
        $members = Get-ADGroupMember -Identity $GroupName -Recursive | ForEach-Object {
            if ($_ -is [Microsoft.ActiveDirectory.Management.ADUser]) {
                [PSCustomObject]@{
                    Group     = $GroupName
                    User      = $_.SamAccountName
                    Name      = $_.Name
                    Enabled   = $_.Enabled
                    ObjectType = "User"
                }
            }
        }
        return $members
    } catch {
        Write-Warning "Chyba pri získavaní členov skupiny $GroupName - $_"
        return @()
    }
}

# Root + 1. úroveň
$folders = @()
try {
    $folders += Get-ChildItem -Path $sharePath -Directory -Depth 1 -ErrorAction Stop
    $folders += Get-Item -Path $sharePath -Credential $credentials -ErrorAction Stop
} catch {
    Write-Error "Nepodarilo sa získať zoznam adresárov z $sharePath - $_"
    exit 1
}

$allGroups = @{}

foreach ($folder in $folders) {
    try {
        $acl = Get-Acl -Path $folder.FullName
    } catch {
        Write-Warning "ACL sa nepodarilo získať pre $($folder.FullName): $_"
        continue
    }

    foreach ($ace in $acl.Access) {
        $identity = $ace.IdentityReference.Value
        if ($identity -like "*\\*") {
            $domain, $name = $identity -split '\\', 2

            try {
                $adObject = Get-ADGroup -Identity $name -ErrorAction Stop
                if (-not $allGroups.ContainsKey($name)) {
                    $allGroups[$name] = Get-ADGroupMembersRecursive -GroupName $name
                }
            } catch {
                # Nie je skupina, nič nerob
            }
        }
    }
}

# Export
Remove-Item $outputExcel -ErrorAction SilentlyContinue

foreach ($group in $allGroups.Keys) {
    $data = $allGroups[$group]
    if ($data.Count -gt 0) {
        $wsName = $group.Substring(0, [Math]::Min(30, $group.Length)) # max 31 znakov
        $data | Export-Excel -Path $outputExcel -WorksheetName $wsName -AutoSize -Append
    }
}

Write-Host "`n✅ Hotovo. Súbor: $outputExcel"
