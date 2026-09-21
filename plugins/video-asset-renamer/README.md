# Video Asset Renamer

这是一个面向 Windows 制作团队的视频素材统一命名插件。运行时只使用 PowerShell 和 Windows 文件系统，不调用 AI，也不消耗 Token。

## 功能

- 单次 Preview/Apply：把同一镜头文件夹中的视频按自然排序改成 `文件夹名-A`、`文件夹名-B`、`文件夹名-C`。
- 中央后台服务：每 10 秒扫描一次多个批次目录，文件大小和修改时间连续两轮不变、且能以独占方式打开后才改名。
- 1080P 规则：自动使用 `文件夹名-A-1080P.mp4`；480P 和 720P 保持不加分辨率后缀。
- 事务式改名：先写入唯一临时名，再切换到最终名；发生错误时尝试回滚。
- 单实例互斥锁、UTF-8 BOM 历史 CSV、日志滚动和计划任务重启。
- 单个无权限、正在复制或被剪辑软件占用的文件夹会被记录并跳过，不会阻塞其他目录。

## 安装为 Codex 插件

```powershell
codex plugin marketplace add pencil102411-cell/horizontal-cinematic-prompt-agent-plugin --ref main
codex plugin add video-asset-renamer@hengping-film-tools
```

安装后只有明确调用 `$video-asset-renamer` 时才使用这个技能。

## 运行中央后台服务

先把 `scripts` 目录放到一个稳定的本地目录或服务器共享目录。然后用 UNC 路径安装计划任务：

```powershell
Set-ExecutionPolicy -Scope Process Bypass
& .\scripts\install-central-task.ps1 `
  -BaseRoot "\\server\share\production\videos" `
  -ServiceDir "\\server\share\production\videos\_video-renamer" `
  -TaskName "VideoAssetRenamer-Central"
```

脚本默认每 10 秒扫描一次，使用当前账户创建任务。服务目录必须包含：

- `video-auto-renamer-central.ps1`
- `VideoAutoRenamer.psm1`
- `uninstall-central-task.ps1`

卸载任务：

```powershell
& .\scripts\uninstall-central-task.ps1 -TaskName "VideoAssetRenamer-Central"
```

## 目录结构约束

中央服务默认识别以下结构：

```text
<batch>\SPxx\第x场\<480P|720P|1080P>\<YYYYMMDD-Vxx>\SP-xxxx[-xxxx]*\video.mp4
<category>\<batch>\SPxx\第x场\<480P|720P|1080P>\<YYYYMMDD-Vxx>\SP-xxxx[-xxxx]*\video.mp4
```

服务只处理镜头文件夹中直接存在的视频，不递归处理镜头文件夹更深层的文件。

## 设计与脚本说明

- [设计思路](docs/design.md)
- [脚本详情](docs/script-details.md)
- [Skill 使用说明](skills/video-asset-renamer/SKILL.md)

## 验证

```powershell
& .\tests\run-tests.ps1
& .\tests\test-central-service.ps1
```

测试只使用临时目录，不会访问真实视频服务器。

## 许可

建议在发布前根据你的开源意图补充许可证。没有许可证时，其他人可以看到代码，但默认不获得明确的再发布、修改和商业使用授权。
