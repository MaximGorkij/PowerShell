# Nastav premenne
$kredencial = Get-ADCredentials -Validate   # Zadaj iné AD konto
$datum = (Get-Date).AddDays(-90)

# Vylúčené OU (podľa DN)
$ouExclude = @(
    "OU=DISABLED ACCOUNTS,DC=tauris,DC=local","OU=Servis_Accounts", "OU=zmaz"
)

$excludeOUText = @('zmaz', 'Service', 'Disabled')

# Všetci používatelia v doméne
$users = Get-ADUser -Filter * -Properties LastLogonDate, DistinguishedName -Credential $kredencial

# Filtrovanie
$result = $users | Where-Object {
    ($_.LastLogonDate -lt $datum -or !$_.LastLogonDate)  -and
    -not (
        # Skontroluje, či sa v DN nachádza niektorý zo zakázaných textov v OU
        $excludeOUText | ForEach-Object {
            $_ -like "*$_*"
        }
    )
}

# Výber + rozdelenie DN na CN_OU a OU_Path
$export = $result | Select-Object @{
    Name = "CN_OU";
    Expression = {
        ($_).DistinguishedName -match '^(CN=.*?,OU=[^,]+)' | Out-Null
        $matches[1] -replace '\\',''
    }
}, @{
    Name = "OU_Path";
    Expression = {
        ($_).DistinguishedName -replace '^(CN=.*?,OU=[^,]+,)', ''
    }
}, Name, SamAccountName, LastLogonDate, DistinguishedName

$sortedexport = $export | Sort-Object OU_Path, CN

# Export do Excelu (.csv verzia, ak nechceš .xlsx)
#$export | Export-Csv -Path "C:\temp\neaktivni_pouzivatelia.csv" -NoTypeInformation -Encoding UTF8

# Export do Excelu
$excelPath = "C:\temp\neaktivni_pouzivatelia.xlsx"
$sortedExport | Export-Excel -Path $excelPath -WorksheetName "Neaktívni používatelia" -AutoSize -TableName "Neaktivni" -BoldTopRow
