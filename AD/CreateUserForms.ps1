param(
    [Parameter(Mandatory = $true)]
    [string]$FirstName,
    
    [Parameter(Mandatory = $true)]
    [string]$LastName,
    
    [Parameter(Mandatory = $true)]
    [string]$JobTitle,
    
    [Parameter(Mandatory = $true)]
    [string]$Division
)

# Nastavenie premenných
$samAccountName = ($LastName).ToLower() # napr. jnovak
$userPrincipalName = $samAccountName + "@tauris.sk"
$displayName = "$LastName $FirstName"
$initialPassword = ConvertTo-SecureString -String "Tauris2025" -AsPlainText -Force

# Cesta k OU, kde sa má užívateľ vytvoriť
# Ak myslíte 'default' kontajner, je to 'Users' alebo špecifická OU:
$OUPath = "OU=Default,DC=tauris,DC=sk" 
# Alebo pre koreňovú OU, ak nebola nikdy zmenená: "CN=Users,DC=vasedomena,DC=sk"

# Vytvorenie nového AD užívateľa
New-ADUser -SamAccountName $samAccountName `
    -UserPrincipalName $userPrincipalName `
    -Name $displayName `
    -DisplayName $displayName `
    -GivenName $FirstName `
    -Surname $LastName `
    -Department $Division `
    -Title $JobTitle `
    -Path $OUPath `
    -AccountPassword $initialPassword `
    -Enabled $true `
    -ChangePasswordAtLogon $true

Write-Host "Uzivatel $displayName ($samAccountName) bol uspesne vytvoreny v $OUPath."