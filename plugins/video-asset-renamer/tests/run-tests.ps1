$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\VideoAutoRenamer.psm1'
if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
    throw "MODULE_MISSING_EXPECTED: $modulePath"
}
Import-Module $modulePath -Force

$script:passed = 0

function Assert-Equal {
    param($Actual, $Expected, [string]$Name)
    if ($Actual -ne $Expected) {
        throw "ASSERT FAILED [$Name]: expected [$Expected], actual [$Actual]"
    }
    $script:passed++
}

function Assert-True {
    param([bool]$Condition, [string]$Name)
    if (-not $Condition) { throw "ASSERT FAILED [$Name]" }
    $script:passed++
}

function New-TestVideo {
    param([string]$Path, [int]$Length = 32)
    $bytes = New-Object byte[] $Length
    for ($i = 0; $i -lt $bytes.Length; $i++) { $bytes[$i] = [byte]($i % 251) }
    [System.IO.File]::WriteAllBytes($Path, $bytes)
}

$fixture = Join-Path $PSScriptRoot ('_tmp_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null

try {
    Assert-Equal (Get-LetterSuffix -Index 0) 'A' 'suffix A'
    Assert-Equal (Get-LetterSuffix -Index 25) 'Z' 'suffix Z'
    Assert-Equal (Get-LetterSuffix -Index 26) 'AA' 'suffix AA'
    Assert-Equal (Get-LetterSuffix -Index 27) 'AB' 'suffix AB'

    $sortFolder = Join-Path $fixture 'SORT'
    New-Item -ItemType Directory -Path $sortFolder | Out-Null
    New-TestVideo (Join-Path $sortFolder '10.mp4')
    New-TestVideo (Join-Path $sortFolder '2.mp4')
    $sorted = @(Get-ChildItem -LiteralPath $sortFolder -File | Sort-Object @{ Expression = { Get-NaturalSortKey -File $_ } })
    Assert-Equal $sorted[0].Name '2.mp4' 'natural sort 2 before 10'

    $root = Join-Path $fixture 'root'
    $shot = Join-Path $root 'SHOT-001'
    New-Item -ItemType Directory -Path $shot -Force | Out-Null
    New-TestVideo (Join-Path $shot 'SHOT-001-A.mp4')
    New-TestVideo (Join-Path $shot '2.mp4')
    New-TestVideo (Join-Path $shot '10.mp4')
    [System.IO.File]::WriteAllText((Join-Path $shot 'notes.txt'), 'ignore')
    New-TestVideo (Join-Path $root 'root-video.mp4')

    $state = @{}
    $first = @(Get-RenamePlan -Root $root -Observations $state)
    Assert-Equal $first.Count 0 'first observation waits'
    $second = @(Get-RenamePlan -Root $root -Observations $state)
    Assert-Equal $second.Count 2 'second unchanged observation plans two files'
    Assert-Equal $second[0].OldName '2.mp4' 'plan natural first'
    Assert-Equal $second[0].NewName 'SHOT-001-B.mp4' 'preserve existing A and allocate B'
    Assert-Equal $second[1].OldName '10.mp4' 'plan natural second'
    Assert-Equal $second[1].NewName 'SHOT-001-C.mp4' 'allocate C'
    Assert-True (Test-Path -LiteralPath (Join-Path $shot 'SHOT-001-A.mp4')) 'standardized file preserved during planning'
    Assert-True (Test-Path -LiteralPath (Join-Path $root 'root-video.mp4')) 'root video ignored'

    $depthRoot = Join-Path $fixture 'depth-root'
    $versionFolder = Join-Path $depthRoot '20260723-V01'
    $depthShot = Join-Path $versionFolder 'SP-0313'
    $tooDeep = Join-Path $depthShot 'backup'
    New-Item -ItemType Directory -Path $tooDeep -Force | Out-Null
    New-TestVideo (Join-Path $versionFolder 'version-direct.mp4') 35
    New-TestVideo (Join-Path $depthShot '1.mp4') 36
    New-TestVideo (Join-Path $depthShot '2.mp4') 37
    New-TestVideo (Join-Path $tooDeep 'too-deep.mp4') 38
    $depthState = @{}
    $depthFirst = @(Get-RenamePlan -Root $depthRoot -Observations $depthState -FolderDepth 2)
    Assert-Equal $depthFirst.Count 0 'depth-two first observation waits'
    $depthSecond = @(Get-RenamePlan -Root $depthRoot -Observations $depthState -FolderDepth 2)
    Assert-Equal $depthSecond.Count 2 'depth-two plans direct videos in material folder'
    Assert-Equal $depthSecond[0].NewName 'SP-0313-A.mp4' 'depth-two uses direct parent folder prefix'
    Assert-Equal $depthSecond[1].NewName 'SP-0313-B.mp4' 'depth-two allocates sequential suffix'
    Assert-True (Test-Path -LiteralPath (Join-Path $versionFolder 'version-direct.mp4')) 'depth-two ignores version-folder direct video'
    Assert-True (Test-Path -LiteralPath (Join-Path $tooDeep 'too-deep.mp4')) 'depth-two ignores deeper video'

    $lockRoot = Join-Path $fixture 'lock-root'
    $lockShot = Join-Path $lockRoot 'SHOT-LOCK'
    New-Item -ItemType Directory -Path $lockShot -Force | Out-Null
    $lockedPath = Join-Path $lockShot 'raw.mp4'
    New-TestVideo $lockedPath
    $lockState = @{}
    [void](Get-RenamePlan -Root $lockRoot -Observations $lockState)
    $stream = [System.IO.File]::Open($lockedPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    try {
        $lockedPlan = @(Get-RenamePlan -Root $lockRoot -Observations $lockState)
        Assert-Equal $lockedPlan.Count 0 'locked file skipped'
    }
    finally { $stream.Dispose() }
    $unlockedPlan = @(Get-RenamePlan -Root $lockRoot -Observations $lockState)
    Assert-Equal $unlockedPlan.Count 1 'released file retries without another change'
    Assert-Equal $unlockedPlan[0].NewName 'SHOT-LOCK-A.mp4' 'released file target'

    $txRoot = Join-Path $fixture 'tx-root'
    $txShot = Join-Path $txRoot 'SHOT-TX'
    $txService = Join-Path $fixture 'tx-service'
    New-Item -ItemType Directory -Path $txShot -Force | Out-Null
    New-TestVideo (Join-Path $txShot '1.mp4') 41
    New-TestVideo (Join-Path $txShot '2.mp4') 42
    $txState = @{}
    [void](Get-RenamePlan -Root $txRoot -Observations $txState)
    $txPlan = @(Get-RenamePlan -Root $txRoot -Observations $txState)
    $txResult = @(Invoke-RenamePlan -Plan $txPlan -ServiceDir $txService)
    Assert-Equal $txResult.Count 2 'transaction renamed two files'
    Assert-True (Test-Path -LiteralPath (Join-Path $txShot 'SHOT-TX-A.mp4')) 'transaction target A exists'
    Assert-True (Test-Path -LiteralPath (Join-Path $txShot 'SHOT-TX-B.mp4')) 'transaction target B exists'
    Assert-Equal (Get-Item -LiteralPath (Join-Path $txShot 'SHOT-TX-A.mp4')).Length 41 'transaction preserves A length'
    Assert-Equal (Get-Item -LiteralPath (Join-Path $txShot 'SHOT-TX-B.mp4')).Length 42 'transaction preserves B length'
    Assert-Equal @(Get-ChildItem -LiteralPath $txShot -File -Filter '.__video_auto_rename_*').Count 0 'transaction leaves no temp files'
    $journalPath = Join-Path $txService 'logs\rename-history.csv'
    $journal = @(Import-Csv -LiteralPath $journalPath -Encoding UTF8)
    Assert-Equal @($journal | Where-Object Status -eq 'Planned').Count 2 'journal planned rows'
    Assert-Equal @($journal | Where-Object Status -eq 'Completed').Count 2 'journal completed rows'
    $journalBytes = [System.IO.File]::ReadAllBytes($journalPath)
    Assert-True ($journalBytes.Length -ge 3 -and $journalBytes[0] -eq 0xEF -and $journalBytes[1] -eq 0xBB -and $journalBytes[2] -eq 0xBF) 'journal has UTF8 BOM'
    $afterState = @{}
    Assert-Equal @(Get-RenamePlan -Root $txRoot -Observations $afterState).Count 0 'second preview after transaction is empty'

    $rollbackRoot = Join-Path $fixture 'rollback-root'
    $rollbackShot = Join-Path $rollbackRoot 'SHOT-RB'
    $rollbackService = Join-Path $fixture 'rollback-service'
    New-Item -ItemType Directory -Path $rollbackShot -Force | Out-Null
    $rb1 = Join-Path $rollbackShot 'one.mp4'
    $rb2 = Join-Path $rollbackShot 'two.mp4'
    New-TestVideo $rb1 51
    New-TestVideo $rb2 52
    $manualPlan = @(
        [pscustomobject]@{ Folder='SHOT-RB'; OldName='one.mp4'; NewName='SHOT-RB-A.mp4'; OldPath=$rb1; NewPath=(Join-Path $rollbackShot 'SHOT-RB-A.mp4'); Length=51; Status='Planned' },
        [pscustomobject]@{ Folder='SHOT-RB'; OldName='two.mp4'; NewName='SHOT-RB-B.mp4'; OldPath=$rb2; NewPath=(Join-Path $rollbackShot 'SHOT-RB-B.mp4'); Length=52; Status='Planned' }
    )
    $rbLock = [System.IO.File]::Open($rb2, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    $rollbackFailed = $false
    try { [void](Invoke-RenamePlan -Plan $manualPlan -ServiceDir $rollbackService) }
    catch { $rollbackFailed = $true }
    finally { $rbLock.Dispose() }
    Assert-True $rollbackFailed 'locked batch fails'
    Assert-True (Test-Path -LiteralPath $rb1) 'rollback restores first original'
    Assert-True (Test-Path -LiteralPath $rb2) 'rollback keeps second original'
    Assert-Equal @(Get-ChildItem -LiteralPath $rollbackShot -File -Filter '.__video_auto_rename_*').Count 0 'rollback leaves no temp files'

    $recoverService = Join-Path $fixture 'recover-service'
    $recoverRoot = Join-Path $fixture 'recover-root'
    New-Item -ItemType Directory -Path $recoverRoot -Force | Out-Null
    $recoverOld = Join-Path $recoverRoot 'old.mp4'
    $recoverNew = Join-Path $recoverRoot 'new.mp4'
    New-TestVideo $recoverNew 61
    Write-JournalRecord -ServiceDir $recoverService -Record ([pscustomobject]@{
        Timestamp=(Get-Date).ToString('o'); BatchId='recover-batch'; Status='Planned'; Folder='RECOVER'
        OldName='old.mp4'; NewName='new.mp4'; OldPath=$recoverOld; NewPath=$recoverNew; Length=61; Message=''
    })
    $recovered = Repair-RenameJournal -ServiceDir $recoverService
    Assert-Equal $recovered 1 'journal recovery count'
    $recoverJournal = @(Import-Csv -LiteralPath (Join-Path $recoverService 'logs\rename-history.csv') -Encoding UTF8)
    Assert-Equal @($recoverJournal | Where-Object Status -eq 'RecoveredCompleted').Count 1 'journal recovery status'

    $logService = Join-Path $fixture 'log-service'
    $logDir = Join-Path $logService 'logs'
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    $logPath = Join-Path $logDir 'service.log'
    [System.IO.File]::WriteAllBytes($logPath, (New-Object byte[] (5MB)))
    Write-ServiceLog -ServiceDir $logService -Level 'INFO' -Message 'rotation-test'
    Assert-True (Test-Path -LiteralPath (Join-Path $logDir 'service.log.1')) 'log rotation backup exists'
    Assert-True ((Get-Item -LiteralPath $logPath).Length -lt 1MB) 'new log is small after rotation'

    $runnerPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\video-auto-renamer.ps1'
    if (-not (Test-Path -LiteralPath $runnerPath -PathType Leaf)) {
        throw "RUNNER_MISSING_EXPECTED: $runnerPath"
    }
    $runnerRoot = Join-Path $fixture 'runner-root'
    $runnerShot = Join-Path $runnerRoot 'SHOT-RUN'
    $runnerService = Join-Path $fixture 'runner-service'
    New-Item -ItemType Directory -Path $runnerShot -Force | Out-Null
    New-TestVideo (Join-Path $runnerShot 'SHOT-RUN-A.mp4') 71
    $runnerMutex = 'Global\VideoAssetRenamerTest_' + [guid]::NewGuid().ToString('N')
    $runnerOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runnerPath -Root $runnerRoot -ServiceDir $runnerService -IntervalSeconds 1 -RunOnce -MutexName $runnerMutex 2>&1
    Assert-Equal $LASTEXITCODE 0 'runner RunOnce exit code'
    $runnerLog = Join-Path $runnerService 'logs\service.log'
    Assert-True (Test-Path -LiteralPath $runnerLog) 'runner creates service log'
    $runnerLogText = Get-Content -Raw -Encoding UTF8 -LiteralPath $runnerLog
    Assert-True ($runnerLogText -match 'Service started') 'runner logs startup'
    Assert-True ($runnerLogText -match 'Scan completed') 'runner logs completed scan'
    Assert-True ($runnerLogText -match "`tINFO`t") 'runner log uses real tab separators'
    Assert-True (-not $runnerLogText.Contains('`t')) 'runner log has no literal backtick-t text'

    $blockedService = Join-Path $fixture 'blocked-runner-service'
    $readyFile = Join-Path $fixture 'mutex-ready.txt'
    $holder = Start-Job -ScriptBlock {
        param($Name, $Ready)
        $mutex = [Threading.Mutex]::new($false, $Name)
        [void]$mutex.WaitOne()
        [System.IO.File]::WriteAllText($Ready, 'ready')
        try { Start-Sleep -Seconds 8 }
        finally { $mutex.ReleaseMutex(); $mutex.Dispose() }
    } -ArgumentList $runnerMutex, $readyFile
    $deadline = (Get-Date).AddSeconds(5)
    while (-not (Test-Path -LiteralPath $readyFile)) {
        if ((Get-Date) -gt $deadline) { throw 'Mutex holder did not become ready.' }
        Start-Sleep -Milliseconds 100
    }
    try {
        $blockedOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runnerPath -Root $runnerRoot -ServiceDir $blockedService -IntervalSeconds 1 -RunOnce -MutexName $runnerMutex 2>&1
        Assert-Equal $LASTEXITCODE 0 'duplicate runner exits cleanly'
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $blockedService 'logs\service.log'))) 'duplicate runner does not scan or log'
    }
    finally {
        Stop-Job -Job $holder -ErrorAction SilentlyContinue
        Remove-Job -Job $holder -Force -ErrorAction SilentlyContinue
    }

    Write-Output "PASS: $script:passed assertions"
}
finally {
    if (Test-Path -LiteralPath $fixture) {
        Remove-Item -LiteralPath $fixture -Recurse -Force
    }
}
