#!/usr/bin/env bash
# 从 APK 的签名 keystore 导出 Vela 快应用（.rpk）签名所需的 PEM。
#
# 手机 App 与手环快应用必须同一密钥对签名，否则小米穿戴 SDK 拒绝通信。
# 用法：
#   ./tools/band_book/export_band_signature.sh android/release.jks shijinpu shijinpu
# 产物：out/private.pem、out/certificate.pem（复制到快应用工程 sign/release/）。
set -euo pipefail

KEYSTORE="${1:?用法: $0 <keystore> <alias> [storepass] [outdir]}"
ALIAS="${2:?缺少 alias}"
STOREPASS="${3:-shijinpu}"
OUTDIR="${4:-out/band_signature}"

command -v keytool >/dev/null || { echo "找不到 keytool（需要 JDK）"; exit 1; }
command -v openssl >/dev/null || { echo "找不到 openssl"; exit 1; }

mkdir -p "$OUTDIR"
P12="$OUTDIR/keystore.p12"

keytool -importkeystore \
  -srckeystore "$KEYSTORE" -srcstoretype JKS \
  -srcstorepass "$STOREPASS" -srcalias "$ALIAS" \
  -destkeystore "$P12" -deststoretype PKCS12 \
  -deststorepass "$STOREPASS" -noprompt >/dev/null

openssl pkcs12 -in "$P12" -nocerts -nodes -passin "pass:$STOREPASS" \
  -out "$OUTDIR/private.pem" 2>/dev/null
openssl pkcs12 -in "$P12" -clcerts -nokeys -passin "pass:$STOREPASS" \
  -out "$OUTDIR/certificate.pem" 2>/dev/null
rm -f "$P12"

echo "已导出："
echo "  $OUTDIR/private.pem"
echo "  $OUTDIR/certificate.pem"
openssl x509 -in "$OUTDIR/certificate.pem" -noout -subject -dates | sed 's/^/  /'
echo
echo "下一步：复制到快应用工程的 sign/release/ 与 sign/debug/，再 npm run release。"
