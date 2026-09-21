Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:SupportedExtensions = @{
    '.mp4' = $true
    '.mov' = $true
    '.mkv' = $true
    '.avi' = $true
    '.wmv' = $true
    '.m4v' = $true
    '.webm' = $true
    '.flv' = $true
    '.mts' = $true
    '.m2ts' = $true
}

function Test-SupportedVideo {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][System.IO.FileInfo]$File)

    return $script:SupportedExtensions.ContainsKey($File.Extension.ToLowerInvariant())
}

function Get-LetterSuffix {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][int]$Index)

    if ($Index -lt 0) { throw 'Index must be zero or greater.' }
    $value = $Index + 1
    $result = ''
    while ($value -gt 0) {
        $value--
        $result = ([char](65 + ($value % 26))) + $result
        $value = [int][math]::Floor($value / 26)
    }
    return $result
}

function Get-NaturalSortKey {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][System.IO.FileInfo]$File)

    return [regex]::Replace(
        $File.Name.ToLowerInvariant(),
        '\d+',
        { param($match) $match.Value.PadLeft(20, '0') }
    )
}

function Test-ExclusiveAccess {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = $null
    try {
        $stream = [System.IO.File]::Open(
            $Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None
        )
        return $true
    }
    catch {
        return $false
    }
    finally {
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

function Get-RenamePlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][hashtable]$Observations,
        [ValidateRange(1, 32)][int]$FolderDepth = 1,
        [int[]]$FolderDepths = @(),
        [string]$FolderPathPattern = '',
        [hashtable]$NameSuffixByResolution = @{},
        [switch]$SkipDuplicateSuffixFolders,
        [System.Collections.IList]$SkippedFolders = $null
    )

    $rootItem = Get-Item -LiteralPath $Root -Force
    if (-not $rootItem.PSIsContainer) { throw "Root is not a directory: $Root" }

    $plans = New-Object System.Collections.Generic.List[object]
    $seenCandidates = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $targetPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $rootPath = $rootItem.FullName.TrimEnd([char[]]"\/")
    $requestedDepths = if ($FolderDepths.Count -gt 0) {
        @($FolderDepths | Sort-Object -Unique)
    }
    else {
        @($FolderDepth)
    }
    foreach ($requestedDepth in $requestedDepths) {
        if ($requestedDepth -lt 1 -or $requestedDepth -gt 32) {
            throw "Folder depth must be between 1 and 32: $requestedDepth"
        }
    }
    $maximumDepth = [int](($requestedDepths | Measure-Object -Maximum).Maximum)
    $foldersAtRequestedDepths = New-Object System.Collections.Generic.List[System.IO.DirectoryInfo]
    $foldersAtCurrentDepth = @($rootItem)
    for ($depth = 1; $depth -le $maximumDepth; $depth++) {
        $foldersAtNextDepth = New-Object System.Collections.Generic.List[System.IO.DirectoryInfo]
        foreach ($parentFolder in $foldersAtCurrentDepth) {
            foreach ($childFolder in @(Get-ChildItem -LiteralPath $parentFolder.FullName -Directory -Force)) {
                if ($childFolder.Name -in @('_自动重命名服务', '_视频自动重命名总工具')) { continue }
                $foldersAtNextDepth.Add($childFolder)
            }
        }
        if ($requestedDepths -contains $depth) {
            foreach ($requestedFolder in $foldersAtNextDepth) {
                $foldersAtRequestedDepths.Add($requestedFolder)
            }
        }
        $foldersAtCurrentDepth = @($foldersAtNextDepth)
    }
    $folders = @($foldersAtRequestedDepths | Sort-Object FullName)

    foreach ($folder in $folders) {
        $relativePath = $folder.FullName.Substring($rootPath.Length).TrimStart([char[]]"\/")
        if (-not [string]::IsNullOrWhiteSpace($FolderPathPattern)) {
            if ($relativePath -notmatch $FolderPathPattern) { continue }
        }

        $segments = @($relativePath -split '[\\/]')
        $resolution = if ($segments.Count -ge 3) { $segments[$segments.Count - 3] } else { '' }
        $nameSuffix = ''
        if ($NameSuffixByResolution.ContainsKey($resolution)) {
            $nameSuffix = [string]$NameSuffixByResolution[$resolution]
        }

        try {
            $videos = @(
                Get-ChildItem -LiteralPath $folder.FullName -File -Force -ErrorAction Stop |
                    Where-Object { Test-SupportedVideo -File $_ }
            )
        }
        catch {
            $reason = "Cannot enumerate folder $($folder.FullName): $($_.Exception.Message)"
            if ($null -ne $SkippedFolders) {
                [void]$SkippedFolders.Add([pscustomobject]@{
                    FolderPath = $folder.FullName
                    Reason = $reason
                })
            }
            continue
        }
        if ($videos.Count -eq 0) { continue }

        $legacyPattern = '^' + [regex]::Escape($folder.Name) + '-(?<suffix>[A-Z]+)$'
        $taggedPattern = '^' + [regex]::Escape($folder.Name) + '-(?<suffix>[A-Z]+)' + [regex]::Escape($nameSuffix) + '$'
        $used = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        $candidates = New-Object System.Collections.Generic.List[object]
        $duplicateSuffix = $null

        foreach ($video in $videos) {
            if (-not [string]::IsNullOrEmpty($nameSuffix) -and $video.BaseName -cmatch $taggedPattern) {
                $suffix = $Matches['suffix']
                if (-not $used.Add($suffix)) {
                    $duplicateSuffix = $suffix
                    break
                }
            }
            elseif ($video.BaseName -cmatch $legacyPattern) {
                $suffix = $Matches['suffix']
                if (-not $used.Add($suffix)) {
                    $duplicateSuffix = $suffix
                    break
                }
                if (-not [string]::IsNullOrEmpty($nameSuffix)) {
                    $candidates.Add([pscustomobject]@{ Video = $video; FixedSuffix = $suffix })
                }
            }
            else {
                $candidates.Add([pscustomobject]@{ Video = $video; FixedSuffix = $null })
            }
        }

        if ($null -ne $duplicateSuffix) {
            $reason = "Duplicate suffix in folder $($folder.FullName): $duplicateSuffix"
            if (-not $SkipDuplicateSuffixFolders) { throw $reason }
            if ($null -ne $SkippedFolders) {
                [void]$SkippedFolders.Add([pscustomobject]@{
                    FolderPath = $folder.FullName
                    Reason = $reason
                })
            }
            continue
        }

        if ($candidates.Count -eq 0) { continue }
        $folderReady = $true

        foreach ($candidate in $candidates) {
            $video = $candidate.Video
            [void]$seenCandidates.Add($video.FullName)
            $snapshot = [pscustomobject]@{
                Length = $video.Length
                LastWriteTimeUtcTicks = $video.LastWriteTimeUtc.Ticks
            }
            $previous = $Observations[$video.FullName]
            if ($null -eq $previous -or
                $previous.Length -ne $snapshot.Length -or
                $previous.LastWriteTimeUtcTicks -ne $snapshot.LastWriteTimeUtcTicks) {
                $Observations[$video.FullName] = $snapshot
                $folderReady = $false
                continue
            }
            if (-not (Test-ExclusiveAccess -Path $video.FullName)) {
                $folderReady = $false
            }
        }

        if (-not $folderReady) { continue }

        $ordered = @(
            $candidates |
                Sort-Object @{ Expression = { Get-NaturalSortKey -File $_.Video } }, @{ Expression = { $_.Video.Name.ToLowerInvariant() } }
        )
        $index = 0
        foreach ($candidate in $ordered) {
            $video = $candidate.Video
            if ($null -ne $candidate.FixedSuffix) {
                $suffix = [string]$candidate.FixedSuffix
            }
            else {
                do {
                    $suffix = Get-LetterSuffix -Index $index
                    $index++
                } while ($used.Contains($suffix))
                [void]$used.Add($suffix)
            }
            $newName = $folder.Name + '-' + $suffix + $nameSuffix + $video.Extension
            $newPath = Join-Path $folder.FullName $newName
            if (-not $targetPaths.Add($newPath)) { throw "Duplicate target path: $newPath" }
            if (Test-Path -LiteralPath $newPath) { throw "Target already exists: $newPath" }

            $plans.Add([pscustomobject]@{
                Folder = $folder.Name
                OldName = $video.Name
                NewName = $newName
                OldPath = $video.FullName
                NewPath = $newPath
                Length = $video.Length
                Status = 'Planned'
            })
        }
    }

    foreach ($key in @($Observations.Keys)) {
        if (-not $seenCandidates.Contains([string]$key)) { $Observations.Remove($key) }
    }

    return $plans
}

