#requires -Modules ImportExcel, ActiveDirectory

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# === GUI ===
$form = New-Object System.Windows.Forms.Form
$form.Text = "Audit Windows Share"
$form.Size = New-Object System.Drawing.Size(400, 400)
$form.StartPosition = "CenterScreen"

$lblPath = New-Object System.Windows.Forms.Label
$lblPath.Text = "UNC Cesta (napr. \\server\share):"
$lblPath.Location = New-Object System.Drawing.Point(10, 20)
$lblPath.AutoSize = $true
$form.Controls.Add($lblPath)

$txtPath = New-Object System.Windows.Forms.TextBox
$txtPath.Size = New-Object System.Drawing.Size(350, 20)
$txtPath.Location = New-Object System.Drawing.Point(10, 40)
$form.Controls.Add($txtPath)

$lblOU = New-Object System.Windows.Forms.Label
$lblOU.Text = "LDAP OU (napr. OU=Users,DC=contoso,DC=local):"
$lblOU.Location = New-Object System.Drawing.Point(10, 70)
$lblOU.AutoSize = $true
$form.Controls.Add($lblOU)

$txtOU = New-Object System.Windows.Forms.TextBox
$txtOU.Size = New-Object System.Drawing.Size(350, 20)
$txtOU.Location = New-Object System.Drawing.Point(10, 90)
$form.Controls.Add($txtOU)

$lblRights = New-Object System.Windows.Forms.Label
$lblRights.Text = "Povolené práva (napr. Modify,FullControl):"
$lblRights.Location = New-Object System.Drawing.Point(10, 120)
$lblRights.AutoSize = $true
$form.Controls.Add($lblRights)

$txtRights = New-Object System.Windows.Forms.TextBox
$txtRights.Size = New-Object System.Drawing.Size(350, 20)
$txtRights.Location = New-Object System.Drawing.Point(10, 140)
$form.Controls.Add($txtRights)

$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Text = "Spustiť Audit"
$btnRun.Location = New-Object System.Drawing.Point(10, 180)
$form.Controls.Add($btnRun)

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = "Zavrieť"
$btnCancel.Location = New-Object System.Drawing.Point(150, 180)
$form.Controls.Add($btnCancel)

$btnCancel.Add_Click({ $form.Close() })

$btnRun.Add_Click({
    $global:SharePath = $txtPath.Text
    $global:OU = $txtOU.Text
    $global:Rights = $txtRights.Text -split "," | ForEach-Object { $_.Trim() }
    $form.Close()
})

$form.ShowDialog()

# Over, ci bola zadana cesta
if (-not $SharePath -or -not $OU -or -not $Rights) {
    Write-Host "Zadanie neúplné. Ukončujem skript."
    return
}

# === Zvyšok hlavného skriptu ===
. "C:\Users\findrik\OneDrive - Tauris, a.s\Documents\PowerShell\AD\AuditShareCore.ps1" -SharePath $SharePath -OU $OU -Rights $Rights