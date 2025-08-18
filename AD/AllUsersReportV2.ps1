# Načítanie modulu Active Directory
Import-Module ActiveDirectory

# Zadanie prihlasovacích údajov
$Username = Read-Host "Zadajte používateľské meno (formát DOMÉNA\používateľ)"
$Password = Read-Host "Zadajte heslo" -AsSecureString
$Credential = New-Object System.Management.Automation.PSCredential ($Username, $Password)

# Definovanie cesty k výstupnému Excel súboru
$ExcelFile = "C:\Temp\ActiveDirectoryUsers_$(Get-Date -Format 'yyyyMMdd_HHmm').xlsx"

# Vytvorenie priečinka ak neexistuje
if (-not (Test-Path "C:\Temp")) {
    New-Item -ItemType Directory -Path "C:\Temp" | Out-Null
}

try {
    # Vytvorenie Excel objektu
    $Excel = New-Object -ComObject Excel.Application
    $Excel.Visible = $false
    $Workbook = $Excel.Workbooks.Add()

    # Funkcia na pridanie dát do listu s formátovaním
    Function Add-Sheet {
        param ($SheetName, $Data)
        
        $Sheet = $Workbook.Sheets.Add()
        $Sheet.Name = $SheetName

        if ($Data.Count -gt 0) {
            $Headers = $Data[0].PSObject.Properties.Name
            
            # Pridanie hlavičiek
            for ($col = 0; $col -lt $Headers.Count; $col++) {
                $Sheet.Cells.Item(1, $col + 1).Value2 = $Headers[$col]
                $Sheet.Cells.Item(1, $col + 1).Interior.ColorIndex = 15  # Sivé pozadie pre hlavičky
                $Sheet.Cells.Item(1, $col + 1).Font.Bold = $true
            }
        
            # Pridanie dát
            for ($row = 0; $row -lt $Data.Count; $row++) {
                for ($col = 0; $col -lt $Headers.Count; $col++) {
                    $value = $Data[$row].$($Headers[$col])
                    $Sheet.Cells.Item($row + 2, $col + 1).Value2 = if ($null -ne $value) { $value.ToString() } else { "" }
                    
                    # Zafarbenie riadkov kde OU obsahuje "disabled" alebo "zmaz"
                    if ($Headers[$col] -eq "CleanOU" -and ($value -match "disabled" -or $value -match "zmaz")) {
                        $Sheet.Rows.Item($row + 2).Interior.ColorIndex = 15  # Sivé pozadie
                        $Sheet.Rows.Item($row + 2).Font.ColorIndex = 1  # Čierna farba textu
                    }
                }
            }
            
            # Auto-fit stĺpce
            $usedRange = $Sheet.UsedRange
            $usedRange.EntireColumn.AutoFit() | Out-Null
        } else {
            Write-Warning "Upozornenie: Žiadne údaje na spracovanie pre list '$SheetName'!"
        }
    }

    # Nastavenie časového intervalu
    $LastLogonThreshold = (Get-Date).AddMonths(-3)

    # Načítanie všetkých užívateľov z AD s prihlasovacími údajmi
    $Users = Get-ADUser -Filter * -Properties SamAccountName, DisplayName, LastLogonDate, Enabled, EmailAddress, DistinguishedName -Credential $Credential

    # Skontroluj, či $Users obsahuje dáta
    if ($Users.Count -eq 0) {
        Write-Error "Žiadni používatelia neboli načítaní z AD!"
        exit 1
    }

    # Pridanie vlastnej vlastnosti CleanOU (iba časť od prvého OU=)
    $Users = $Users | Select-Object *, @{
        Name = "CleanOU"
        Expression = {
            # Nájdenie pozície prvého OU=
            $ouStart = $_.DistinguishedName.IndexOf("OU=")
            if ($ouStart -ge 0) {
                # Získanie časti od prvého OU=
                $cleanOU = $_.DistinguishedName.Substring($ouStart)
                # Odstránenie koncových častí ak existujú (ako DC=...)
                $cleanOU -replace ',DC=.*$',''
            } else {
                "N/A"
            }
        }
    }

    # Filtrovanie používateľov
    $ActiveUsers = $Users | Where-Object { $_.LastLogonDate -ge $LastLogonThreshold -and $_.Enabled }
    $InactiveUsers = $Users | Where-Object { $_.LastLogonDate -lt $LastLogonThreshold -and $_.Enabled }
    $DisabledUsers = $Users | Where-Object { -not $_.Enabled }

    # Vlastnosti pre export
    $SelectProperties = @('SamAccountName', 'DisplayName', 'LastLogonDate', 'Enabled', 'EmailAddress', 'CleanOU')

    # Vytvorenie listov v Exceli
    Add-Sheet "Aktívni užívatelia" ($ActiveUsers | Select-Object $SelectProperties)
    Add-Sheet "Neaktívni užívatelia" ($InactiveUsers | Select-Object $SelectProperties)
    Add-Sheet "Disabled užívatelia" ($DisabledUsers | Select-Object $SelectProperties)

    # Odstránenie prázdneho prvého listu
    $Workbook.Sheets.Item(4).Delete() | Out-Null

    # Uloženie a zatvorenie Excel súboru
    $Workbook.SaveAs($ExcelFile)
    Write-Host "Export do Excelu dokončený: $ExcelFile" -ForegroundColor Green
    Invoke-Item $ExcelFile  # Automatické otvorenie súboru
}
catch {
    Write-Error "Chyba pri spracovaní: $_"
}
finally {
    # Správne uvoľnenie COM objektov
    if ($Excel) {
        $Excel.Quit()
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($Excel) | Out-Null
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
    }
}