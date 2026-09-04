# 横屏影视提示词 Agent 1.3

这是一个供 Codex 安装的私有插件市场仓库。插件包含：

- 横屏真人电影感 Seedance 2.0 提示词工作流
- 逐镜精确焦段、景深、机距与透视规则
- 人物表演、动作戏、特效戏和叙事光影规则
- 室外风、雨、雪、雾对环境和人物的可见影响
- 《风起玲珑骨》24 集逐集文本、4 份定稿 PDF、451 场索引和人物表演圣经

## 同事安装

仓库是私有仓库。先由仓库管理员在 GitHub 中把同事加入 Collaborators，同事接受邀请后，在 PowerShell 运行：

```powershell
codex plugin marketplace add pencil102411-cell/horizontal-cinematic-prompt-agent-plugin --ref main
codex plugin add horizontal-cinematic-prompt-agent-v1-3@hengping-film-tools
```

第一次访问私有仓库时，Git 或 Codex 可能会打开 GitHub 登录窗口。安装完成后，新建一个 Codex 任务即可使用：

```text
$horizontal-cinematic-prompt-agent-v1-3
```

## 同事更新

维护者推送新版后，同事运行：

```powershell
codex plugin marketplace upgrade hengping-film-tools
codex plugin add horizontal-cinematic-prompt-agent-v1-3@hengping-film-tools
```

然后新建一个 Codex 任务，让新任务加载新版插件。

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
.\tools\sync-release.ps1 -ProjectRoot "D:\项目\横屏影视提示词Agent1.3"
```

脚本仅在内容实际变化时更新插件缓存版本。`-Publish` 需要本机已配置 Git 提交身份并能访问远程仓库。

## 目录

```text
.agents/plugins/marketplace.json
plugins/horizontal-cinematic-prompt-agent-v1-3/
  .codex-plugin/plugin.json
  skills/horizontal-cinematic-prompt-agent-v1-3/
tools/sync-release.ps1
```

本仓库含项目剧本资料，仅限获授权的团队成员使用和传播。
