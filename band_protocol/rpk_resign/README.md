# RPK 改包名与重签（Dart）

手环按「包名 + 签名」定位快应用，同名只能装一个。把 rpk 的包名改掉再重新签名，
就能让「官方版」和「内置书版」同时留在同一只手环上。

这套实现是手机端 App「安装包工具」的内核，纯 Dart，只依赖 `dart:*` 与
`package:crypto`，可以单独抠出来用。

## 组成

| 文件 | 职责 |
| --- | --- |
| `rpk_zip.dart` | ZIP 读写：解析中央目录、取出压缩数据、按原样重组（保留原始 local header） |
| `rpk_der.dart` | 最小 DER 编解码，供自签证书与公钥解析使用 |
| `rpk_rsa.dart` | RSA 密钥生成、PKCS#1 v1.5 签名、PEM 编解码 |
| `rpk_x509.dart` | 生成自签 X.509 证书（CN 自定，SHA-256 签名） |
| `rpk_sign.dart` | 签名块 `RPK Sig Block 42` 的构造、剥离与验签 |
| `rpk_repack.dart` | 入口：改 `manifest.json` 的包名 → 重组 zip → 逐文件摘要 → 签名 |

## 签名块格式

格式对齐 `@aiot-toolkit/aiotpack` 的 `SignUtil`：

1. 把 zip 切成 `header`（本地文件区）/ `central`（中央目录）/ `footer`（EOCD）三段；
2. 每段算 `SHA-256(0xA5 || uint32(段长度) || 段字节)`；
3. 三段摘要拼成 `0x5A || uint32(3) || 三段摘要`，再取一次 SHA-256 得到整体摘要；
4. 整体摘要进 digest 块，RSA 签名（SHA-256 / PKCS#1 v1.5）签的是整段 `signdata`；
5. 签名块插在 `header` 与 `central` 之间，并修正 EOCD 里的中央目录偏移。

块内结构：多个 `key-value` 条目（`size | 0 | id | value`），
`0x01000101` 是签名者块（`signdata | signatures | publicKey`），
`0x01000201` 是逐文件摘要块（每项 `crc32(路径) | uint16 长度 | SHA-256 内容`）。
块尾重复一次 `size`，再跟 `RPK Sig Block 42` 魔数。

内层 `META-INF/CERT` 本身也是一个签过名的 zip（`hash.json` + 同样的签名块），
所以一次改动要签两次，验也是两次。

字段长度必须逐字节与官方实现一致——包括 `saveDigestChunk` 里 size 只记 body
长度这类细节；差一个字节，手环就拒绝安装。

## 用法

```dart
final result = repackRpk(
  source: File('pages.rpk').readAsBytesSync(),
  key: generateRsaKey(),                 // 或用 encodePrivateKeyPem 存下来复用
  certificate: buildSelfSignedCertificate(key),
  newPackage: 'com.yeyu.reader.seed',
);
File('pages.seed.rpk').writeAsBytesSync(result.bytes);
```

`repackRpk` 末尾会调用 `verifySignedRpk` 自检，验不过直接抛错，不会产出装不上的包。
`checkSignedRpk` 可以单独用来诊断已有包是外层还是内层没过。

## 需要注意

- 改过包名的包与原包**互不认**：手机端的传书、`launchWearApp` 只对同包名同签名的
  原包生效，共存版要在手环应用列表里手动打开；
- 数据各自独立（书架、阅读进度都不共享）；
- 换一套密钥再签，旧的共存版无法覆盖安装，只能先卸载。
