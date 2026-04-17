# iTip ⚡

macOS 菜单栏应用，自动追踪你的应用使用习惯，一键切换到最近使用的应用。

## 功能

- 菜单栏常驻，自动记录应用切换
- 按最近使用时间和频率排序，展示前 10 个常用应用
- 显示使用次数、累积活跃时长、最后使用时间
- 一键激活或启动目标应用
- 冷启动时从 Spotlight 预填充历史数据
- 自动清理已卸载的应用

## 安装

从 [GitHub Actions](https://github.com/txdywy/iTip/actions) 下载最新的 `iTip-release` artifact。

下载后按以下步骤操作：

```bash
# 1. 解压（GitHub artifact 是双层 zip）
cd ~/Downloads
unzip iTip-release.zip

# 2. 解压内层 zip 并移动到 /Applications（必须用 mv，不能 cp）
ditto -x -k iTip.zip /tmp/
mv /tmp/iTip.app /Applications/iTip.app

# 3. 清除 quarantine 属性
xattr -cr /Applications/iTip.app

# 4. 打开
open /Applications/iTip.app
```

> ⚠️ 不要从 Downloads 目录直接运行！macOS 的 App Translocation 机制会阻止 app 正常启动。
> 必须先移动到 `/Applications` 再运行。

首次打开时 macOS 可能提示"无法验证开发者"，右键点击 → "打开" → 确认即可。

## 构建

```bash
xcodebuild -project iTip.xcodeproj -scheme iTip -configuration Release build
```

需要 Xcode 16+ 和 macOS 14+。
