<p align="center">
  <img src="assets/images/app_logo.webp" width="100" alt="页屿">
</p>

<h1 align="center">页屿 (Yeyu Reader) · 看小说、短剧、漫画的手机 App</h1>

<p align="center">不用注册 · 不用付费 · 打开就能看</p>

<p align="center">
  <img alt="Platform" src="https://img.shields.io/badge/Android-7.0%2B-3DDC84?logo=android&logoColor=white"> <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/License-GPL--3.0-blue"></a> <a href="https://github.com/hrk666666/yeyu-reader/stargazers"><img alt="Stars" src="https://img.shields.io/github/stars/hrk666666/yeyu-reader?style=social"></a>
</p>

<p align="center">
  <a href="https://pan.quark.cn/s/10d1e8548b36"><img alt="下载 APK" height="40" src="https://img.shields.io/badge/%E4%B8%8B%E8%BD%BD-APK-3DDC84?style=for-the-badge&logo=android&logoColor=white"></a>
</p>

本仓是**页屿手机端的完整源码仓**：客户端、Rust 内核、平台工程、手环协议与测试全部在内，构建得出与发行版一致的 App。

所有内容实时从网上获取，App 本身不存任何内容。

> [!WARNING]
> 仅供学习研究，不提供、不存放任何内容。内容来自第三方公开接口，版权归原作者所有。使用后果自负，如有侵权请联系删除。

## 能做什么

- **📖 看小说** —— 左右翻页或上下滑动，字号字体随意调，有段落评论
- **🎧 听书** —— 机器朗读和真人讲书，有人声字幕、定时关闭、倍速、自动下一章
- **🎬 看短剧 / 漫剧** —— 播完自动下一集，能快进快退、调倍速、全屏
- **🖼 看漫画** —— 竖着往下滑，缓存过的断网也能看
- **🔍 找内容** —— 搜关键词或编号，有排行榜、作者主页、书评
- **🕘 记住进度** —— 看到哪自动记，下次接着看
- **⬇️ 下载离线** —— 整本下载后彻底离线，不会被自动清掉
- **📦 导出 EPUB** —— 整本打包成带封面与完整元数据的 EPUB 3，任何阅读器都能打开
- **⌚ 传到手环** —— 蓝牙把书架里的书推到小米手环 / 手表，页屿手环端直接打开读
- **🧩 安装包工具** —— 导入手环端 rpk，改包名重签后与原版共存，可存到下载目录或直接分享

## 相对上游的改动

