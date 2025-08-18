#requires -Modules ImportExcel, ActiveDirectory

param (
    [string]$SharePath,
    [string]$OU,
    [string[]]$Rights
)

$datum = Get-Date -Format 'yyyyMMdd_HHmm'
# === Logovanie ===
$logFile = "C:\Users\findrik\OneDrive - Tauris, a.s\Documents\Excel\AD_Share_Audit_$datum.log"
$cred = Get-Credential -Message "Zadaj doménové poverenia pre prístup k $SharePath"

function Write-Log {
    param (
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $entry = "$timestamp [$Level] $Message"
    Add-Content -Path $logFile -Value $entry
    Write-Host $entry
}

# === Funkcia: Získanie členov skupiny ===
function Get-ADGroupMembersRecursive {
    param ([string]$GroupName)
    try {
        $members = Get-ADGroupMember -Identity $GroupName -Recursive | ForEach-Object {
            if ($_ -is [Microsoft.ActiveDirectory.Management.ADUser]) {
                [PSCustomObject]@{
                    Group       = $GroupName
                    User        = $_.SamAccountName
                    Name        = $_.Name
                    Enabled     = $_.Enabled
                    ObjectType  = "User"
                }
            }
        }
        return $members
    } catch {
        Write-Log "Chyba pri získavaní členov skupiny $GroupName : $_" -Level "ERROR"
        return @()
    }
}

# === Funkcia: Preklad ACL práv ===
function Convert-Permission {
    param ($accessMask)

    $permissions = @()
    if ($accessMask -band 0x1F01FF) { $permissions += "FullControl" }
    elseif ($accessMask -band 0x1301BF) { $permissions += "Modify" }
    elseif ($accessMask -band 0x120089) { $permissions += "Read" }
    elseif ($accessMask -band 0x120116) { $permissions += "Write" }

    if ($permissions.Count -eq 0) { $permissions += "Custom" }
    return ($permissions -join ", ")
}


# === Načítaj priečinky ===
$folders = @()
try {
    $folders += Get-ChildItem -Path $SharePath -Credential $cred -Directory -Depth 1 -ErrorAction Stop
    $folders += Get-Item -Path $SharePath -Credential $cred -ErrorAction Stop
    Write-Log "Načítaných priečinkov: $($folders.Count)"
} catch {
    Write-Log "Zlyhalo čítanie adresárov z $SharePath : $_" -Level "ERROR"
    exit 1
}

# === Spracovanie ACL ===
$allGroups = @{}
$groupPermissions = @()

foreach ($folder in $folders) {
    Write-Log "Spracúvam ACL pre $($folder.FullName)"
    try {
        $acl = Get-Acl -Path $folder.FullName
    } catch {
        Write-Log "Zlyhanie pri ACL: $($folder.FullName): $_" -Level "WARN"
        continue
    }

    foreach ($ace in $acl.Access) {
        $identity = $ace.IdentityReference.Value
        $permType = Convert-Permission -accessMask $ace.FileSystemRights.value__

        if (-not $Rights -contains $permType) {
            continue
        }

        if ($identity -like "*\\*") {
            $domain, $name = $identity -split '\\', 2
            try {
                $adGroup = Get-ADGroup -Identity $name -ErrorAction Stop

                # Filter podľa OU
                if ($adGroup.DistinguishedName -notlike "*$OU*") {
                    Write-Log "Skupina '$name' nie je v povolenej OU → ignorujem." -Level "INFO"
                    continue
                }

                if (-not $allGroups.ContainsKey($name)) {
                    Write-Log "Zisťujem členov skupiny '$name'"
                    $allGroups[$name] = Get-ADGroupMembersRecursive -GroupName $name
                }

                $groupPermissions += [PSCustomObject]@{
                    Group     = $name
                    Folder    = $folder.FullName
                    Rights    = $permType
                }
            } catch {
                # Môže byť používateľ (NTFS účet)
                try {
                    $adUser = Get-ADUser -Identity $name -ErrorAction Stop
                    $key = "DirectUser_$name"
                    if (-not $allGroups.ContainsKey($key)) {
                        $allGroups[$key] = ,([PSCustomObject]@{
                            Group       = "DirectUser"
                            User        = $adUser.SamAccountName
                            Name        = $adUser.Name
                            Enabled     = $adUser.Enabled
                            ObjectType  = "User"
                        })
                    }
                    $groupPermissions += [PSCustomObject]@{
                        Group     = "DirectUser"
                        Folder    = $folder.FullName
                        Rights    = $permType
                    }
                } catch {
                    Write-Log "Identita '$name' nie je skupina ani používateľ – ignorujem." -Level "WARN"
                }
            }
        }
    }
}

# === Export skupín ===
$outputExcel = "C:\Users\findrik\OneDrive - Tauris, a.s\Documents\Excel\AD_Share_Audit$(Get-Date -Format 'yyyyMMdd_HHmm').xlsx"

# Odstráň predchádzajúci Excel
Remove-Item $outputExcel -ErrorAction SilentlyContinue

foreach ($group in $allGroups.Keys) {
    $data = $allGroups[$group]
    if ($data.Count -gt 0) {
        $wsName = ($data[0].Group -replace '[^\w]', '_').Substring(0, [Math]::Min(30, ($data[0].Group).Length))
        Write-Log "Exportujem skupinu '$($data[0].Group)' $($data.Count) používateľov"
        $data | Export-Excel -Path $outputExcel -WorksheetName $wsName -AutoSize -Append
    } else {
        Write-Log "Skupina '$group' nemá používateľov - preskakujem." -Level "WARN"
    }
}

# === Export oprávnení ===
Write-Log "Exportujem prehľad oprávnení skupín"
$groupPermissions | Export-Excel -Path $outputExcel -WorksheetName "SkupinyPrava" -AutoSize -Append

Write-Log "✅ Audit dokončený. Výstupný Excel: $outputExcel"
Write-Log "Log súbor: $logFile"