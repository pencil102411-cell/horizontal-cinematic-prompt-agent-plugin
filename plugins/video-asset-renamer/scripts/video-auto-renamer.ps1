[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$ServiceDir,
    [ValidateRange(1, 86400)][int]$IntervalSeconds = 10,
    [ValidateRange(1, 32)][int]$FolderDepth = 1,
    [switch]$RunOnce,
    [string]$MutexName = 'Global\VideoAssetRenamer_SingleInstance'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$mutex = $null
$acquired = $false
try {
    $mutex = [System.Threading.Mutex]::new($false, $MutexName)
    try { $acquired = $mutex.WaitOne(0) }
    catch [System.Threading.AbandonedMutexException] { $acquired = $true }
    if (-not $acquired) { exit 0 }

    $modulePath = Join-Path $PSScriptRoot 'VideoAutoRenamer.psm1'
    Import-Module $modulePath -Force
    $observations = @{}

    Write-ServiceLog -ServiceDir $ServiceDir -Level 'INFO' -Message ("Service started. Root={0}; IntervalSeconds={1}; FolderDepth={2}; RunOnce={3}" -f $Root, $IntervalSeconds, $FolderDepth, [bool]$RunOnce)
    try {
        $recovered = Repair-RenameJournal -ServiceDir $ServiceDir
        if ($recovered -gt 0) {
            Write-ServiceLog -ServiceDir $ServiceDir -Level 'WARN' -Message ("Recovered {0} completed journal record(s)." -f $recovered)
        }
    }
    catch {
        Write-ServiceLog -ServiceDir $ServiceDir -Level 'ERROR' -Message ("Journal recovery failed: {0}" -f $_.Exception.Message)
    }

    do {
        try {
            $renamed = @(Invoke-RenameScan -Root $Root -Observations $observations -ServiceDir $ServiceDir -FolderDepth $FolderDepth)
            Write-ServiceLog -ServiceDir $ServiceDir -Level 'INFO' -Message ("Scan completed. Renamed={0}" -f $renamed.Count)
        }
        catch {
            try {
                Write-ServiceLog -ServiceDir $ServiceDir -Level 'ERROR' -Message ("Scan failed: {0}" -f $_.Exception.Message)
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