对照 [ch6vip/fqapp](https://github.com/ch6vip/fqapp) `master`：

### Material Design 3 视觉改造

技术栈不变（仍是 Flutter + Rust 内核），但 UI 全部换成官方 MD3。规范数值不自己抄，一律委托 Flutter SDK 的官方常量 / 组件。

| 维度 | 实现 |
| --- | --- |
| 配色 | 全 App 单一源头 `ColorScheme.fromSeed(seedColor: #EF5038)`。浅 / 深两套官方 tonal palette；`surface` / `surfaceContainer*` / `onSurfaceVariant` / `outlineVariant` 等 role 全程使用，不再手写色板 |
| 组件主题 | `AppBar`（surfaceTint + 滚动后 level2 elevation + 标题左对齐）、`Card`（12dp / level1）、`Dialog`（28dp / surfaceContainerHigh）、`BottomSheet`（28dp 顶圆角 + 官方 drag handle 32×4）、`SnackBar`（inverseSurface）、`NavigationBar`（80dp + secondaryContainer 胶囊 indicator）、Filled/Outlined/Text/IconButton、FAB、SegmentedButton、Chip、Badge、Tooltip、ProgressIndicator 全部按官方 `*ThemeData` 配置 |
| 动效 | 直接引用 SDK 的 `Easing`（emphasizedDecelerate = `Cubic(0.05,0.7,0.1,1.0)`）与 `Durations`（short1–extralong4）。**不覆盖** `pageTransitionsTheme`，用 Flutter 官方默认转场（Android 3.38+ 为 PredictiveBack / FadeForwards，450ms）；另提供 `Md3SharedAxisPageRoute` 与 `Md3FadeThroughPageRoute` |
| 形状 / 高度 / 状态层 | `lib/theme/md3.dart`：`Md3Shape`(4/8/12/16/28)、`Md3Elevation`(0/1/3/6/8/12)、`Md3State`(hover .08 / pressed .10 / dragged .16)、`Md3Dimens`(48dp 触摸目标…) |
| 响应式 | `Md3WindowSizeClass` 按官方 600 / 840 / 1200 / 1600 断点；compact→NavigationBar、medium/expanded→NavigationRail、large→NavigationDrawer（`Md3AdaptiveNavigation`） |
| 导航 | 自研液态玻璃 `GlassDock` → 官方 `NavigationBar`（Material Symbols 图标、官方 state layer、重复选中当前目的地用 `standardDecelerate` + medium2 滚回顶部） |
| 去玻璃拟态 | `WenkuScope` 不再重建一套单色 ThemeData，改为复用全局官方主题、只注入 `ThemeExtension`；`LiquidGlassLens` / `GlassAppearance` / 档案纸色板统一到 `surfaceContainer*` + `surfaceTint` 分层 |
| 交互 | 按压反馈交给官方 `InkWell` state layer，删除自研弹簧缩放；信息层级用官方 `Typography.material2021` typescale |

**保留的例外**（都是显式语义色，不是自研视觉）：阅读器纸张预设、封面动态取色（官方 `ColorScheme.fromImageProvider` 思路）、视频 / 漫画画布、以及墨水屏纯黑白与 OLED 纯黑两个可访问性变体。

`test/md3_theme_test.dart` 把「官方」做成可验证断言：配色确实来自 `fromSeed`、动效绑定 SDK `Easing`/`Durations`、断点与形状数值、主导航确实是 `NavigationBar`。

### EPUB 3 导出

入口在「离线缓存」页每本书的书本按钮。整本重新取文，装配成单个 `.epub` 写进系统「下载」。

- **元数据**：Dublin Core 全字段 + schema.org（`ratingValue` / `ratingCount` / `wordCount`）+ 自定义 `fq:` 命名空间（`serialStatus` / `lastUpdated` / `readCount` / `shelfCount`）+ `belongs-to-collection`
- **封面**：按魔数嗅探 jpg / png / webp / gif（上游常把 WebP 挂在 `.jpg` 名下），登记 `properties="cover-image"`，同时保留 EPUB 2 的 `<meta name="cover">`
- **书名页**：封面缩略图、事实表（分类 / 状态 / 评分 / 字数 / 章节 / 在读 / 收藏 / 出版 / 首发 / 更新 / 原名 / 角色）、标签胶囊、完整简介、版权说明
- **结构**：`mimetype` 首位且不压缩；`nav.xhtml`（含 landmarks）与 `toc.ncx` 双目录；章节页把「第 N 章」拆成独立行
- **标识**：`uuid5(NAMESPACE_URL, "fanqie:<book_id>")`，与批量工具产出的同一本书共用同一 UUID

零计数的字段（在读 0、收藏 0）直接省略，不写成 `0 人在读`；评分上游给 0–100 刻度时折算到 0–10，给 0 视为无评分。

### 整本下载改批量取文

`/api/v1/chapters/full` 一次 CM/DH 握手解密整批（上游上限 3000 章，客户端按 80 章一批）：

- 400 章的书从 400 次往返变成 5 次
- 整批失败按二分拆半重试，单章仍失败才回退 `/chapters/{id}`
- 缺章（下架 / 锁章 / 解密失败）只影响那一章，不拖垮整批
- 缓存写入、断点续传、`pinned` 保护、插图刷新判定全部保持原样

### 平台通道

`fqapp/downloads` 新增 `saveBytes`：EPUB 以二进制写入 `MediaStore.Downloads`（Android 10+ 无需存储权限），旧版本落到应用外部目录并如实回报 `public=false`。

## 仓库结构

| 路径 | 内容 |
| --- | --- |
| `lib/` | Flutter 客户端全量代码：阅读器、播放器、漫画、书架、设置、手环传书、安装包工具 |
| `rust/` | Rust 内核（flutter_rust_bridge 桥接、视频解析、内容抓取端点） |
| `native/` | C 层加密库源码 |
| `android/` `ios/` `windows/` | 三端平台工程，含 `fqapp/downloads` 与 `SharePlugin` 通道 |
| `band_protocol/` | 手环端通信协议：协议文档、Kotlin 通道、Flutter 侧实现，以及 `rpk_resign/`（纯 Dart 的 rpk 改包名重签） |
| `test/` | 单元与组件测试，含 rpk 重签自检、MD3 主题断言 |
| `assets/` | 内置字体与品牌图 |
| `scripts/` `tools/` | 构建脚本与命令行工具（`rpk_repack_check.dart` 可脱离 App 改包名） |
| `update.json` | 应用内更新与公告的数据源 |

不入库：签名材料（`key.properties`、`*.jks`、`*.keystore`）、`docs/`、构建产物（`build/`、`target/`）。

## 怎么用

**找内容** —— 首页推荐各类内容，下拉刷新换一批。想找特定的就点搜索，输关键词或作品编号。

**看小说** —— 点屏幕中间呼出菜单，调目录、排版、缓存。翻过本章最后一页自动进下一章。

**滚动跨章** ——「阅读菜单 → 设置 → 翻页」选中滚动后，下方显示「跨章」选项，默认用分割线拼接相邻章节，也可直接切换下一章。拼接模式提前准备正文与段评排版，按实际读到的章节保存进度。

**正文替换** ——「设置 → 阅读 → 正文替换」添加普通文本或正则规则，按顺序在本地处理正文；默认关闭，关闭后显示原文。系统朗读也会使用替换后的文字，真人音频保持原样；规则暂不包含在备份中。

**听书** —— 声音可选，进度会记住。切到别的页面还能接着听，底部有控制条，支持通知栏和锁屏控制。

**播放页布局** ——「设置 → 外观 → 播放页布局」可选沉浸式、横屏片源自动分屏、始终分屏；分屏时竖屏上下、横屏左右，拖动分隔条调比例、点一下收起。

**下载离线** —— 详情页点「下载」存整本；阅读器点「缓存」批量下载后面几十章。手动下载的不会被自动清理。

## 常见问题

<details><summary><b>打开后一直卡在初始化？</b></summary>

第一次打开必须联网完成设备注册，检查网络再重试。

</details>

<details><summary><b>正文乱码 / 视频放不出来？</b></summary>

一般是设备信息过期。清除应用数据后重开会自动重新注册。

> [!CAUTION]
> 清除应用数据会同时删掉阅读记录和缓存。

</details>

<details><summary><b>搜索或播放突然失败？</b></summary>

内容都来自上游网站，对方调整或网络波动都会临时影响，过会儿再试。这个 App 没有自己的服务器，没法绕过上游的变化。

</details>

<details><summary><b>换手机怎么搬书架和进度？</b></summary>

「设置 → 数据 → 备份与恢复」导出文件，传到新手机后选文件、确认合并。

能搬：收藏、阅读和播放进度、看过哪些剧集。搬不了：本地 TXT/EPUB 文件、下载缓存、阅读时长、划线和设置。

</details>

<details><summary><b>需要注册或付费吗？有 iOS 版吗？</b></summary>

不用注册也不用付费，App 里没有任何登录和支付功能。没有 iOS 版，目前只有安卓。

</details>

## 参与贡献

一个人维护精力有限，欢迎提 issue、发 PR，修个小问题、补个功能都行，我都会看。参与方式见 [如何反馈](CONTRIBUTING.md)。

<a href="https://github.com/hrk666666/yeyu-reader/graphs/contributors">
  <img src=".github/contributors.svg" alt="贡献者">
</a>

---

**电脑版** [Windows 桌面版](WINDOWS.md) ｜ **开发者** [编译与开发](DEVELOPMENT.md) ｜ [如何反馈](CONTRIBUTING.md) ｜ **许可** [GPL-3.0](LICENSE)，Copyright (C) 2026 ch6vip ｜ **致谢** [LINUX DO](https://linux.do/)

<a href="https://www.star-history.com/?repos=hrk666666%2Fyeyu-reader&type=date&legend=top-left"><picture><source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=hrk666666/yeyu-reader&type=date&theme=dark&legend=top-left" /><source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=hrk666666/yeyu-reader&type=date&legend=top-left" /><img alt="Star History" src="https://api.star-history.com/chart?repos=hrk666666/yeyu-reader&type=date&legend=top-left" /></picture></a>
