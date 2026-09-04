# 横屏影视提示词 Agent 2.0

这是一个供 Codex 直接安装的公开插件市场仓库。插件包含：

完整图文说明请查看：[安装指南与更新说明.html](./安装指南与更新说明.html)

- 横屏真人电影感 Seedance 2.0 提示词工作流
- 逐镜精确焦段、景深、机距与透视规则
- 人物表演动机、尺度、泪态、倾听与过演控制，以及动作戏、特效戏和叙事光影规则
- 室外风、雨、雪、雾对环境和人物的可见影响
- 在当前场次项目内建立和维护 `场次记忆.md`
- 《风起玲珑骨》24 集逐集文本、4 份定稿 PDF、451 场索引和人物表演圣经

## 建立本地场次记忆

在需要制作的场次项目目录中打开 Codex，调用插件后直接说：

```text
$horizontal-cinematic-prompt-agent-v2
请根据当前项目里的分镜、资产和补充要求，建立这个场次的记忆文件。
```

插件会在当前场次项目根目录创建或更新 `场次记忆.md`。文件只保存在该项目中，不会写回插件、上传 Git 或同步到其他场次。

## 同事安装

无需下载压缩包，也无需添加 Collaborator。直接在 PowerShell 运行：

```powershell
codex plugin marketplace add pencil102411-cell/horizontal-cinematic-prompt-agent-plugin --ref main
codex plugin add horizontal-cinematic-prompt-agent-v2@hengping-film-tools
```

安装完成后，新建一个 Codex 任务即可使用：

```text
$horizontal-cinematic-prompt-agent-v2
```

## 同事更新

维护者推送新版后，同事运行：

```powershell
codex plugin marketplace upgrade hengping-film-tools
codex plugin add horizontal-cinematic-prompt-agent-v2@hengping-film-tools
```

然后新建一个 Codex 任务，让新任务加载新版插件。

## 启用自动更新

完成首次安装后，每位同事只需再运行一次：

```powershell
& "$env:USERPROFILE\.codex\.tmp\marketplaces\hengping-film-tools\tools\register-auto-update.ps1"
```

脚本会创建当前用户的 Windows 计划任务，在每次登录 Windows 时和每天 12:00 自动检查 GitHub。检测到新版本后会刷新插件市场并重新安装插件，无需管理员权限。更新会写入：

```text
%LOCALAPPDATA%\Codex\horizontal-cinematic-prompt-agent-v2\update.log
```

自动更新完成后，已打开的 Codex 任务不会热更新；新建任务后使用新版。

如需关闭自动更新：

```powershell
& "$env:USERPROFILE\.codex\.tmp\marketplaces\hengping-film-tools\tools\register-auto-update.ps1" -Remove
```

## 维护者同步与发布

`tools/sync-release.ps1` 以桌面工程为内容源，同时更新：

1. 本仓库内的插件 Skill
2. `~/.codex/skills` 中直接安装的 Skill
3. `~/plugins` 中的本地个人插件
4. 本地 Codex 插件缓存

只同步并重装本机版本：

```powershell
.\tools\sync-release.ps1
```

同步、提交并推送到 GitHub：

```powershell
.\tools\sync-release.ps1 -Publish -CommitMessage "更新提示词规则"
```

如果工程不在默认位置，可指定路径：

```powershell
.\tools\sync-release.ps1 -ProjectRoot "D:\项目\横屏影视提示词Agent2.0"
```

脚本仅在内容实际变化时更新插件缓存版本。`-Publish` 需要本机已配置 Git 提交身份并能访问远程仓库。

## 目录

```text
.agents/plugins/marketplace.json
plugins/horizontal-cinematic-prompt-agent-v2/
  .codex-plugin/plugin.json
  skills/horizontal-cinematic-prompt-agent-v2/
    skills/场次记忆.md
    templates/场次记忆模板.md
tools/sync-release.ps1
```

本仓库包含完整项目剧本资料。公开访问不代表授权转载、再发布或商业使用。
