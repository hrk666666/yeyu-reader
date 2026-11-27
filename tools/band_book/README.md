# 手环传书（弦电子书手环端）

App 侧实现：`lib/pages/band_book_page.dart`、`lib/services/band_book/`、
`android/app/src/main/kotlin/com/fqapp/fqapp/BandBookPlugin.kt`。

## 为什么手环上要装「配套 rpk」

小米穿戴 SDK 的硬性约束：**手机 App 与手环快应用必须同包名、同签名**，否则
`launchWearApp` 直接失败（`AppNotInstalledException` / 签名校验失败）。
手环端的开源项目是 `youshen2/com.bandbbs.ebook`（AGPL-3.0），官方发行包的包名是
`com.bandbbs.ebook.plus`、签名是作者的证书，我们的 App 是 `com.yeyu.reader` +
`shijinpu.jks`，所以必须自己打一份配套 rpk。

## 打包配套 rpk

1. 克隆手环端，切到对应设备的分支：

   | 分支 | 设备 | 屏宽 |
   | --- | --- | --- |
   | `band` | 手环通用（8/9/10 等，按 README 说明） | 336 |
   | `o66` | 小米手环 10 | 212 |
   | `n67` | 小米手环 8 Pro / 9 Pro | 336 |
   | `o62` / `p67` | 对应手表型号 | — |
   | `rw` | REDMI Watch | — |

   ```bash
   git clone https://github.com/youshen2/com.bandbbs.ebook
   cd com.bandbbs.ebook
   git checkout n67
   npm install
   ```

2. 改 `src/manifest.json`：

   ```json
   "package": "com.yeyu.reader",
   "versionName": "V26.6.1.BAND",
   "versionCode": 260601
   ```

   包名必须与 `android/app/build.gradle.kts` 的 `applicationId` 一致。
   `versionName` 后缀建议带分支名（如 `V26.6.1.o66` / `V26.6.1.n67`），
   便于装错型号时从「关于」页一眼看出来。

3. 把 App 的签名证书转成快应用签名（`sign/release/{private,certificate}.pem`）：

   ```bash
   ./tools/band_book/export_band_signature.sh /path/to/release.jks shijinpu
   ```

   脚本产出 `private.pem` / `certificate.pem`，复制到快应用工程的
   `sign/release/`（以及 `sign/debug/`，调试安装同样要签名一致）。

4. 打包：

   ```bash
   npm run release
   ```

   产物在 `dist/` 下的 `.rpk`。

5. 安装到手环：表盘自定义工具 / AstroBox → 蓝牙一键安装 → 装完重启手环。

## 协议（与手环端 `utils/interconn*.js` 对齐）

| 方向 | 消息 |
| --- | --- |
| 双向 | `{"tag":"__hs__","count":0..2,"version":260600}` 握手 |
| 手机→手环 | `{"tag":"file","stat":"startTransfer","filename","total","wordCount","startFrom":0,"chapterIndices":[…],"hasCover":false,"author","summary","category"}` |
| 手环→手机 | `{"tag":"file","type":"ready","count","usage"}` |
| 手机→手环 | `{"tag":"file","stat":"d","count":章序号,"data":"<JSON字符串>"}`，`data` 内为 `{index,name,content,wordCount,chunkNum,totalChunks}` |
| 手环→手机 | `next_chunk`（还有下一片）/ `chapter_chunk_complete`（本章最后一片） |
| 手机→手环 | `{"tag":"file","stat":"chapter_complete","count":章序号}` |
| 手环→手机 | `{"tag":"file","type":"chapter_saved","syncedCount","totalCount","progress"}` |
| 手机→手环 | `{"tag":"file","stat":"transfer_complete"}` |
| 手环→手机 | `{"tag":"file","type":"transfer_finished"}` |
| 手环→手机 | `{"tag":"file","type":"error","message","count"}` |

分片上限 10 000 字符（与手环端 `saveChapter` 的拼接方式一致），每片必须等手环
回包再发下一片——Binder 消息通道没有背压，抢发会丢片。

## 已知限制

- 只传纯文本：插图、段评、封面都不带（`hasCover: false`）。
- 手环端存储不足会回 `error`，App 直接失败提示，不会无限重试。
- 重传同一本书会从第 0 章覆盖（`startFrom: 0`），不做断点续传的差异计算。

## 共存版安装包（App 内改包名重签）

手环按「包名 + 签名」定位快应用，同名只能留一个：内置书版本一旦覆盖安装，
手机端的 `launchWearApp` 就找不到它了。App 里因此做了一个离线工具
（手环传书页 → 右上角「安装包工具」）：

1. 导入任意 rpk（官方包、内置书版本都行）；
2. 开「改包名，实现共存」，包名默认为 `<原包名>.seed`，可自己改；
3. 生成 → 存到系统「下载」目录，或直接调系统分享发给别人。

关闭开关时不做任何处理，直接把原包原样交出去。

签名用的是**本机第一次使用时生成的 RSA-2048 密钥**（存 Secure Storage，
Keystore 加密），自签证书一起生成，不碰 `shijinpu` 私钥。所以：

- 改包名后的包与官方包签名不同、包名不同，两者可以同时装在一台手环上；
- 它也不再与手机端互认 —— 传书、`launchWearApp` 唤起都只对同包名同签名的
  原包有效；
- 清数据/换机后密钥会重新生成，届时旧包无法被覆盖安装，只能先卸载。

实现：`lib/services/band_rpk/`（zip 重打包、签名块、RSA、自签证书）+ 
`lib/pages/band_rpk_tool_page.dart`（界面）+ `SharePlugin.shareFile`
（`FileProvider` 授权，见 `android/app/src/main/res/xml/file_paths.xml`）。

### 在电脑上验证产物

改包名后的包必须能被 `RPK Sig Block 42` 验签，否则手环会拒绝安装。仓库里带了一个
离线校验脚本（不依赖手环）：

```bash
dart run tools/band_book/rpk_repack_check.dart \
  ../../页屿手环端-小米手环9.rpk /tmp/out.rpk com.yeyu.reader.seed
```

脚本会打印密钥生成/重打包耗时，并把产物写到 `/tmp/out.rpk`（同目录另有
`out.rpk.pem`，是本次用的私钥，仅用于复现）。签名格式与
`@aiot-toolkit/aiotpack` 的 `SignUtil` 逐字节对齐，包括 `saveDigestChunk`
里 size 只记 body 长度这类细节。
