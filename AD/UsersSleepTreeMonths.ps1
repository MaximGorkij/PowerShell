param(
    #[string]$AdminUser,
    #[string]$AdminPassword,
    [string[]]$ExcludeOUPatterns = @("zmaz", "Service_Accounts", "Disabled", "Servis_Accounts", "Zrusene"),
    [string]$ExportPath = "C:\temp\NeaktivniUzivatele.xlsx"
)

# Načítanie potrebných modulov
try {
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    Write-Host "Modul ActiveDirectory nie je nainštalovaný. Inštalujem..."
    Install-Module -Name ActiveDirectory -Force -Scope CurrentUser
    Import-Module ActiveDirectory
}

# Vytvorenie poverení pre alternatívneho používateľa
<#if ($AdminUser -and $AdminPassword) {
    $securePassword = ConvertTo-SecureString $AdminPassword -AsPlainText -Force
    $credentials = New-Object System.Management.Automation.PSCredential ($AdminUser, $securePassword)
} else {
    $credentials = Get-Credential -Message "Zadajte poverenia pre pripojenie k Active Directory"
}
    #>

$credentials = Get-ADCredentials -Validate

# Vypočítanie dátumu pred 3 mesiacmi
$dateThreshold = (Get-Date).AddMonths(-3)

# Získanie všetkých OU v doméne
try {
    
    $allOUs = Get-ADOrganizationalUnit -Filter * -Properties Name | 
              Where-Object {
                  $ou = $_
                  -not ($ExcludeOUPatterns | Where-Object { $ou.Name -like "*$_*" })
              } |
              Select-Object -ExpandProperty DistinguishedName
              
    if (-not $allOUs) {
        throw "Nenašli sa žiadne OU po aplikovaní filtrov"
    }

    Write-Host "Hľadám v týchto OU:"
    $allOUs | ForEach-Object { Write-Host " - $_" }

    # Získanie neaktívnych používateľov
    $inactiveUsers = foreach ($ou in $allOUs) {
       Get-ADUser -filter 'enabled -eq $true' -SearchBase $ou -Credential $credentials -Properties LastLogonDate, SamAccountName, UserPrincipalName, Enabled, EmailAddress, DistinguishedName | Where-object {($_.LastLogonDate -lt $dateThreshold) -or (!$_.LastLogonDate)}
       #Get-ADUser -Filter '(enabled -eq $true) -and ((PasswordLastSet -lt $dateThreshold) -or (LastLogonTimestamp -lt $dateThreshold))' -Properties LastLogonDate, SamAccountName, UserPrincipalName, Enabled, EmailAddress, DistinguishedName, PasswordLastSet,LastLogonTimestamp | ft Name,PasswordLastSet,@{N="LastLogonTimestamp";E={[datetime]::FromFileTime($_.LastLogonTimestamp)}}
    }

    $results = $inactiveUsers | 
               Select-Object SamAccountName, UserPrincipalName, Name, LastLogonDate, Enabled, EmailAddress, DistinguishedName |
               Sort-Object LastLogonDate -Unique

    # Export do Excelu
    try {
        if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
            Install-Module -Name ImportExcel -Force -Scope CurrentUser
        }
        
        $results | Export-Excel -Path $ExportPath -WorksheetName "Neaktívni používatelia" -AutoSize -FreezeTopRow -BoldTopRow -TableName "InactiveUsers"
        Write-Host "Úspešne exportované do $ExportPath"
        Write-Host "Počet nájdených neaktívnych používateľov: $($results.Count)"
    }
    catch {
        # Alternatíva ak nie je k dispozícii ImportExcel modul
        $results | Export-Csv -Path ($ExportPath -replace 'xlsx$', 'csv') -NoTypeInformation -Encoding UTF8
        Write-Host "Exportované do CSV formátu: $($ExportPath -replace 'xlsx$', 'csv')"
    }
}
catch {
    Write-Host "Chyba: $_" -ForegroundColor Red
}