function Write-ServiceLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ServiceDir,
        [Parameter(Mandatory = $true)][string]$Level,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $logDir = Join-Path $ServiceDir 'logs'
    if (-not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    $logPath = Join-Path $logDir 'service.log'
    $backupPath = Join-Path $logDir 'service.log.1'
    if ((Test-Path -LiteralPath $logPath) -and (Get-Item -LiteralPath $logPath).Length -ge 5MB) {
        if (Test-Path -LiteralPath $backupPath) { Remove-Item -LiteralPath $backupPath -Force }
        Move-Item -LiteralPath $logPath -Destination $backupPath
    }

    $line = "{0}`t{1}`t{2}{3}" -f (Get-Date).ToString('o'), $Level.ToUpperInvariant(), $Message, [Environment]::NewLine
    [System.IO.File]::AppendAllText($logPath, $line, [System.Text.UTF8Encoding]::new($true))
}

function Write-JournalRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ServiceDir,
        [Parameter(Mandatory = $true)][object]$Record
    )

    $logDir = Join-Path $ServiceDir 'logs'
    if (-not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    $journalPath = Join-Path $logDir 'rename-history.csv'
    $normalized = [pscustomobject][ordered]@{
        Timestamp = [string]$Record.Timestamp
        BatchId = [string]$Record.BatchId
        Status = [string]$Record.Status
        Folder = [string]$Record.Folder
        OldName = [string]$Record.OldName
        NewName = [string]$Record.NewName
        OldPath = [string]$Record.OldPath
        NewPath = [string]$Record.NewPath
        Length = [string]$Record.Length
        Message = [string]$Record.Message
    }

    if (-not (Test-Path -LiteralPath $journalPath)) {
        $lines = @($normalized | ConvertTo-Csv -NoTypeInformation)
        [System.IO.File]::WriteAllLines($journalPath, $lines, [System.Text.UTF8Encoding]::new($true))
    }
    else {
        $dataLine = @($normalized | ConvertTo-Csv -NoTypeInformation | Select-Object -Skip 1)
        $appendText = [string]::Join([Environment]::NewLine, $dataLine) + [Environment]::NewLine
        [System.IO.File]::AppendAllText($journalPath, $appendText, [System.Text.UTF8Encoding]::new($false))
    }
}

