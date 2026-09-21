# 脚本详情

## `VideoAutoRenamer.psm1`

核心模块，提供扩展名白名单、自然排序、文件独占访问测试、命名计划、稳定观察、事务改名、日志和历史 CSV。`Get-RenamePlan` 只生成计划；`Invoke-RenamePlan` 才执行改名。读取单个镜头目录失败时会把目录加入跳过列表，避免中断整个扫描。

## `video-auto-renamer-central.ps1`

常驻入口。参数包括 `BaseRoot`、`ServiceDir`、`IntervalSeconds`、`Resolutions`、`RunOnce` 和 `MutexName`。它加载模块、修复未完成历史记录、循环调用 `Invoke-RenameScan`，并将每轮结果写入日志。

## `video-auto-renamer.ps1`

适合单一根目录和固定深度的轻量 runner，保留给不需要中央目录白名单的场景。

## `install-central-task.ps1`

验证服务文件和监控根目录后，注册 Windows 计划任务。任务使用隐藏的 Windows PowerShell、`-ExecutionPolicy Bypass`、当前用户登录触发、单实例策略和每分钟恢复触发。默认扫描间隔是 10 秒。

## `uninstall-central-task.ps1`

只停止并删除指定计划任务，不删除视频、日志、历史 CSV 或脚本。

## `migrate-1080p-suffix.ps1`

用于已有 1080P 文件的 Preview/Apply 迁移。Preview 先等待稳定、输出 CSV 映射；Apply 验证映射的数量、字节数、路径和 `-1080P` 后缀后才执行事务改名。

## 日志与恢复

`logs/service.log` 记录启动、扫描、改名和跳过原因；`logs/rename-history.csv` 使用 UTF-8 BOM，便于 Excel 打开中文路径。日志达到阈值后滚动备份。服务重启时检查 `Planned` 记录，依据磁盘上原名和目标名的实际状态补写恢复结果。

## 发布前检查

发布包不能包含真实服务器 UNC、映射盘符、生产日志、历史 CSV、视频文件、账号信息或本机临时目录。安装时通过参数传入用户自己的 `BaseRoot` 和 `ServiceDir`。
