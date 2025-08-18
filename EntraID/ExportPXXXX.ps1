# Vytvor exportný priečinok
$ExportPath = ".\ADExport_Pxxxx"
New-Item -Path $ExportPath -ItemType Directory -Force | Out-Null

# Získaj všetkých používateľov v tvare Pxxxx
$users = Get-ADUser -Filter * -Properties MemberOf, GivenName, Surname, Department, Title, EmailAddress |
    Where-Object { $_.SamAccountName -match '^P\d{4}$' }

# Ulož používateľov do CSV
$users | Select-Object SamAccountName, Name, GivenName, Surname, Enabled, Department, Title, EmailAddress |
    Export-Csv -Path "$ExportPath\Users_Pxxxx.csv" -NoTypeInformation -Encoding UTF8

# Priprav zoznam unikátnych skupín, kde sú títo používatelia členmi
$groupNames = $users | ForEach-Object {
    $_.MemberOf
} | Where-Object { $_ -ne $null } | Sort-Object -Unique

# Získaj podrobnosti o skupinách a exportuj
$groups = @()
foreach ($groupDN in $groupNames) {
    $group = Get-ADGroup -Identity $groupDN -Properties Description, GroupScope
    $groups += $group
}
$groups | Select-Object Name, SamAccountName, GroupScope, Description |
    Export-Csv -Path "$ExportPath\Groups_Pxxxx.csv" -NoTypeInformation -Encoding UTF8

# Vytvor mapovanie členstva (len PXXXX členovia)
$groupMembership = @()
foreach ($group in $groups) {
    $members = Get-ADGroupMember -Identity $group.SamAccountName -Recursive | Where-Object {
        $_.ObjectClass -eq 'user' -and $_.SamAccountName -match '^P\d{4}$'
    }
    foreach ($member in $members) {
        $groupMembership += [PSCustomObject]@{
            GroupName = $group.SamAccountName
            MemberSamAccountName = $member.SamAccountName
        }
    }
}

$groupMembership | Export-Csv -Path "$ExportPath\GroupMembership_Pxxxx.csv" -NoTypeInformation -Encoding UTF8

Write-Host "✅ Export hotový. Dáta sú uložené v priečinku '$ExportPath'" -ForegroundColor Green
