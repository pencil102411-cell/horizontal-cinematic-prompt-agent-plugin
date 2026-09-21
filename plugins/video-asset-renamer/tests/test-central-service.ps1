$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$script:assertions = 0
function Assert-True {
    param([bool]$Condition, [string]$Message)
    $script:assertions++
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$scriptRoot = Join-Path $projectRoot 'scripts'
$modulePath = Join-Path $scriptRoot 'VideoAutoRenamer.psm1'
$runnerPath = Join-Path $scriptRoot 'video-auto-renamer-central.ps1'
$installerPath = Join-Path $scriptRoot 'install-central-task.ps1'

Assert-True (Test-Path -LiteralPath $runnerPath -PathType Leaf) 'central runner exists'
Assert-True (Test-Path -LiteralPath $installerPath -PathType Leaf) 'central installer exists'

$runnerText = Get-Content -LiteralPath $runnerPath -Raw
$installerText = Get-Content -LiteralPath $installerPath -Raw
Assert-True ($runnerText -match "480P") 'runner includes 480P'
Assert-True ($runnerText -match "720P") 'runner includes 720P'
Assert-True ($runnerText -match "1080P") 'runner includes 1080P'
Assert-True ($runnerText -match 'FolderDepths') 'runner supports both legacy and categorized folder depths'
Assert-True ($runnerText -match 'FolderPathPattern') 'runner applies folder path allowlist'
Assert-True ($installerText -match 'MultipleInstances IgnoreNew') 'installer keeps a single task instance'
Assert-True ($installerText -match 'RepetitionInterval \(New-TimeSpan -Minutes 1\)') 'installer has recovery trigger'
Assert-True ($installerText -match 'IntervalSeconds 10') 'installer uses ten-second scans'

Import-Module $modulePath -Force
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('central-renamer-test-' + [guid]::NewGuid().ToString('N'))
try {
    $eligible480 = Join-Path $testRoot '项目A\SP04\第1场\480P\20260725-V01\SP-0401-1-3'
    $eligible1080 = Join-Path $testRoot '项目A\SP04\第1场\1080P\20260725-V01\SP-0401-4'
    $eligible1080Lower = Join-Path $testRoot '项目A\SP04\第1场\1080p\20260725-V01\SP-0401-5'
    $categorized1080 = Join-Path $testRoot '分类批次A\项目B\SP01\第1场\1080P\20260725-V01\SP-0101-1'
    $conflicting1080 = Join-Path $testRoot '项目A\SP04\第1场\1080P\20260725-V01\SP-0401-7'
    $rough = Join-Path $testRoot '项目A\SP04\第1场\480P\20260725-V01\粗剪'
    $unsupportedResolution = Join-Path $testRoot '项目A\SP04\第1场\2160P\20260725-V01\SP-0401-6'
    $archive = Join-Path $testRoot '项目A\成片\版本\其他\目录\SP-9999-1'
    foreach ($folder in @($eligible480, $eligible1080, $eligible1080Lower, $categorized1080, $conflicting1080, $rough, $unsupportedResolution, $archive)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        [IO.File]::WriteAllBytes((Join-Path $folder 'source.mp4'), [byte[]](1, 2, 3))
    }
    [IO.File]::WriteAllBytes((Join-Path $eligible480 'source2.mov'), [byte[]](4, 5, 6))
    [IO.File]::WriteAllBytes((Join-Path $eligible1080 'SP-0401-4-B.mp4'), [byte[]](7, 8, 9))
    [IO.File]::WriteAllBytes((Join-Path $eligible1080 'SP-0401-4-C-1080P.mp4'), [byte[]](10, 11, 12))
    [IO.File]::WriteAllBytes((Join-Path $conflicting1080 'SP-0401-7-A.mp4'), [byte[]](13, 14, 15))
    [IO.File]::WriteAllBytes((Join-Path $conflicting1080 'SP-0401-7-A-1080P.mp4'), [byte[]](13, 14, 15))

    $observations = @{}
    $pathPattern = '^(?:[^\\]+\\)?[^\\]+\\SP\d+\\第\d+场\\(?:480P|720P|1080P)\\\d{8}-V\d+\\SP-\d{4}(?:-\d+)*$'
    $nameSuffixes = @{ '1080P' = '-1080P' }
    $skippedFolders = New-Object System.Collections.ArrayList
    $first = @(Get-RenamePlan -Root $testRoot -Observations $observations -FolderDepths @(6, 7) -FolderPathPattern $pathPattern -NameSuffixByResolution $nameSuffixes -SkipDuplicateSuffixFolders -SkippedFolders $skippedFolders)
    Assert-True ($first.Count -eq 0) 'first observation round does not rename'
    $skippedFolders.Clear()
    $second = @(Get-RenamePlan -Root $testRoot -Observations $observations -FolderDepths @(6, 7) -FolderPathPattern $pathPattern -NameSuffixByResolution $nameSuffixes -SkipDuplicateSuffixFolders -SkippedFolders $skippedFolders)
    Assert-True ($second.Count -eq 6) 'eligible legacy and categorized files produce rename plans'
    Assert-True (@($second | Where-Object NewName -eq 'SP-0401-1-3-A.mp4').Count -eq 1) '480P first suffix is A'
    Assert-True (@($second | Where-Object NewName -eq 'SP-0401-1-3-B.mov').Count -eq 1) '480P second suffix is B'
    Assert-True (@($second | Where-Object NewName -eq 'SP-0401-4-A-1080P.mp4').Count -eq 1) 'new 1080P file receives suffix'
    Assert-True (@($second | Where-Object NewName -eq 'SP-0401-4-B-1080P.mp4').Count -eq 1) 'legacy standard 1080P file is migrated'
    Assert-True (@($second | Where-Object NewName -eq 'SP-0401-4-C-1080P.mp4').Count -eq 0) 'tagged 1080P file is skipped'
    Assert-True (@($second | Where-Object NewName -eq 'SP-0401-5-A-1080P.mp4').Count -eq 1) 'lowercase 1080p receives canonical suffix'
    Assert-True (@($second | Where-Object NewName -eq 'SP-0101-1-A-1080P.mp4').Count -eq 1) 'categorized 1080P receives canonical suffix'
    Assert-True (@($second | Where-Object NewName -like '*-1080P-1080P.*').Count -eq 0) 'suffix is never duplicated'
    Assert-True (@($second | Where-Object Folder -eq '粗剪').Count -eq 0) 'rough cut is excluded'
    Assert-True (@($second | Where-Object Folder -eq 'SP-0401-6').Count -eq 0) '2160P is excluded'
    Assert-True (@($second | Where-Object Folder -eq 'SP-9999-1').Count -eq 0) 'unstructured archive is excluded'
    Assert-True (@($second | Where-Object Folder -eq 'SP-0401-7').Count -eq 0) 'duplicate suffix folder is skipped'
    Assert-True ($skippedFolders.Count -eq 1) 'one duplicate suffix folder is reported'
    Assert-True ($skippedFolders[0].FolderPath -eq $conflicting1080) 'reported skip identifies conflicting folder'
    Assert-True ($skippedFolders[0].Reason -match 'Duplicate suffix.*A') 'reported skip includes duplicate suffix reason'
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}

"PASS: $script:assertions central-service assertions"
