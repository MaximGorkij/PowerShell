# Kompletny PowerShell skript pre vytvorenie skupiny a pridanie zakazanych (disabled) uzivatelov v Entra ID
# Vyuziva Microsoft Graph PowerShell SDK, je pripravene pre hybridne prostredie (Entra ID + On-Prem AD + Exchange Online)

# ==== 1. Inicializacia ====
Install-Module -Name Microsoft.Graph -Scope CurrentUser -Force -AllowClobber
Install-Module -Name ExchangeOnlineManagement -Scope CurrentUser -Force
Import-Module Microsoft.Graph
Import-Module ExchangeOnlineManagement

# ==== 2. Pripojenie ====
$Scopes = @(
    "User.Read.All",
    "Group.ReadWrite.All",
    "Directory.Read.All",
    "User.ReadWrite.All"
)
Connect-MgGraph -Scopes $Scopes
Connect-ExchangeOnline -ShowBanner:$false

# ==== 3. Definicia domeny ====
$targetDomain = "mojadomena.sk"  # <- NASTAV DOMENU, pre ktoru to ma platit

# ==== 4. Nacitanie existujucej skupiny alebo jej vytvorenie ====
$groupName = "Disabled Users Group"
$existingGroup = Get-MgGroup -Filter "displayName eq '$groupName'" -ErrorAction SilentlyContinue

if (-not $existingGroup) {
    Write-Output "Skupina '$groupName' neexistuje. Vytvaram..."
    $newGroup = New-MgGroup -DisplayName $groupName \
                             -MailEnabled:$false \
                             -MailNickname "disabledusers" \
                             -SecurityEnabled:$true \
                             -GroupTypes @()
    $groupId = $newGroup.Id

    Update-MgGroup -GroupId $groupId -IsAssignableToRole:$false
    Write-Output "Zakazany pristup skupine '$groupName' k rolam a zdrojom."
} else {
    Write-Output "Skupina '$groupName' uz existuje."
    $groupId = $existingGroup.Id
    Update-MgGroup -GroupId $groupId -IsAssignableToRole:$false
    Write-Output "Overene: Skupina '$groupName' nema pristup k prostriedkom."
}

# ==== 5. Rotacia logov ====
$logDir = "$PSScriptRoot\Logs"
if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$logBase = "$logDir\DisabledUsersLog.txt"
if (Test-Path $logBase) {
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    Rename-Item -Path $logBase -NewName "DisabledUsersLog_$timestamp.txt"
}
$logPath = $logBase
$logEntries = @()

# ==== 6. Ziskanie disabled uzivatelov podla menovej politiky (P0000) ====
Write-Output "Ziskavam zakazanych pouzivatelov so vzorom P0000 a domenou $targetDomain..."
$allDisabledUsers = Get-MgUser -Filter "accountEnabled eq false" -All
$disabledUsers = $allDisabledUsers | Where-Object {
    $_.UserPrincipalName -match "^P\d{4}@$targetDomain$" -and
    ($_.OnPremisesSyncEnabled -eq $true -or $_.OnPremisesImmutableId)
}

