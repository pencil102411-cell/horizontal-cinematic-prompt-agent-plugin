[CmdletBinding()]
param(
    [ValidateSet('Preview', 'Apply')][string]$Mode = 'Preview',
    [Parameter(Mandatory = $true)][string]$BaseRoot,
    [Parameter(Mandatory = $true)][string]$ServiceDir,
    [Parameter(Mandatory = $true)][string]$MappingPath,
    [ValidateRange(0, 1000000)][int]$ExpectedCount = 0,
    [ValidateRange(0, 9223372036854775807)][long]$ExpectedBytes = 0,
    [ValidateRange(1, 300)][int]$StabilityWaitSeconds = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'VideoAutoRenamer.psm1'
Import-Module $modulePath -Force

$rootItem = Get-Item -LiteralPath $BaseRoot -Force
if (-not $rootItem.PSIsContainer) { throw "BaseRoot is not a directory: $BaseRoot" }
if (-not (Test-Path -LiteralPath $ServiceDir -PathType Container)) {
    throw "ServiceDir is not a directory: $ServiceDir"
}

$rootPath = $rootItem.FullName.TrimEnd([char[]]"\/")
$folderPathPattern = '^[^\\]+\\SP\d+\\第\d+场\\1080P\\\d{8}-V\d+\\SP-\d{4}(?:-\d+)*$'
$nameSuffixByResolution = @{ '1080P' = '-1080P' }

function Test-MigrationPlan {
    param([Parameter(Mandatory = $true)][object[]]$Plan)

    $targetPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($item in $Plan) {
        if (-not (Test-Path -LiteralPath $item.OldPath -PathType Leaf)) {
            throw "Source is missing: $($item.OldPath)"
        }
        $source = Get-Item -LiteralPath $item.OldPath -Force
        if (-not (Test-SupportedVideo -File $source)) {
            throw "Unsupported video extension: $($item.OldPath)"
        }
        if ([long]$source.Length -ne [long]$item.Length) {
            throw "Source length changed: $($item.OldPath)"
        }
        if (-not $source.FullName.StartsWith($rootPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Source is outside BaseRoot: $($item.OldPath)"
        }

        $relativeFolder = $source.Directory.FullName.Substring($rootPath.Length).TrimStart([char[]]"\/")
        $segments = @($relativeFolder -split '[\\/]')
        if ($segments -contains '粗剪') {
            throw "Rough-cut path is excluded: $($item.OldPath)"
        }
        if ($relativeFolder -notmatch $folderPathPattern) {
            throw "Source is outside the standard 1080P structure: $($item.OldPath)"
        }
        if ([string]$item.NewName -cnotmatch '-1080P\.[^.]+$') {
            throw "Target name lacks canonical -1080P suffix: $($item.NewName)"
        }
        if (-not $targetPaths.Add([string]$item.NewPath)) {
            throw "Duplicate target path: $($item.NewPath)"
        }
        if (Test-Path -LiteralPath $item.NewPath) {
            throw "Target already exists: $($item.NewPath)"
        }
    }
}

if ($Mode -eq 'Preview') {
    $observations = @{}
    [void]@(Get-RenamePlan `
        -Root $rootPath `
        -Observations $observations `
        -FolderDepth 6 `
        -FolderPathPattern $folderPathPattern `
        -NameSuffixByResolution $nameSuffixByResolution)
    Start-Sleep -Seconds $StabilityWaitSeconds
    $plan = @(Get-RenamePlan `
        -Root $rootPath `
        -Observations $observations `
        -FolderDepth 6 `
        -FolderPathPattern $folderPathPattern `
        -NameSuffixByResolution $nameSuffixByResolution)

    Test-MigrationPlan -Plan $plan
    $mappingDirectory = Split-Path -Parent $MappingPath
    if ([string]::IsNullOrWhiteSpace($mappingDirectory)) {
        throw "MappingPath must include a parent directory: $MappingPath"
    }
    if (-not (Test-Path -LiteralPath $mappingDirectory)) {
        New-Item -ItemType Directory -Path $mappingDirectory -Force | Out-Null
    }
    $temporaryMapping = Join-Path $mappingDirectory ('.preview-' + [guid]::NewGuid().ToString('N') + '.csv')
    try {
        $plan |
            Select-Object Folder, OldName, NewName, OldPath, NewPath, Length, Status |
            Export-Csv -LiteralPath $temporaryMapping -NoTypeInformation -Encoding UTF8
        Move-Item -LiteralPath $temporaryMapping -Destination $MappingPath -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryMapping) {
            Remove-Item -LiteralPath $temporaryMapping -Force
        }
    }

    [pscustomobject]@{
        Mode = 'Preview'
        Count = $plan.Count
        Bytes = [long](($plan | Measure-Object Length -Sum).Sum)
        MappingPath = $MappingPath
    }
    exit 0
}

if (-not (Test-Path -LiteralPath $MappingPath -PathType Leaf)) {
    throw "Mapping file is missing: $MappingPath"
}
$imported = @(Import-Csv -LiteralPath $MappingPath -Encoding UTF8)
if ($imported.Count -ne $ExpectedCount) {
    throw "ExpectedCount mismatch. Expected=$ExpectedCount; Actual=$($imported.Count)"
}
$actualBytes = [long](($imported | Measure-Object Length -Sum).Sum)
if ($actualBytes -ne $ExpectedBytes) {
    throw "ExpectedBytes mismatch. Expected=$ExpectedBytes; Actual=$actualBytes"
}

$plan = @(
    foreach ($row in $imported) {
        [pscustomobject]@{
            Folder = [string]$row.Folder
            OldName = [string]$row.OldName
            NewName = [string]$row.NewName
            OldPath = [string]$row.OldPath
            NewPath = [string]$row.NewPath
            Length = [long]$row.Length
            Status = 'Planned'
        }
    }
)
Test-MigrationPlan -Plan $plan
$renamed = @(Invoke-RenamePlan -Plan $plan -ServiceDir $ServiceDir)

[pscustomobject]@{
    Mode = 'Apply'
    Count = $renamed.Count
    Bytes = [long](($renamed | Measure-Object Length -Sum).Sum)
    MappingPath = $MappingPath
}
