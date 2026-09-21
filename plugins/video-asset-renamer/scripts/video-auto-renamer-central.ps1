[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BaseRoot,
    [Parameter(Mandatory = $true)][string]$ServiceDir,
    [ValidateRange(1, 86400)][int]$IntervalSeconds = 10,
    [string[]]$Resolutions = @('480P', '720P', '1080P'),
    [switch]$RunOnce,
    [string]$MutexName = 'Global\LPVideoAutoRenamer_Central'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resolutionPattern = ($Resolutions | ForEach-Object { [regex]::Escape($_) }) -join '|'
$folderPathPattern = '^(?:[^\\]+\\)?[^\\]+\\SP\d+\\第\d+场\\(?:' + $resolutionPattern + ')\\\d{8}-V\d+\\SP-\d{4}(?:-\d+)*$'
$mutex = $null
$acquired = $false
$nameSuffixByResolution = @{ '1080P' = '-1080P' }

try {
    $mutex = [System.Threading.Mutex]::new($false, $MutexName)
    try { $acquired = $mutex.WaitOne(0) }
    catch [System.Threading.AbandonedMutexException] { $acquired = $true }
    if (-not $acquired) { exit 0 }

    $modulePath = Join-Path $PSScriptRoot 'VideoAutoRenamer.psm1'
    Import-Module $modulePath -Force
    $observations = @{}
    $reportedSkippedFolders = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    Write-ServiceLog -ServiceDir $ServiceDir -Level 'INFO' -Message (
        "Central service started. BaseRoot={0}; IntervalSeconds={1}; Resolutions={2}" -f
        $BaseRoot, $IntervalSeconds, ($Resolutions -join ',')
    )
    try {
        $recovered = Repair-RenameJournal -ServiceDir $ServiceDir
        if ($recovered -gt 0) {
            Write-ServiceLog -ServiceDir $ServiceDir -Level 'WARN' -Message (
                "Recovered {0} completed journal record(s)." -f $recovered
            )
        }
    }
    catch {
        Write-ServiceLog -ServiceDir $ServiceDir -Level 'ERROR' -Message (
            "Journal recovery failed: {0}" -f $_.Exception.Message
        )
    }

    do {
        try {
            $skippedFolders = New-Object System.Collections.ArrayList
            $renamed = @(
                Invoke-RenameScan `
                    -Root $BaseRoot `
                    -Observations $observations `
                    -ServiceDir $ServiceDir `
                    -FolderDepths @(6, 7) `
                    -FolderPathPattern $folderPathPattern `
                    -NameSuffixByResolution $nameSuffixByResolution `
                    -SkipDuplicateSuffixFolders `
                    -SkippedFolders $skippedFolders
            )
            $currentlySkipped = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($skipped in $skippedFolders) {
                [void]$currentlySkipped.Add([string]$skipped.FolderPath)
                if ($reportedSkippedFolders.Add([string]$skipped.FolderPath)) {
                    Write-ServiceLog -ServiceDir $ServiceDir -Level 'WARN' -Message (
                        "Skipped folder. {0}" -f $skipped.Reason
                    )
                }
            }
            foreach ($reportedPath in @($reportedSkippedFolders)) {
                if (-not $currentlySkipped.Contains($reportedPath)) {
                    [void]$reportedSkippedFolders.Remove($reportedPath)
                }
            }
            Write-ServiceLog -ServiceDir $ServiceDir -Level 'INFO' -Message (
                "Central scan completed. Renamed={0}; SkippedConflicts={1}" -f $renamed.Count, $skippedFolders.Count
            )
        }
        catch {
            try {
                Write-ServiceLog -ServiceDir $ServiceDir -Level 'ERROR' -Message (
                    "Central scan failed: {0}" -f $_.Exception.Message
                )
            }
            catch { }
        }

        if ($RunOnce) { break }
        Start-Sleep -Seconds $IntervalSeconds
    } while ($true)
}
finally {
    if ($acquired -and $null -ne $mutex) {
        try { $mutex.ReleaseMutex() } catch { }
    }
    if ($null -ne $mutex) { $mutex.Dispose() }
}