# ==== 7. Spracovanie uzivatelov ====
foreach ($user in $disabledUsers) {
    $userId = $user.Id
    try {
        $userGroups = Get-MgUserMemberOf -UserId $userId -All | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.group' }
        $groupNames = $userGroups | ForEach-Object { $_.displayName }
        $msgGroupList = "Uzivatel $($user.DisplayName) je v skupinach: $($groupNames -join ', ')"
        Write-Output $msgGroupList
        $logEntries += $msgGroupList

        $disabledGroupMembership = $userGroups | Where-Object { $_.displayName -eq $groupName }
        if ($disabledGroupMembership) {
            $addedTime = Get-MgGroupMember -GroupId $groupId -All | Where-Object { $_.Id -eq $userId } | Select-Object -ExpandProperty AdditionalProperties
            if ($addedTime["createdDateTime"]) {
                $createdDate = [datetime]$addedTime["createdDateTime"]
                if ($createdDate -lt (Get-Date).AddDays(-90)) {
                    try {
                        $backupDir = "$PSScriptRoot\Backups"
                        if (!(Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir | Out-Null }
                        $backupPath = "$backupDir\$($user.UserPrincipalName)_backup.json"
                        $user | ConvertTo-Json -Depth 10 | Out-File -FilePath $backupPath -Encoding UTF8

                        $samAccountName = ($user.UserPrincipalName -split "@")[0]
                        $adUser = Get-ADUser -Filter { SamAccountName -eq $samAccountName } -ErrorAction SilentlyContinue
                        if ($adUser) {
                            Remove-ADUser -Identity $adUser.DistinguishedName -Confirm:$false
                            $logEntries += "Pouzivatel $samAccountName bol odstraneny z lokalneho AD."
                        } else {
                            $logEntries += "Pouzivatel $samAccountName nebol najdeny v lokalnom AD."
                        }

                        $delegationPath = "$PSScriptRoot\DelegationInstructions_$($user.UserPrincipalName).txt"
                        "Zalohovany a deaktivovany pouzivatel: $($user.DisplayName)`nOdstranit z AD: $samAccountName" |
                            Out-File -FilePath $delegationPath -Encoding UTF8
                        $logEntries += "Instrukcie pre delegovaneho admina ulozene do: $delegationPath"

                        continue
                    } catch {
                        $errDel = "CHYBA PRI ZALOHE/ZRUSENI: $($user.DisplayName): $($_.Exception.Message)"
                        Write-Warning $errDel
                        $logEntries += $errDel
                        continue
                    }
                }
            }
        }

        # Skrytie z GAL (Exchange Online)
        try {
            Set-Mailbox -Identity $user.UserPrincipalName -HiddenFromAddressListsEnabled $true
            $logEntries += "Mailbox pre $($user.UserPrincipalName) bol skryty v GAL (HiddenFromAddressListsEnabled = true)."
        } catch {
            $logEntries += "Nepodarilo sa skryt mailbox $($user.UserPrincipalName): $($_.Exception.Message)"
        }

        foreach ($group in $userGroups) {
            if ($group.displayName -ne "All users") {
                try {
                    Remove-MgGroupMember -GroupId $group.Id -DirectoryObjectId $userId -ErrorAction Stop
                    $msgRemove = "Odstraneny z: $($group.displayName)"
                    Write-Output $msgRemove
                    $logEntries += $msgRemove
                } catch {
                    $warn = "CHYBA pri odstraneni z '$($group.displayName)': $($_.Exception.Message)"
                    Write-Warning $warn
                    $logEntries += $warn
                }
            }
        }

        $isMember = Get-MgGroupMember -GroupId $groupId -All | Where-Object { $_.Id -eq $userId }
        if (-not $isMember) {
            Add-MgGroupMember -GroupId $groupId -DirectoryObjectId $userId
            $msg = "Pridany do '$groupName': $($user.DisplayName) ($($user.UserPrincipalName))"
            Write-Output $msg
            $logEntries += $msg
        } else {
            $msg = "Preskoceny (uz je clen '$groupName'): $($user.DisplayName) ($($user.UserPrincipalName))"
            Write-Output $msg
            $logEntries += $msg
        }

    } catch {
        $errorMsg = "CHYBA: $($user.DisplayName): $($_.Exception.Message)"
        Write-Warning $errorMsg
        $logEntries += $errorMsg
    }
}

# ==== 8. Ulozenie logu ====
$logEntries | Out-File -FilePath $logPath -Encoding UTF8
Write-Output "Log ulozeny do: $logPath"

# ==== 9. Export CSV pre audit ====
$csvPath = "$PSScriptRoot\\DisabledUsersExport_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$disabledUsers | Select-Object DisplayName, UserPrincipalName, Id | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
Write-Output "CSV export: $csvPath"

# ==== 10. Odpojenie ====
Disconnect-MgGraph
Disconnect-ExchangeOnline -Confirm:$false
