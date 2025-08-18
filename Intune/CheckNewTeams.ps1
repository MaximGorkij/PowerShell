<# 
.SYNOPSIS 
Detect New Microsoft Teams App on target devices 
.DESCRIPTION 
Below script will detect if New MS Teams App is installed.
 
.NOTES     
        Name       : New MS Teams Detection Script
        Author     : Jatin Makhija  
        Version    : 1.0.1  
        DateUpdated: 06-Dec-2024
        Blog       : https://cloudinfra.net
         
.LINK 
https://cloudinfra.net 
#>
$datum = get-date -format "yyyy-MM-dd_HH.mm"
Add-Content -Path "C:\Windows\Temp\teams.log" -Value $datum
$oldteams = Get-ItemProperty -Path HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | Where-Object { $_.DisplayName -like "Teams*" }

if ($oldteams) {
    & 'MsiExec.exe /I{731F6BAA-A986-45A4-8936-7C3AAAAA760B} /qn'
    Add-Content -Path "C:\Windows\Temp\teams.log" -Value "Old Teams sa nasiel"
}

$oldteams = Get-ItemProperty -Path HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | Where-Object { $_.DisplayName -like "Teams*" }
if ($oldteams){
    Add-Content -Path "C:\Windows\Temp\teams.log" -Value "Old Teams je stale tu"
    exit 1
}

# Define the path where New Microsoft Teams is installed
$teamsPath = "C:\Program Files\WindowsApps"

# Define the filter pattern for Microsoft Teams installer
$teamsInstallerName = "MSTeams_*"

# Retrieve items in the specified path matching the filter pattern
$teamsNew = Get-ChildItem -Path $teamsPath -Filter $teamsInstallerName -ErrorAction SilentlyContinue

# Check if Microsoft Teams is listed in Appx packages
$teamsAppx = Get-AppxPackage -AllUsers | Where-Object { $_.Name -like "*Teams*" }


# Evaluate both conditions to determine if Microsoft Teams is installed
if ($teamsNew -and $teamsAppx) {
    # Display message if Microsoft Teams is found
    Add-Content -Path "C:\Windows\Temp\teams.log" -Value "Microsoft Teams client is installed."
    exit 0
} else {
    # Display message if Microsoft Teams is not found
    Add-Content -Path "C:\Windows\Temp\teams.log" -Value "Microsoft Teams client not found."
    exit 1
}
Add-Content -Path "C:\Windows\Temp\teams.log" -Value "..."