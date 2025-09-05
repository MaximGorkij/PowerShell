$ScriptFolder = "C:\TaurisIT\skript"

# Heslá v plain texte (len na uloženie, potom ich môžeš vymazať)
$RootPlainPassword = "TvojeNemenneHeslo123!"
$AdminPlainPassword = "DRUFhijac1"

# Ulož ako SecureString do XML
$RootPlainPassword  | ConvertTo-SecureString -AsPlainText -Force | Export-Clixml "$ScriptFolder\RootPwd.xml"
$AdminPlainPassword | ConvertTo-SecureString -AsPlainText -Force | Export-Clixml "$ScriptFolder\AdminPwd.xml"

Write-Output "Heslá boli uložené do XML: RootPwd.xml a AdminPwd.xml"
