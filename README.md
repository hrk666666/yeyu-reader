# 页屿 · Yeyu Reader

小说阅读器 **页屿**（Yeyu Reader，Android / Flutter，包名 `com.yeyu.reader`）的开源组件仓：
更新检查 / 公告机制（`update.json`）与手环传书协议及双端源码（`band_protocol/`）。
开发者 **hrk_**。

> **先读 [许可与来源声明](#许可与来源声明必读) 与 [非从属关系声明](#非从属关系声明)。**
> 本项目是独立的个人学习研究作品，与任何商业实体及上游项目作者无隶属、授权或合作关系。

---

## 许可与来源声明（必读）

### 许可

本项目**手机端与手环端统一以 [GNU AGPL-3.0](LICENSE) 发布**（下称 AGPL-3.0）：

- 手机端主体衍生自 **fqapp 1.4.0**（[ch6vip/fqapp](https://github.com/ch6vip/fqapp)，**GPL-3.0**）；
- 手环端与通信协议实现衍生自 **moye 弦电子书**（[youshen2/com.bandbbs.ebook](https://github.com/youshen2/com.bandbbs.ebook)，**AGPL-3.0**）。
- 按 GPL-3.0 第 13 条，GPL-3.0 代码可以合法并入 AGPL-3.0 作品，合并后的作品按 AGPL-3.0 授权。
  因此双端**向下兼容地统一为 AGPL-3.0**，两端原始版权与许可声明均完整保留，不删除、不替换。
- 本仓前代「什锦铺 Web 套件」（`fetcher/` `web/` `android/`）原以 MIT 发布，现由版权人 hrk_
  一并改以 AGPL-3.0 授权，使全仓许可口径统一。

**分发义务（AGPL-3.0）**：对外分发本项目任何部分（含手环 rpk 二进制）时，必须一并提供对应
源码与修改说明，并同样以 AGPL-3.0 授权。仅个人本地使用不触发网络服务条款。

### 来源与修改清单（这是什么改的）

| 部分 | 来源 | 上游许可 | 本项目所做的修改 |
| --- | --- | --- | --- |
| 手机端 App（页屿） | ch6vip/fqapp 1.4.0 | GPL-3.0（并入后随 AGPL-3.0） | 界面全面迁移 Material Design 3；EPUB 元数据与批量导出、缓存/书架整理；接入手环传书（协议移植自弦电子书）；手环进度双向同步；品牌改名「页屿 / Yeyu Reader」、包名 `com.ch6vip.fqapp` → `com.yeyu.reader`、更换图标；`update.json` 更新检查/公告与镜像测速优选；启动静默连手环；移除爱发电入口；署名 hrk_ |
| 手环端 rpk | youshen2/com.bandbbs.ebook（弦电子书） | AGPL-3.0 | 包名改为 `com.yeyu.reader`、应用名「页屿」、更换图标（小米穿戴 SDK 硬约束：与手机端同包名同签名）；`/pages/push` 接收页对接页屿协议（握手/分片/命令集/进度同步）；按 o66 / n67 / band / rw / p67 / o62 六机型分支维护（`designWidth` 适配） |
| 手环协议与安卓桥 | 弦电子书双端通信 / 重连逻辑 | AGPL-3.0 | 文档化为 [PROTOCOL.md](band_protocol/PROTOCOL.md)；固化 10KB 分片流控、看门狗/保活、增量传书、进度取更远端/时长按天取 max/书签并集等同步语义 |
| 遗留 Web 套件 `fetcher/` `web/` `android/` | 自研 | AGPL-3.0（原 MIT） | 纯 Web MD3 阅读器 + WebView 套壳 + EPUB 3 抓取打包；信息架构参照 fqapp；现行 App 已改用 Flutter，此部分仅存档 |

界面排版另参考 [Wenku8 Flutter](https://github.com/ccdatw/Wenku8Flutter)（致谢，许可文本见 App 内「开源许可」）。
内容数据来自番茄小说公开接口，非本项目授权内容。

## 非从属关系声明

本项目为独立的个人学习研究作品，与下列各方**无任何隶属、授权、合作、背书或官方关系**：
小米科技 / 华米（Xiaomi、REDMI、VelaOS、小米手环、REDMI Watch、小米手表、小米运动健康、
小米穿戴 SDK 等名称与商标归各自所有者）、番茄小说及其所属公司、fqapp 原作者 ch6vip、
弦电子书作者 youshen2、Wenku8 Flutter 作者。

提及第三方名称**仅用于**说明技术来源、兼容对象与事实性引用。上游项目对本项目不承担任何
责任，本项目亦不代表上游项目的立场或承诺任何担保。

## 免责声明（风险提示）

- 本项目仅供**个人学习与技术研究**（HTTP 协议、加密链路、EPUB 规范、可穿戴通信等）使用。
- 抓取与展示的内容版权归原作者及平台所有；**请勿传播、商用或二次分发**。如有侵权，联系即删。
- 使用修改版客户端、安装第三方手环 rpk、访问非官方接口均存在账号、设备与稳定性风险，
  **一切后果由使用者自行承担**。
- 本项目按「现状」提供，不附带任何明示或默示担保（适销性、特定用途适用性等）。
- 在法律允许的最大范围内，开发者对因使用本项目造成的任何损失不承担责任。

---

## 本仓内容

| 路径 | 内容 |
| --- | --- |
| [`update.json`](update.json) | App 启动拉取的**更新检查 / 公告**单文件，字段说明见 [update.json.README.md](update.json.README.md) |
| [`band_protocol/`](band_protocol/) | 手环传书**协议**（[PROTOCOL.md](band_protocol/PROTOCOL.md)）与双端源码：`phone/` 手机侧 Dart、`kotlin/` Android 桥（小米穿戴 SDK）、`rpk_resign/` rpk 改包名与重签（纯 Dart，让官方版与内置书版共存） |
| `fetcher/` `web/` `android/` | 遗留「什锦铺」Web 套件（存档，见文末） |

手环端（VelaOS 快应用 rpk）源码在独立仓库 [hrk666666/yeyu-band](https://github.com/hrk666666/yeyu-band)，
按 o66 / n67 / band / rw / p67 / o62 六机型分支维护，同样以 AGPL-3.0 发布。

## 更新检查与下载

App 启动时拉取本仓 `update.json`（设置可关），拉取走 GitHub 镜像测速优选（并发探测、先回先赢，
可在设置手动钉死镜像）。有新版时**不从 GitHub 下载 APK**，而是引导用户跳转 `latest.url` ——
该链接在 update.json 里**自定义**（网盘 / 落地页皆可，由发布者配置）。

**本仓不发 GitHub Release。** 安装包请以 `latest.url` 指向的自定义链接为准。

## 协议

手环与手机之间按 [`band_protocol/PROTOCOL.md`](band_protocol/PROTOCOL.md) 传递：`__hs__` 三段握手、
10KB 分片与流控、文件命令集（传书 / 删书 / 章节目录 / 存储查询）、阅读进度与阅读时长双向同步。
SDK 硬约束：手机 APK 与手环 rpk 须**同包名同签名**。

---

## 附：什锦铺 Web 套件（遗留）

`fetcher/` `web/` `android/` 是前代「什锦铺」的纯 Web 重写版：把 fqapp 的页面层级与信息架构，
用**纯 Web 重写为 Material Design 3** 的可交互阅读器，并封装成离线可用的 Android 应用。
现行页屿 App 已改用 Flutter 原生实现，本部分仅作存档。

不发一个 HTTP 请求，不起一个本地服务器 —— 发行版是单个 IIFE + 脚本注入的正文，`file://` 直接可用。

```
┌──────────────────────────────────────────────────────────┐
│  fetcher/        Python 抓取与 EPUB 3 打包                │
│      ↓  产出书库 JSON + 封面 + 正文                       │
│  web/            MD3 前端（HTML/CSS/JS，零框架）           │
│      ↓  build.py 打包成 dist/                            │
│  android/        WebView 套壳，assets/ 内嵌全部资源        │
└──────────────────────────────────────────────────────────┘
```

| 目录 | 内容 | 技术栈 |
| --- | --- | --- |
| [`fetcher/`](fetcher/) | 批量发现 → 抓取 → 生成带完整元数据与封面的 EPUB 3 | Python 3，无第三方依赖 |
| [`web/`](web/) | Material 3 界面、路由栈、阅读器、书架、取色主题 | 原生 HTML/CSS/JS + esbuild |
| [`android/`](android/) | 单 Activity + 单 WebView 套壳，`WebViewAssetLoader` | Java 17 / AGP 8.7 / SDK 34 |

### 快速开始（遗留套件）

**跑前端**

```bash
cd web
npm i -D esbuild        # 仅打包需要
python3 build.py        # 产出 dist/
open dist/index.html    # 双击即开
```

**构建 Android**

```bash
cd android
cp /path/to/your.jks app/release.jks     # 或在 app/keystore.properties 里配置
./gradlew assembleRelease
```

没有 keystore 时会自动跳过签名（只出 unsigned 包），不会中断构建。

**抓书**

见 [`fetcher/README.md`](fetcher/README.md)。需要先起 fqapp 的 Rust 内核提供 loopback 接口。

### 已知限制

- 听书页是界面模拟，短剧页是封面 + 播放器 UI，都没有真实音视频流
- `file://` 直开时 Canvas 取色会被判跨源，主题回退到默认种子色；WebView / Electron 下正常
- 未做真机启动验证（CI 环境无 KVM），原生层只保证静态正确
- 书库为抓取时点的快照，不含后续更新章节

仓库内正文数据只保留两本，用于界面演示；完整书库不入库。

## 署名

页屿（Yeyu Reader）由 **hrk_** 开发（GitHub: hrk666666）。二次开发自 fqapp 1.4.0（GPL-3.0，
原作者 ch6vip），手环能力移植自 moye 弦电子书（AGPL-3.0，作者 youshen2）。双端统一以
AGPL-3.0 发布，完整保留上游版权声明；详见上文「许可与来源声明」。