function New-JournalRecord {
    param(
        [object]$Item,
        [string]$BatchId,
        [string]$Status,
        [string]$Message = ''
    )

    return [pscustomobject]@{
        Timestamp = (Get-Date).ToString('o')
        BatchId = $BatchId
        Status = $Status
        Folder = [string]$Item.Folder
        OldName = [string]$Item.OldName
        NewName = [string]$Item.NewName
        OldPath = [string]$Item.OldPath
        NewPath = [string]$Item.NewPath
        Length = [string]$Item.Length
        Message = $Message
    }
}

function Repair-RenameJournal {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$ServiceDir)

    $journalPath = Join-Path (Join-Path $ServiceDir 'logs') 'rename-history.csv'
    if (-not (Test-Path -LiteralPath $journalPath)) { return 0 }

    $records = @(Import-Csv -LiteralPath $journalPath -Encoding UTF8)
    $recovered = 0
    $groups = @($records | Group-Object { $_.BatchId + '|' + $_.OldPath })
    foreach ($group in $groups) {
        $last = $group.Group[-1]
        if ($last.Status -ne 'Planned') { continue }

        $oldExists = Test-Path -LiteralPath $last.OldPath -PathType Leaf
        $newExists = Test-Path -LiteralPath $last.NewPath -PathType Leaf
        if ($newExists -and -not $oldExists) {
            $status = 'RecoveredCompleted'
            $message = 'New path exists and old path is absent.'
            $recovered++
        }
        elseif ($oldExists -and -not $newExists) {
            $status = 'RecoveredNotApplied'
            $message = 'Old path exists and new path is absent.'
        }
        else {
            $status = 'RecoveryConflict'
            $message = 'Disk state is ambiguous; no file operation performed.'
        }
        Write-JournalRecord -ServiceDir $ServiceDir -Record ([pscustomobject]@{
            Timestamp = (Get-Date).ToString('o')
            BatchId = $last.BatchId
            Status = $status
            Folder = $last.Folder
            OldName = $last.OldName
            NewName = $last.NewName
            OldPath = $last.OldPath
            NewPath = $last.NewPath
            Length = $last.Length
            Message = $message
        })
    }
    return $recovered
}

