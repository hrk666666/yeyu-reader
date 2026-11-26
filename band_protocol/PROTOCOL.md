# 页屿手环传书协议（Band Book Protocol）

本目录开源「页屿（Yeyu Reader）」手机端与手环端之间**实际传递的通信协议**及相关实现。

## 来源与许可

- **协议与通信实现**移植自 [moye 弦电子书（youshen2/com.bandbbs.ebook）](https://github.com/youshen2/com.bandbbs.ebook)（**AGPL-3.0**，作者 youshen2）：重连、看门狗、分片流控等链路逻辑沿用其开源实现，并在此基础上文档化、固化增量传书与阅读进度双向同步语义。上游版权与许可声明完整保留。
- **手机端主体**（本目录之外的 App 代码）衍生自 fqapp 1.4.0（ch6vip/fqapp，**GPL-3.0**）。按 GPL-3.0 第 13 条，GPL-3.0 代码可并入 AGPL-3.0 作品，故**双端统一以下兼容的 AGPL-3.0 发布**。
- 本目录（协议文档 + `phone/` + `kotlin/`）以 **AGPL-3.0** 授权，分发时须一并提供源码与修改说明。

**非从属关系声明**：本项目与小米 / 华米（小米穿戴 SDK、VelaOS、小米手环、REDMI Watch、小米运动健康等）、fqapp 原作者 ch6vip、弦电子书作者 youshen2 均无隶属、授权或合作关系；提及仅用于说明技术来源与兼容对象。

**免责**：仅供个人学习研究；修改版 rpk / 客户端的使用风险自负；按「现状」提供，无任何担保。完整声明见[根 README](../README.md)。

## 目录

- `phone/` — 手机端实现（Dart，`lib/services/band_book/`）
- `kotlin/` — 手机端安卓桥（`BandBookPlugin.kt`，小米穿戴 SDK xms-wearable 1.4）
- 手环端实现（VelaOS 快应用 rpk 源码，六机型分支）见仓库 `hrk666666/yeyu-band`
- `rpk_resign/` — rpk 改包名与重签（纯 Dart），见 [rpk_resign/README.md](rpk_resign/README.md)

## 0. 传输层与硬约束

| 项 | 值 |
| --- | --- |
| 通道 | 小米穿戴 SDK MessageApi（NodeApi 发现节点 / MessageApi 收发 JSON 文本） |
| 应用拉起 | `launchWearApp(nodeId, "/pages/push")`，先拉起手环端、约 0.3s 后再询问授权 |
| **包名约束** | 手机 APK 与手环 rpk 必须同包名：`com.yeyu.reader` |
| **签名约束** | 两端必须同一签名证书（同一 jks 导出的 release pem） |
| 手环机型分支 | o66（手环10/11）、n67（9Pro/8Pro）、band（手环9）、rw（Redmi Watch 5/6）、p67（手环10 Pro）、o62（手表S5/S4/S4 Sport/S3） |

> 包名或签名不一致时 `launchWearApp` 直接失败，两端无法互通——这是小米穿戴 SDK 的硬限制。

## 1. 握手（`__hs__`）

连接建立后由手机端发起，三步计数：

```jsonc
// count 0: 手机 → 手环，开始握手
{"tag": "__hs__", "count": 0, "version": 260600, "versionName": "26.6.1"}

// count 1: 手环 → 手机，上报手环版本（versionCode + versionName）
{"tag": "__hs__", "count": 1, "version": 260601, "versionName": "26.6.1.n67"}

// count 2: 手机 → 手环，确认
{"tag": "__hs__", "count": 2, "version": 260600, "versionName": "26.6.1"}
```

**版本规则（`versionName`，a.b.c 可续段）**：

- 格式为点分段 `a.b.c(.d…)`：`a.b` 是兼容系列，`c` 及以后（修订号、机型码如 `n67`/`rw`/`o66`）不限。
- **连接强制要求双方 `a.b` 一致**，不一致即拒绝（手机侧抛「版本不兼容」，手环侧弹版本错误页）。
- 当前系列为 **26.6**：手机 `26.6.1` ↔ 手环 `26.6.1.{branch}`。
- 旧端兼容：对端不回 `versionName` 时退化为数值版本下限检查——手环要求手机 `version` ≥ `126430`（`MIN_PHONE_VERSION`），手机要求手环 `version` ≥ `251231`。
- `version`（数值）字段保留，供旧端互操作；新端一律以 `versionName` 的 a.b 判定为准。

链路控制帧 `__link__`：手机侧链路失效时下发，双方清理在途命令。

## 2. 保活与看门狗

| 机制 | 侧 | 参数 |
| --- | --- | --- |
| 看门狗 | 手环 | 15s 无消息断开 |
| 看门狗 | 手机 | 10s 无消息判定失联，打断全部在途命令 |
| 保活 | 手机 | 空闲时每 3s 发 `get_storage_info`，连续 3 tick |

传输命令均有应答，天然保活；大批量间隙（如用户在手机端选书）需显式保活。

## 3. 传书（分片传输）

一本多章节文本按章节为单位传；每章正文切 **10KB** 分片。时序：

```text
手机                                            手环
  │ startTransfer {title, chapterCount, chapterIndices?} │
  │ ───────────────────────────────────────────────────▶ │
  │                                              ready    │
  │ ◀─────────────────────────────────────────────────── │
  │ stat:"d" {chapter, chunk, total, data}   （10KB 分片） │
  │ ───────────────────────────────────────────────────▶ │
  │ next_chunk / chapter_chunk_complete                  │
  │ ◀─────────────────────────────────────────────────── │
  │ （重复分片直到本章完）                                  │
  │ chapter_complete {chapter}                            │
  │ ───────────────────────────────────────────────────▶ │
  │ chapter_saved {chapter}                               │
  │ ◀─────────────────────────────────────────────────── │
  │ （下一章 …）                                           │
  │ transfer_complete                                     │
  │ ───────────────────────────────────────────────────▶ │
  │ transfer_finished                                     │
  │ ◀─────────────────────────────────────────────────── │
```

- `chapterIndices`（可选）：只传给定下标子集，用于**增量同步**（只推新章节）。
- `startFrom` 只影响手环侧阅读进度写入，**不决定**哪些章写入（写入集合完全由 `chapterIndices` / 全量决定）。
- 断线续传：手机侧命令通道 FIFO + 3 次重试（重试延迟可注入），看门狗超时以 `__link__` 打断。
- `data` 为嵌套 JSON 字符串（手环端 JS 解析两次）。

## 4. 命令集（JSON 文本消息）

| 命令 | 方向 | 说明 |
| --- | --- | --- |
| `startTransfer` / `ready` / `next_chunk` / `chapter_chunk_complete` / `chapter_complete` / `chapter_saved` / `transfer_complete` / `transfer_finished` | 双向 | 传书流程（见 §3） |
| `get_book_status` | 手机→手环 | 查询书在手环上的章节数、阅读进度；增量传前先查 |
| `get_reading_data` | 手机→手环 | 拉取阅读进度（chapterIndex / offsetInChapter / scrollOffset）+ 时长（totalSeconds / dailySeconds 按天）+ 书签 |
| `set_reading_data` | 手机→手环 | 回写进度 / 时长 / 书签（任一或全部） |
| `get_storage_info` | 手机→手环 | 剩余/已用存储；兼作保活 |
| `delete_book` | 手机→手环 | 删除整本 |
| `delete_chapters` | 手机→手环 | 删除指定章节（下标列表） |
| `update_book_info` | 手机→手环 | 更新书名等元信息 |
| `get_settings` / `set_settings` | 手机→手环 | 手环端阅读设置 |

## 5. 阅读数据双向同步语义（`band_reading_sync.dart`）

| 数据 | 合并规则 |
| --- | --- |
| 进度（章 / 章内偏移） | 取**更远**的一端（按章序，同章比 offset） |
| 阅读时长 | 按天取 `max`（同一天两端都读过不相加），汇总后回写 |
| 书签 | 双向并集 |

同步模式：`auto`（默认，谁远听谁）/ `bandToPhone` / `phoneToBand`。
手机侧写入走历史记录 upsert——**无历史条目时补建**（旧版此处静默丢弃，导致"手环进度同步后手机没变"）。

## 6. 启动静默连接（`band_auto_connect.dart`）

App 启动约 4s 后静默尝试连接手环（设置可关 `band_auto_connect_enabled`）；
连接成功后若开启自动同步，对全部书目执行 §5 双向同步。
连接时序（`BandBookPlugin.kt`）：选节点 → `launchWearApp` 拉起手环端 → 约 0.3s → 询问授权。

## 7. 许可

- 协议实现移植自 moye 弦电子书（AGPL-3.0），本目录及手环端源码依 AGPL-3.0 开源。
- 手机端其余部分为 GPL-3.0（基于 fqapp 二次开发）。
