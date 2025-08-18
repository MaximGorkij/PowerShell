Import-Module -Name "$PSScriptRoot\SoftwareDetection.psm1"

$result = Detect-Software -Name "Zoom" -RequiredVersion "6.5.7.9933" -Mode "Requirement"

if ($result) {
    Write-Host "Podmienka splnená"
} else {
    Write-Host "Softvér nie je prítomný alebo nevyhovuje verziou"
}