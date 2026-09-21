# 横屏影视提示词 Agent 2.0

## 2026-09-19 工作流整理

版本：`2.3.0`。

- 保留提示词生成、返修、场次记忆、剧本检索和语料完整性校验。
- 生成、分析和返修按用户当前请求直接交付。

已安装的同事运行：

```powershell
codex plugin marketplace upgrade hengping-film-tools
codex plugin add horizontal-cinematic-prompt-agent-v2@hengping-film-tools
```

随后新建 Codex 任务加载新版。

这是一个供 Codex 直接安装的公开插件市场仓库。插件包含：

快速说明：[安装与升级一图说明.png](./安装与升级一图说明.png)｜[网页版 HTML](./安装指南与更新说明.html)

- 横屏真人电影感 Seedance 2.0 提示词工作流
- 逐镜精确焦段、景深、机距与透视规则
- 人物表演动机、尺度、泪态、倾听与过演控制，以及动作戏、特效戏和叙事光影规则
- 室外风、雨、雪、雾对环境和人物的可见影响
- 在当前场次项目内建立和维护 `场次记忆.md`
- 《风起玲珑骨》24 集逐集文本、4 份定稿 PDF、451 场索引和人物表演圣经

## 执行方式与创作判断

- 用户当前要求和已确认场次条件优先；已有资料直接使用，非关键缺口采用并标注工作假设，不重复索要资产或确认已有授权。
- 四区块用于最终完整视频提示词；分析讨论、局部返修和场次记忆按各自请求交付。缺少时长时默认按 15 秒工作基准继续，明确指定时长或分条方式优先。
- 保留中近景、85mm 以上长焦和克制表演的默认审美；允许有叙事用途的焦距例外、镜内变焦、连续攻防及有意消散，不强制每镜填满微表情、粒子或环境变化。
- 主动指出具体的台词时长、空间和动作衔接问题，保留用户已确认的核心镜头与剧情；一次完成请求范围内的多条提示词。
- 场次记忆首次建立需明确要求；后续维护区分已确认事实和未生成、未核验的预计状态。索引无命中时继续检索逐集正文。

## 2026-09-15 规则更新

版本：`2.2.0+codex.20260915120737`。

- 先判断本场的信息与情绪中心，再选景别、机位和切镜；沉默的旁观者也可以承载戏点。
- 构图增加人物层次、前景用途和必要信息检查；对称、正面、中近景等选择服从具体场景。
- 同框反应无需自动切镜；多人受到同一刺激时可以自然同步，不再用固定停顿或距离变化次数限制表演。
- 保留已确认的分镜、台词和动作过程；仅在用户要求时提供额外备选素材。

本次对照检查包含 12 组改前和 12 组改后文本回答，两版均符合本组明确请求。更新已通过结构检查；这组文本结果不代表真实视频质量或生成成功率提高。

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

## 维护与验证

仓库根目录是本文件所在目录；技能和脚本位于：

```text
plugins/horizontal-cinematic-prompt-agent-v2/skills/horizontal-cinematic-prompt-agent-v2/
```

从任意工作目录运行语料完整性测试：

```powershell
$pluginRoot = "<仓库根目录>\plugins\horizontal-cinematic-prompt-agent-v2\skills\horizontal-cinematic-prompt-agent-v2"
python -m unittest discover -s "$pluginRoot\scripts" -p "test_*.py"
python "$pluginRoot\scripts\verify_corpus.py"
```

`verify_corpus.py` 是只读校验器：`episodes` 的 `sha256` 证明原始提取文件未变，`scene-index.jsonl` 每条的 `text_sha256` 则按“逐行 strip、删除空行和精确 `<<<PDF_PAGE:nnn>>>` 标记、LF 拼接、UTF-8 SHA-256”计算。当前仓库应得到 24/24 集、451/451 场；校验器不会清洗或覆盖原始 episode 文件。

## 目录

```text
.agents/plugins/marketplace.json
plugins/horizontal-cinematic-prompt-agent-v2/
  .codex-plugin/plugin.json
  skills/horizontal-cinematic-prompt-agent-v2/
    SKILL.md
    AGENTS.md
    scripts/
    references/风起玲珑骨/剧本/
    skills/场次记忆.md
    templates/场次记忆模板.md
tools/sync-release.ps1
```

本市场还包含独立的 `video-asset-renamer` 插件，提供 Windows 视频素材安全命名和中央 watcher。安装方式：

```powershell
codex plugin add video-asset-renamer@hengping-film-tools
```

本仓库包含完整项目剧本资料。公开访问不代表授权转载、再发布或商业使用。
