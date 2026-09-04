[CmdletBinding()]
param(
    [string]$ProjectRoot = (Join-Path ([Environment]::GetFolderPath('Desktop')) '项目分析\横屏影视提示词Agent1.3'),
    [switch]$Publish,
    [string]$CommitMessage = 'Update horizontal cinematic prompt agent'
)

$ErrorActionPreference = 'Stop'

$pluginName = 'horizontal-cinematic-prompt-agent-v2'
$repoRoot = [System.IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$source = [System.IO.Path]::GetFullPath($ProjectRoot)
$repoSkill = [System.IO.Path]::GetFullPath((Join-Path $repoRoot "plugins\$pluginName\skills\$pluginName"))
$directSkill = [System.IO.Path]::GetFullPath((Join-Path $HOME ".codex\skills\$pluginName"))
$personalPlugin = [System.IO.Path]::GetFullPath((Join-Path $HOME "plugins\$pluginName"))
$personalSkill = [System.IO.Path]::GetFullPath((Join-Path $personalPlugin "skills\$pluginName"))
$repoPlugin = [System.IO.Path]::GetFullPath((Join-Path $repoRoot "plugins\$pluginName"))
$cachebusterScript = [System.IO.Path]::GetFullPath((Join-Path $HOME '.codex\skills\.system\plugin-creator\scripts\update_plugin_cachebuster.py'))

function Assert-ExactTarget {
    param(
        [Parameter(Mandatory)][string]$Actual,
        [Parameter(Mandatory)][string]$Expected
    )

    $actualFull = [System.IO.Path]::GetFullPath($Actual).TrimEnd('\')
    $expectedFull = [System.IO.Path]::GetFullPath($Expected).TrimEnd('\')
    if (-not $actualFull.Equals($expectedFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "拒绝同步到非预期目录：$actualFull"
    }
    if ([System.IO.Path]::GetFileName($actualFull) -ne $pluginName) {
        throw "目标目录名称不符合插件名：$actualFull"
    }
}

function Get-TreeDigest {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return ''
    }

    $rows = Get-ChildItem -LiteralPath $Path -File -Recurse |
        Sort-Object FullName |
        ForEach-Object {
            $relative = [System.IO.Path]::GetRelativePath($Path, $_.FullName)
            $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
            "$relative`t$hash"
        }

    $joined = [string]::Join("`n", $rows)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($joined)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return [Convert]::ToHexString($sha.ComputeHash($bytes))
    }
    finally {
        $sha.Dispose()
    }
}

function Sync-Tree {
    param(
        [Parameter(Mandatory)][string]$From,
        [Parameter(Mandatory)][string]$To,
        [Parameter(Mandatory)][string]$Expected
    )

    Assert-ExactTarget -Actual $To -Expected $Expected
    New-Item -ItemType Directory -Path $To -Force | Out-Null
    & robocopy.exe $From $To /MIR /R:2 /W:1 /NFL /NDL /NJH /NJS /NP
    if ($LASTEXITCODE -gt 7) {
        throw "同步失败，Robocopy 退出码：$LASTEXITCODE"
    }
}

if (-not (Test-Path -LiteralPath $source -PathType Container)) {
    throw "找不到工程目录：$source"
}
if (-not (Test-Path -LiteralPath (Join-Path $source 'SKILL.md') -PathType Leaf)) {
    throw "工程目录缺少 SKILL.md：$source"
}
if (-not (Test-Path -LiteralPath $cachebusterScript -PathType Leaf)) {
    throw "找不到插件版本更新脚本：$cachebusterScript"
}

$beforeDigest = Get-TreeDigest -Path $repoSkill
$sourceDigest = Get-TreeDigest -Path $source
$contentChanged = $beforeDigest -ne $sourceDigest

Sync-Tree -From $source -To $repoSkill -Expected $repoSkill
Sync-Tree -From $source -To $directSkill -Expected $directSkill
Sync-Tree -From $source -To $personalSkill -Expected $personalSkill

if ($contentChanged) {
    $cachebuster = Get-Date -Format 'yyyyMMddHHmmss'
    & python $cachebusterScript $repoPlugin --cachebuster $cachebuster
    if ($LASTEXITCODE -ne 0) {
        throw '插件版本更新失败。'
    }
}

$repoManifest = Join-Path $repoPlugin '.codex-plugin\plugin.json'
$personalManifestDir = Join-Path $personalPlugin '.codex-plugin'
New-Item -ItemType Directory -Path $personalManifestDir -Force | Out-Null
Copy-Item -LiteralPath $repoManifest -Destination (Join-Path $personalManifestDir 'plugin.json') -Force

& codex plugin add "$pluginName@personal" --json
if ($LASTEXITCODE -ne 0) {
    throw '本地插件重装失败。'
}

$digests = @(@(
    Get-TreeDigest -Path $repoSkill
    Get-TreeDigest -Path $directSkill
    Get-TreeDigest -Path $personalSkill
) | Select-Object -Unique)
if ($digests.Count -ne 1) {
    throw '同步后的三份 Skill 内容不一致。'
}

if ($Publish) {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot '.git') -PathType Container)) {
        throw "仓库尚未初始化 Git：$repoRoot"
    }

    Push-Location $repoRoot
    try {
        git add -A
        if (git status --porcelain) {
            git commit -m $CommitMessage
            if ($LASTEXITCODE -ne 0) {
                throw 'Git 提交失败。请检查 user.name 和 user.email。'
            }
            git push
            if ($LASTEXITCODE -ne 0) {
                throw 'Git 推送失败。请检查远程仓库与登录状态。'
            }
        }
        else {
            Write-Host '没有内容变化，无需提交。'
        }
    }
    finally {
        Pop-Location
    }
}

Write-Host "同步完成。Skill SHA256：$($digests | Select-Object -First 1)"
