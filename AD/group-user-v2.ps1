$groups = Get-ADGroup -filter * -SearchBase "DC=tauris,DC=local"
ForEach ($g in $groups) 
{
$path = "C:\Users\findrik\OneDrive - Tauris, a.s\Documents\Excel\exp-" + $g.Name + ".csv"
Get-ADGroup -Identity $g.Name -Properties * | Select-Object name,description | Out-File $path -Append

$results = Get-ADGroupMember -Identity $g.Name -Recursive | Get-ADUser -filter 'Enabled -eq $True' -Properties DisplayName,EmailAddress,memberof,DistinguishedName,Enabled

ForEach ($r in $results){
New-Object PSObject -Property @{       

    'DisplayName = $r.displayname'
    'Email=$r.EmailAddress'
    'Member of=$r.MemberOf'
    'Enabled=$r.Enabled'
    'Grop=$.g'
  '}'
} | Out-File $path -Append
}