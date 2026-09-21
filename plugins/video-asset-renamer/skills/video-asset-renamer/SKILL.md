---
name: video-asset-renamer
description: Use only when the user explicitly invokes `$video-asset-renamer` by exact skill name. Do not infer invocation from paths, video files, naming requests, or similar keywords.
---

# 视频素材统一命名

这个技能只在用户明确输入 `$video-asset-renamer` 时调用。它支持一次性 Preview/Apply 改名，也可以帮助用户检查中央 Windows watcher 的状态和日志。

## 一次性改名规则

把指定大文件夹下的直接一级子文件夹视为独立批次。保留已经符合 `<子文件夹名>-<大写字母序列>.<原扩展名>` 的视频；其余支持的视频按自然排序使用 A、B、C……AA、AB。只处理 mp4、mov、mkv、avi、wmv、m4v、webm、flv、mts、m2ts。

必须先 Preview，展示旧名到新名的映射并保存 CSV；只有用户明确确认后才 Apply。Apply 前后核对视频数量和文件大小，确认再次 Preview 没有待处理项。

## 中央 watcher 规则

中央服务每 10 秒扫描一次白名单目录结构。新视频必须连续两轮大小和修改时间不变，并且能够以 `FileShare.None` 独占打开后才改名。1080P 文件使用 `-1080P` 后缀；480P 和 720P 不追加分辨率后缀。粗剪、成片、测试和不符合结构的路径跳过。

遇到单个无权限或暂时不可读的镜头文件夹，记录 WARN 并继续其他目录；不要删除、移动或强行取得生产文件的权限。

## 操作边界

- 不递归处理镜头文件夹更深层的视频。
- 不覆盖已有目标文件。
- 不强制关闭剪映或其他占用视频的软件。
- 不输出或上传真实服务器路径、日志和素材名称到公共文档。
- 安装和维护脚本见插件目录的 `scripts/`，设计说明见 `docs/`。
