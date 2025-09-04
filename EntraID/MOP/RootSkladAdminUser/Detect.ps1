<#
.SYNOPSIS
    Detekcia skriptu na kontrolu a zmenu hesla pre root, admin a sklad

.DESCRIPTION
    Overi, ci hesla su take ako by mali byt nastavene

.AUTHOR
    Marek Findrik

.CREATED
    2025-09-04

.VERSION
    1.1

.NOTES
    .
#>


$ScriptPath = "C:\TaurisIT\skript\SetPassword.ps1"
if (Test-Path $ScriptPath) {
    Write-Output "Installed"
    exit 0
}
else {
    Write-Output "Not Installed"
    exit 1
}