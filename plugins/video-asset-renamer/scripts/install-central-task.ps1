[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BaseRoot,
    [Parameter(Mandatory = $true)][string]$ServiceDir,
    [string]$TaskName = 'VideoAssetRenamer-Central',
    [string]$RunnerPath = '',
    [string]$MutexName = 'Global\VideoAssetRenamer_Central'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RunnerPath)) {
    $RunnerPath = Join-Path $ServiceDir 'video-auto-renamer-central.ps1'
}

$requiredFiles = @(
    $RunnerPath,
    (Join-Path $ServiceDir 'VideoAutoRenamer.psm1'),
    (Join-Path $ServiceDir 'uninstall-central-task.ps1')
)
foreach ($path in $requiredFiles) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required service file is missing: $path"
    }
}
if (-not (Test-Path -LiteralPath $BaseRoot -PathType Container)) {
    throw "Monitored root is not accessible: $BaseRoot"
}

$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$powerShellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -BaseRoot "{1}" -ServiceDir "{2}" -IntervalSeconds 10 -MutexName "{3}"' -f $RunnerPath, $BaseRoot, $ServiceDir, $MutexName

$action = New-ScheduledTaskAction -Execute $powerShellExe -Argument $arguments
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $currentUser
$trigger.Delay = 'PT30S'
$recoveryTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 1) -RepetitionDuration (New-TimeSpan -Days 3650)
$settings = New-ScheduledTaskSettingsSet `
    -MultipleInstances IgnoreNew `
    -RestartCount 999 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -StartWhenAvailable `
    -ExecutionTimeLimit ([TimeSpan]::Zero)
$principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger @($trigger, $recoveryTrigger) -Settings $settings -Principal $principal -Force | Out-Null
Start-ScheduledTask -TaskName $TaskName
Start-Sleep -Seconds 2

$task = Get-ScheduledTask -TaskName $TaskName
$info = Get-ScheduledTaskInfo -TaskName $TaskName
[pscustomobject]@{
    TaskName = $task.TaskName
    State = $task.State
    User = $task.Principal.UserId
    Execute = $task.Actions.Execute
    Arguments = $task.Actions.Arguments
    LastRunTime = $info.LastRunTime
    LastTaskResult = $info.LastTaskResult
}
