$Groups = (Get-AdGroup -filter * | Where-Object {$_.name -like "**"} | Select-Object name -ExpandProperty name)

$Table = @()

$Record = @{
  "Group Name" = ""
  "Name" = ""
  "Username" = ""
}


Foreach ($Group in $Groups) {

  $Arrayofmembers = Get-ADGroupMember -identity $Group -recursive | Select-Object name,samaccountname

  foreach ($Member in $Arrayofmembers) {
    $Record."Group Name" = $Group
    $Record."Name" = $Member.name
    $Record."UserName" = $Member.samaccountname
    $objRecord = New-Object PSObject -property $Record
    $Table += $objrecord

  }
}

$Table | Export-Csv -Path "C:\Users\findrik\OneDrive - Tauris, a.s\Documents\Excel\ou_users-enabled.csv"
