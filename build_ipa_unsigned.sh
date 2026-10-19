#!/bin/bash
# ---------------------------------------------------------------------------
# 不需要 Apple 账号、不需要签名的 .ipa —— 给朋友用 AltStore / Sideloadly 自己签
#
# 用法（Mac 上）：
#   ./build_ipa_unsigned.sh
# 产物：
#   out/ios/Shooter-unsigned.ipa
#
# 朋友那边：AltStore / Sideloadly / TrollStore 拖进去，用它自己的 Apple ID 签一次
# 就能装上（免费账号 7 天有效，到期重签；付费开发者账号 1 年）。
# ---------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "$0")"

OUT="out/ios"
DERIVED="$OUT/DerivedData-unsigned"
mkdir -p "$OUT"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "❌ 需要 macOS + Xcode（iOS 包只能在 Mac 上编译，任何 Android/Linux 都不行）"
  exit 1
fi

rm -rf "$DERIVED" "$OUT/Payload" "$OUT/Shooter-unsigned.ipa"

echo "==> 编译（不签名）"
xcodebuild \
  -project Shooter.xcodeproj \
  -scheme Shooter \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath "$DERIVED" \
  -destination "generic/platform=iOS" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  PRODUCT_BUNDLE_IDENTIFIER="${BUNDLE_ID:-com.suicode.shooter}" \
  build | tail -25

APP="$DERIVED/Build/Products/Release-iphoneos/Shooter.app"
[ -d "$APP" ] || { echo "❌ 没找到 $APP"; exit 1; }

mkdir -p "$OUT/Payload"
cp -R "$APP" "$OUT/Payload/Shooter.app"
# AltStore/Sideloadly 都接受不签名 ipa，签名在设备上完成
(cd "$OUT" && zip -qry Shooter-unsigned.ipa Payload)
rm -rf "$OUT/Payload"

echo "✅ 未签名安装包: $(pwd)/$OUT/Shooter-unsigned.ipa"
echo "   发给朋友，让他用 AltStore / Sideloadly 装（会自动用他的 Apple ID 签名）"
