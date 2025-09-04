$taskName = "PasswordCheckStartup"
$scriptPath = "C:\TaurisIT\skript\SetPasswords.ps1"
$pwshPath = "C:\Program Files\PowerShell\7\pwsh.exe"

# Vytvor Scheduled Task ak neexistuje
try {
    $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if (-not $existing) {
        $action = New-ScheduledTaskAction -Execute $pwshPath -Argument "-ExecutionPolicy Bypass -File `"$scriptPath`""
        $trigger = New-ScheduledTaskTrigger -AtStartup
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest

        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal
        Write-Output "Scheduled Task vytvoreny."
    } else {
        Write-Output "Scheduled Task uz existuje."
    }
} catch {
    Write-Output "Chyba pri vytvarani Scheduled Task: $_"
    exit 1
}