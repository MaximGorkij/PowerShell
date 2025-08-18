# Načítanie modulu Active Directory
Import-Module ActiveDirectory

# Zadanie prihlasovacích údajov
<# $Username = "tauris\adminfindrik"  # Zmeň na správne používateľské meno
$Password = ConvertTo-SecureString "Opekan7-Rozok" -AsPlainText -Force
$Credential = New-Object System.Management.Automation.PSCredential ($Username, $Password)
#>

$Credential = Get-ADCredentials -Validate

# Definovanie cesty k výstupnému Excel súboru
$ExcelFile = "C:\Temp\ActiveDirectoryUsers.xlsx"

# Vytvorenie Excel objektu
$Excel = New-Object -ComObject Excel.Application
$Excel.Visible = $false
$Workbook = $Excel.Workbooks.Add()

# Funkcia na pridanie dát do listu
Function Add-Sheet {
    param ($SheetName, $Data)
    $Sheet = $Workbook.Sheets.Add()
    $Sheet.Name = $SheetName

    if ($Data.Count -gt 0) {
        $Headers = $Data[0].PSObject.Properties.Name | ForEach-Object { $_.ToString() }
        for ($col = 0; $col -lt $Headers.Count; $col++) {
            write-host $Headers[$col]
            pause 10
            $Sheet.Cells.Item(1, $col + 1).Value2 = $Headers[$col]
        }
    
        for ($row = 0; $row -lt $Data.Count; $row++) {
            for ($col = 0; $col -lt $Headers.Count; $col++) {
                write-host $Headers[$col]
                pause 10
                    $Sheet.Cells.Item($row + 2, $col + 1).Value2 = $Data[$row].$($Headers[$col]).ToString()
            }
        }
    } else {
        Write-Host "⚠️ Upozornenie: Žiadne údaje na spracovanie!"
    }
}

# Nastavenie časového intervalu
$LastLogonThreshold = (Get-Date).AddMonths(-3)

# Načítanie všetkých užívateľov z AD s prihlasovacími údajmi
$Users = Get-ADUser -Filter * -Properties SamAccountName, DisplayName, LastLogonDate, Enabled -Credential $Credential

# Skontroluj, či $Users obsahuje dáta
if ($Users.Count -eq 0) {
    Write-Host "⚠️ Žiadni používatelia neboli načítaní z AD!"
    exit
}

# Filtrovanie používateľov
$ActiveUsers = $Users | Where-Object { $_.LastLogonDate -ge $LastLogonThreshold -and $_.Enabled }
$InactiveUsers = $Users | Where-Object { $_.LastLogonDate -lt $LastLogonThreshold -and $_.Enabled }
$DisabledUsers = $Users | Where-Object { -not $_.Enabled }

# Skontroluj, či aspoň jedna kategória obsahuje dáta
if ($ActiveUsers.Count -eq 0) { Write-Host "⚠️ Žiadni aktívni používatelia!" }
if ($InactiveUsers.Count -eq 0) { Write-Host "⚠️ Žiadni neaktívni používatelia!" }
if ($DisabledUsers.Count -eq 0) { Write-Host "⚠️ Žiadni disabled používatelia!" }

# Vytvorenie listov v Exceli
Add-Sheet "Aktívni užívatelia" $ActiveUsers
Add-Sheet "Neaktívni užívatelia" $InactiveUsers
Add-Sheet "Disabled užívatelia" $DisabledUsers

# Uloženie a zatvorenie Excel súboru
$Workbook.SaveAs($ExcelFile)
$Excel.Quit()

Write-Host "Export do Excelu dokončený: $ExcelFile"