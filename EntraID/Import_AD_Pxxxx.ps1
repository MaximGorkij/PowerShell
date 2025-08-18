# Import AD Pouzivatelov a Skupin (PXXXX)
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ImportPath = Join-Path $ScriptRoot "ADExport_Pxxxx"
$LogPath = Join-Path $ImportPath "Import_AD_Pxxxx.log"
$UserOU = "OU=Users,OU=MuB,DC=test-tauris,DC=local"
$GroupOU = "OU=Groups,OU=MuB,DC=test-tauris,DC=local"
$Simulation = $true  # Set to $false to perform actual changes

Function LogInfo($msg) {"[0] INFO: $msg" -f (Get-Date) | Out-File -Append $LogPath; Write-Host $msg -ForegroundColor Green }
Function LogWarn($msg) {"[0] WARN: $msg" -f (Get-Date) | Out-File -Append $LogPath; Write-Warning $msg }
Function LogError($msg) {"[0] ERROR: $msg" -f (Get-Date) | Out-File -Append $LogPath; Write-Error $msg }

# Vyčisti log
Remove-Item $LogPath -Force -ErrorAction SilentlyContinue

# Overenie existencie CSV súborov
$UsersCsv = Join-Path $ImportPath "Users_Pxxxx.csv"
$GroupsCsv = Join-Path $ImportPath "Groups_Pxxxx.csv"
$MembershipCsv = Join-Path $ImportPath "GroupMembership_Pxxxx.csv"

if (-Not (Test-Path $UsersCsv)) { LogError "CSV súbor s používateľmi neexistuje: $UsersCsv"; exit }
if (-Not (Test-Path $GroupsCsv)) { LogError "CSV súbor so skupinami neexistuje: $GroupsCsv"; exit }
if (-Not (Test-Path $MembershipCsv)) { LogError "CSV súbor s členstvom neexistuje: $MembershipCsv"; exit }

# Import používateľov
try {
    $users = Get-Content -Path $UsersCsv | Select-Object -Skip 1 | ConvertFrom-Csv
    foreach ($user in $users) {
        $exists = Get-ADUser -Filter { SamAccountName -eq $user.SamAccountName } -ErrorAction SilentlyContinue
        if (-not $exists) {
            if (-not $Simulation) {
                try {
                    New-ADUser -Name $user.Name `
                               -SamAccountName $user.SamAccountName `
                               -GivenName $user.GivenName `
                               -Surname $user.Surname `
                               -UserPrincipalName "$($user.SamAccountName)@firma.local" `
                               -Department $user.Department `
                               -Title $user.Title `
                               -EmailAddress $user.EmailAddress `
                               -Path $UserOU `
                               -AccountPassword (ConvertTo-SecureString "TempPass123!" -AsPlainText -Force) `
                               -Enabled $true `
                               -ChangePasswordAtLogon $true
                    LogInfo "Vytvorený používateľ: $($user.SamAccountName)"
                } catch {
                    LogError "Chyba pri vytváraní používateľa $($user.SamAccountName): $_"
                }
            } else {
                LogInfo "SIMULÁCIA: Vytvorený používateľ: $($user.SamAccountName)"
            }
        } else {
            LogWarn "Používateľ $($user.SamAccountName) už existuje"
        }
    }
} catch {
    LogError "Chyba pri importe používateľov: $_"
}

# Import skupín
try {
    $groups = Get-Content -Path $GroupsCsv | Select-Object -Skip 1 | ConvertFrom-Csv
    foreach ($group in $groups) {
        $exists = Get-ADGroup -Filter { SamAccountName -eq $group.SamAccountName } -ErrorAction SilentlyContinue
        if (-not $exists) {
            if (-not $Simulation) {
                try {
                    New-ADGroup -Name $group.Name `
                                -SamAccountName $group.SamAccountName `
                                -GroupScope $group.GroupScope `
                                -Description $group.Description `
                                -Path $GroupOU
                    LogInfo "Vytvorená skupina: $($group.SamAccountName)"
                } catch {
                    LogError "Chyba pri vytváraní skupiny $($group.SamAccountName): $_"
                }
            } else {
                LogInfo "SIMULÁCIA: Vytvorená skupina: $($group.SamAccountName)"
            }
        } else {
            LogWarn "Skupina $($group.SamAccountName) už existuje"
        }
    }
} catch {
    LogError "Chyba pri importe skupín: $_"
}

# Priradenie členstva
try {
    $membership = Get-Content -Path $MembershipCsv | Select-Object -Skip 1 | ConvertFrom-Csv
    foreach ($entry in $membership) {
        if (-not $Simulation) {
            try {
                Add-ADGroupMember -Identity $entry.GroupName -Members $entry.MemberSamAccountName -ErrorAction Stop
                LogInfo "Pridaný $($entry.MemberSamAccountName) do $($entry.GroupName)"
            } catch {
                LogError "Nepodarilo sa pridať $($entry.MemberSamAccountName) do $($entry.GroupName): $_"
            }
        } else {
            LogInfo "SIMULÁCIA: Pridaný $($entry.MemberSamAccountName) do $($entry.GroupName)"
        }
    }
} catch {
    LogError "Chyba pri importe členstva: $_"
}
