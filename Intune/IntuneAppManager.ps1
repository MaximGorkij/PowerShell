function Export-IntuneApps {
    param([string]$backupRoot = "\\nas03\LOG\BackupIntune")

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logPath = "$backupRoot\diff.log"
    Add-Content $logPath "`n===== Export: $timestamp ====="

    $apps = Get-MgDeviceAppManagementMobileApps
    foreach ($app in $apps) {
        $id = $app.Id
        $type = $app.'@odata.type' -replace "#microsoft.graph.", ""
        $folder = "$backupRoot\$type"
        if (!(Test-Path $folder)) { New-Item -ItemType Directory -Path $folder | Out-Null }

        $filePath = "$folder\$id.json"
        $json = $app | ConvertTo-Json -Depth 10
        $version = $app.version

        if (!(Test-Path $filePath)) {
            $json | Out-File $filePath
        } else {
            $oldJson = Get-Content $filePath -Raw
            if ($json -ne $oldJson) {
                $json | Out-File $filePath
                Add-Content $logPath "[$timestamp] $($app.displayName) | Typ: $type | Verzia: $version"
            }
        }
    }
}

function Restore-IntuneApps {
    param(
        [string]$backupRoot = "\\nas03\LOG\BackupIntune",
        [switch]$UpdateExisting
    )

    $folders = Get-ChildItem -Path $backupRoot -Directory
    foreach ($folder in $folders) {
        $jsonFiles = Get-ChildItem -Path $folder.FullName -Filter "*.json"
        foreach ($jsonFile in $jsonFiles) {
            $json = Get-Content $jsonFile.FullName -Raw
            $appData = $json | ConvertFrom-Json

            if (-not $appData.displayName -or -not $appData.'@odata.type') {
                Write-Host "❌ Chýba metadáta: $($jsonFile.Name)"
                continue
            }

            $existing = Get-MgDeviceAppManagementMobileApps | Where-Object { $_.displayName -eq $appData.displayName }
            if ($existing -and $UpdateExisting) {
                Update-MgDeviceAppManagementMobileApp -MobileAppId $existing.Id -BodyParameter $appData
            } elseif (-not $existing) {
                New-MgDeviceAppManagementMobileApp -BodyParameter $appData
            }
        }
    }
}

function Show-Gui {
    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction Stop

        [xml]$XAML = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Title="Intune Backup Tool" Height="400" Width="500">
    <Grid Margin="10">
        <StackPanel>
            <TextBlock FontSize="18" FontWeight="Bold" Margin="0,0,0,10">Intune Backup & Restore GUI</TextBlock>
            <Button Name="btnExport" Content="🔁 Export aplikácií" Height="30" Margin="0,0,0,5"/>
            <Button Name="btnRestore" Content="💾 Obnova aplikácií" Height="30" Margin="0,0,0,5"/>
            <TextBlock Name="txtStatus" FontSize="12" Margin="0,10,0,0" Foreground="Gray"/>
        </StackPanel>
    </Grid>
</Window>
"@

        $reader = (New-Object System.Xml.XmlNodeReader $XAML)
        $window = [Windows.Markup.XamlReader]::Load($reader)
        $btnExport = $window.FindName("btnExport")
        $btnRestore = $window.FindName("btnRestore")
        $txtStatus = $window.FindName("txtStatus")
        $backupRoot = "\\nas03\LOG\BackupIntune"

        $btnExport.Add_Click({
            Export-IntuneApps -backupRoot $backupRoot
            $txtStatus.Text = "📦 Export hotový"
        })

        $btnRestore.Add_Click({
            Restore-IntuneApps -backupRoot $backupRoot -UpdateExisting
            $txtStatus.Text = "🔄 Obnova hotová"
        })

        $window.ShowDialog() | Out-Null
        return $true
    }
    catch {
        Write-Host "⚠️ GUI nedostupné, prechod na textový režim..." -ForegroundColor Yellow
        return $false
    }
}

function SpustCli {
    $action = Read-Host "Zadaj akciu (export / obnova)"
    $backupRoot = "\\nas03\LOG\BackupIntune"

    switch ($action.ToLower()) {
        "export"  { Export-IntuneApps -backupRoot $backupRoot }
        "obnova"  { Restore-IntuneApps -backupRoot $backupRoot -UpdateExisting }
        default   { Write-Host "❓ Neznáma voľba. Skús >export< alebo >obnova<" }
    }
}

# ▶️ Spustenie
if (-not (Show-Gui)) {
    SpustCli
}