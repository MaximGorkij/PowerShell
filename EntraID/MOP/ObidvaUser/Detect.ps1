$taskName = "PasswordCheckStartup"
$pwshPath = "C:\Program Files\PowerShell\7\pwsh.exe"

try {
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
    $action = $task.Actions | Where-Object { $_.Execute -eq $pwshPath }

    if ($action) {
        Write-Output "Installed"
        exit 0
    } else {
        Write-Output "Task exists but does not use PowerShell 7"
        exit 1
    }
} catch {
    Write-Output "Task not found"
    exit 1
}