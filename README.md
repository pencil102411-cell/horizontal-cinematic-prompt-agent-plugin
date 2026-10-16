# 横屏影视提示词Agent

## 2026-10-16 规则结构整理

版本：`3.1.0`。

- 每条规则只放一处，入口、总规则、模板分工清楚；冲突时按 `AGENTS.md`「冲突时听谁的」一份排序处理。
- 每次交付提示词后附「本轮读取清单」，方便核对 AI 是否真的读了模板和模块。
- 场次记忆不写进任何宿主程序的全局记忆（用户明确要求的除外）；同一目录可放多场，新增的场次用 `场次记忆-<集场标识>.md`，原有 `场次记忆.md` 不改名。
- 插件不负责：只要分镜方案、在已生成视频上局部修改或换机位重拍、人物/场景设定图。
- 内部模块文件夹改名为 `modules/`；语料校验现在也核对定稿 PDF。

已安装的同事运行：

```powershell
codex plugin marketplace upgrade hengping-film-tools
codex plugin add horizontal-cinematic-prompt-agent-v2@hengping-film-tools
```

随后新建 Codex 任务加载新版。Claude Code 用户运行 `/plugin marketplace update hengping-film-tools` 更新市场，再在 `/plugin` 里更新本插件，然后新开会话。

## 2026-10-09 Seedance 2.5 升级

版本：`3.0.0`。

- 适配 Seedance 2.5：每条视频 4—30 秒；素材上限 50 个（图片 30 张、视频 10 段、音频 10 段）；时间戳只用整数秒。
- 提示词改为五区块：素材引用 → 生成目标 → 光影设计 → 时间轴 → 保持一致；人物素材排在最前。
- 台词统一写成“角色台词（语气）：{台词原文}”；声音禁项在开头和结尾各写一次。
- 字数只统计时间轴：≤15 秒为 2000 / 3000 / 4000，16—30 秒为 3000 / 4500 / 6000。
- 显示名改为“横屏影视提示词Agent”；新增 Claude Code 安装清单（`.claude-plugin`）。

已安装的同事运行：

```powershell
codex plugin marketplace upgrade hengping-film-tools
codex plugin add horizontal-cinematic-prompt-agent-v2@hengping-film-tools
```

随后新建 Codex 任务加载新版。

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

快速说明：[安装与升级一图说明.png](./安装与升级一图说明.png)（旧版图示，以网页版和本文件为准）｜[网页版 HTML](./安装指南与更新说明.html)

- 横屏真人电影感 Seedance 2.5 提示词工作流
- 逐镜精确焦段、景深、机距与透视规则
- 人物表演动机、尺度、泪态、倾听与过演控制，以及动作戏、特效戏和叙事光影规则
- 室外风、雨、雪、雾对环境和人物的可见影响
- 在当前场次项目内建立和维护场次记忆（默认 `场次记忆.md`；同一目录新增的场次用 `场次记忆-<集场标识>.md`）
- 《风起玲珑骨》24 集逐集文本、4 份定稿 PDF、451 场索引和人物表演圣经

不负责：只要分镜方案、不要提示词的请求；在已生成视频上做局部修改或换机位重拍；人物/场景设定图等图像提示词。

## 执行方式与创作判断

- 用户当前要求和已确认场次条件优先；已有资料直接使用，非关键缺口采用并标注工作假设，不重复索要资产或确认已有授权。
- 五区块用于最终完整视频提示词；分析讨论、局部返修和场次记忆按各自请求交付。缺少时长时先按台词和动作节拍估算（4—30 秒），估不出来按 15 秒处理，明确指定时长或分条方式优先。
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

插件会在当前场次项目根目录创建或更新这一场的场次记忆文件（默认 `场次记忆.md`；同一目录已有别的场次时，新建 `场次记忆-<集场标识>.md`）。文件只保存在该项目中，不会写回插件、上传 Git 或同步到其他场次。

## 同事安装

无需下载压缩包，也无需添加 Collaborator。直接在 PowerShell 运行：

```powershell
codex plugin marketplace add pencil102411-cell/horizontal-cinematic-prompt-agent-plugin --ref main
codex plugin add horizontal-cinematic-prompt-agent-v2@hengping-film-tools
```

Claude Code 用户在 Claude Code 里运行：

```text
/plugin marketplace add pencil102411-cell/horizontal-cinematic-prompt-agent-plugin
/plugin install horizontal-cinematic-prompt-agent-v2@hengping-film-tools
```

Claude Code 装完后新开会话即可使用。Codex 安装完成后，新建一个 Codex 任务即可使用：

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

**注意**：3.1.0 的修改是直接在本仓库里完成的，桌面工程没有同步。本脚本会把桌面工程（默认 `桌面\项目分析\横屏影视提示词Agent1.3`，或 `-ProjectRoot` 指定的目录）镜像到仓库和本机安装位置，目标里多出来的文件会被删掉。再次运行前，先删除或清空桌面工程里原来的技能文件，再把仓库里 `plugins/horizontal-cinematic-prompt-agent-v2/skills/horizontal-cinematic-prompt-agent-v2/` 文件夹里的全部内容复制过去（`SKILL.md` 放在桌面工程的根目录），不要合并覆盖；否则旧的 `skills/` 文件夹和旧规则会被同步回来，冲掉 3.1.0 的修改。

本脚本需要 PowerShell 7（`pwsh`）运行；它只会更新 `plugins/horizontal-cinematic-prompt-agent-v2/.codex-plugin/plugin.json` 的版本号。发版时还要手动把 `plugins/horizontal-cinematic-prompt-agent-v2/.claude-plugin/plugin.json` 和根目录 `.claude-plugin/marketplace.json` 的版本号改成新的版本号（每次发版都要变，不带 `+codex` 后缀），否则 Claude Code 用户收不到更新。

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

`verify_corpus.py` 是只读校验器：`sources` 里 4 份定稿 PDF 的大小和 `sha256` 证明原件未变，`episodes` 的 `sha256` 证明原始提取文件未变，`scene-index.jsonl` 每条的 `text_sha256` 则按“逐行 strip、删除空行和精确 `<<<PDF_PAGE:nnn>>>` 标记、LF 拼接、UTF-8 SHA-256”计算。另会核对 manifest 里声明的 PDF 数、集数、场次总数和每集场次数。当前仓库应得到 4/4 份 PDF、24/24 集、451/451 场；校验器不会清洗或覆盖原始 episode 文件。

结果是 JSON。退出码 0 表示全部一致，1 表示内容与 manifest 不符，2 表示文件或结构读不了。在 PowerShell 或命令提示符窗口里直接运行时中文正常显示；输出给管道或文件时，中文写成 `\uXXXX` 转义，任何编码下都能解析。`corpus_root_sha256` 字段暂不核对。

## 目录

```text
.agents/plugins/marketplace.json      （Codex 插件市场）
.claude-plugin/marketplace.json       （Claude Code 插件市场）
plugins/horizontal-cinematic-prompt-agent-v2/
  .codex-plugin/plugin.json
  .claude-plugin/plugin.json
  skills/horizontal-cinematic-prompt-agent-v2/
    SKILL.md          （入口）
    AGENTS.md         （总规则）
    modules/          （分镜、动作戏、情感表演、特效戏、场次记忆五个内部模块）
    references/       （镜头与灯光、Seedance 规范等通用参考，以及 风起玲珑骨/ 剧本和人物表演圣经）
    templates/标准输出模板.md
    templates/场次记忆模板.md
    scripts/          （语料校验脚本和测试）
tools/sync-release.ps1
```

本仓库包含完整项目剧本资料。公开访问不代表授权转载、再发布或商业使用。