function Invoke-RenamePlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Plan,
        [Parameter(Mandatory = $true)][string]$ServiceDir
    )

    if ($Plan.Count -eq 0) { return @() }

    $targets = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($item in $Plan) {
        if (-not (Test-Path -LiteralPath $item.OldPath -PathType Leaf)) {
            throw "Source file no longer exists: $($item.OldPath)"
        }
        if (-not $targets.Add([string]$item.NewPath)) { throw "Duplicate target path: $($item.NewPath)" }
        if (Test-Path -LiteralPath $item.NewPath) { throw "Target already exists: $($item.NewPath)" }
    }

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($folderGroup in @($Plan | Group-Object Folder)) {
        $batchId = [guid]::NewGuid().ToString('N')
        foreach ($item in $folderGroup.Group) {
            Write-JournalRecord -ServiceDir $ServiceDir -Record (New-JournalRecord -Item $item -BatchId $batchId -Status 'Planned')
        }

        $stages = New-Object System.Collections.Generic.List[object]
        foreach ($item in $folderGroup.Group) {
            $parent = [System.IO.Path]::GetDirectoryName($item.OldPath)
            do {
                $tempName = '.__video_auto_rename_' + [guid]::NewGuid().ToString('N') + [System.IO.Path]::GetExtension($item.OldPath)
                $tempPath = Join-Path $parent $tempName
            } while (Test-Path -LiteralPath $tempPath)
            $stages.Add([pscustomobject]@{ Item=$item; TempName=$tempName; TempPath=$tempPath })
        }

        try {
            foreach ($stage in $stages) {
                Rename-Item -LiteralPath $stage.Item.OldPath -NewName $stage.TempName -ErrorAction Stop
            }
            foreach ($stage in $stages) {
                Rename-Item -LiteralPath $stage.TempPath -NewName $stage.Item.NewName -ErrorAction Stop
                $stage.Item.Status = 'Renamed'
                $results.Add($stage.Item)
            }
        }
        catch {
            $failure = $_.Exception.Message
            foreach ($stage in @($stages | Sort-Object { $_.Item.OldName } -Descending)) {
                if (Test-Path -LiteralPath $stage.TempPath) {
                    Rename-Item -LiteralPath $stage.TempPath -NewName $stage.Item.OldName -ErrorAction SilentlyContinue
                }
                elseif (Test-Path -LiteralPath $stage.Item.NewPath) {
                    Rename-Item -LiteralPath $stage.Item.NewPath -NewName $stage.Item.OldName -ErrorAction SilentlyContinue
                }
            }
            foreach ($item in $folderGroup.Group) {
                try {
                    Write-JournalRecord -ServiceDir $ServiceDir -Record (New-JournalRecord -Item $item -BatchId $batchId -Status 'RolledBack' -Message $failure)
                }
                catch { }
            }
            throw
        }

        foreach ($item in $folderGroup.Group) {
            Write-JournalRecord -ServiceDir $ServiceDir -Record (New-JournalRecord -Item $item -BatchId $batchId -Status 'Completed')
        }
        Write-ServiceLog -ServiceDir $ServiceDir -Level 'INFO' -Message ("Renamed {0} video(s) in {1}." -f $folderGroup.Count, $folderGroup.Name)
    }
    return $results
}

function Invoke-RenameScan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][hashtable]$Observations,
        [Parameter(Mandatory = $true)][string]$ServiceDir,
        [ValidateRange(1, 32)][int]$FolderDepth = 1,
        [int[]]$FolderDepths = @(),
        [string]$FolderPathPattern = '',
        [hashtable]$NameSuffixByResolution = @{},
        [switch]$SkipDuplicateSuffixFolders,
        [System.Collections.IList]$SkippedFolders = $null
    )

    $plan = @(Get-RenamePlan -Root $Root -Observations $Observations -FolderDepth $FolderDepth -FolderDepths $FolderDepths -FolderPathPattern $FolderPathPattern -NameSuffixByResolution $NameSuffixByResolution -SkipDuplicateSuffixFolders:$SkipDuplicateSuffixFolders -SkippedFolders $SkippedFolders)
    if ($plan.Count -eq 0) { return @() }
    return @(Invoke-RenamePlan -Plan $plan -ServiceDir $ServiceDir)
}

Export-ModuleMember -Function @(
    'Test-SupportedVideo',
    'Get-LetterSuffix',
    'Get-NaturalSortKey',
    'Test-ExclusiveAccess',
    'Get-RenamePlan',
    'Write-ServiceLog',
    'Write-JournalRecord',
    'Repair-RenameJournal',
    'Invoke-RenamePlan',
    'Invoke-RenameScan'
)
