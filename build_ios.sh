#!/bin/bash
# ---------------------------------------------------------------------------
# 霓虹突击 iOS —— 一键在 Mac 上出包
#
# 用法（在 Mac 上，把整个 shooter/ios 目录拷过去，或者在仓库里直接跑）：
#
#   ./build_ios.sh                      # 模拟器包（免签名，最快验证能不能编译）
#   ./build_ios.sh device               # 真机 .app（需要签名，见下）
#   ./build_ios.sh ipa                  # 真机 .ipa（需要签名）
#   TEAM_ID=ABCDE12345 ./build_ios.sh ipa
#
# 环境要求：macOS + Xcode 15 及以上（xcode-select --install 不算，必须装完整 Xcode）。
# 真机/ipa 需要：Xcode 里登录 Apple ID，或设置 TEAM_ID 环境变量（免费账号也行，
# 免费账号签出来的包 7 天后过期，重跑一次脚本即可）。
#
# 产物路径会打印在最后一行，例如：
#   out/ios/Shooter.app            （模拟器）
#   out/ios/Shooter.ipa            （真机安装包）
# ---------------------------------------------------------------------------
set -euo pipefail

cd "$(dirname "$0")"

MODE="${1:-sim}"
PROJ="Shooter.xcodeproj"
SCHEME="Shooter"
OUT="out/ios"
DERIVED="$OUT/DerivedData"
BUNDLE_ID="${BUNDLE_ID:-com.suicode.shooter}"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "❌ 找不到 xcodebuild。请先装完整 Xcode（App Store），再执行："
  echo "   sudo xcode-select -s /Applications/Xcode.app"
  exit 1
fi

mkdir -p "$OUT"

echo "==> 清理"
rm -rf "$DERIVED"

COMMON=(
  -project "$PROJ"
  -scheme "$SCHEME"
  -configuration Release
  -derivedDataPath "$DERIVED"
  -destination "generic/platform=iOS"
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID"
  CODE_SIGNING_ALLOWED=NO
)

case "$MODE" in
  sim)
    echo "==> 编译（iOS 模拟器，免签名）"
    xcodebuild "${COMMON[@]}" \
      -sdk iphonesimulator \
      -destination "generic/platform=iOS Simulator" \
      CODE_SIGNING_REQUIRED=NO \
      build | tail -40
    APP="$DERIVED/Build/Products/Release-iphonesimulator/Shooter.app"
    rm -rf "$OUT/Shooter.app"
    cp -R "$APP" "$OUT/Shooter.app"
    echo "✅ 模拟器包: $(pwd)/$OUT/Shooter.app"
    echo "   跑起来: xcrun simctl boot 'iPhone 15' 2>/dev/null || true"
    echo "           xcrun simctl install booted '$OUT/Shooter.app'"
    echo "           xcrun simctl launch booted $BUNDLE_ID"
    ;;

  device|ipa)
    TEAM="${TEAM_ID:-}"
    if [ -z "$TEAM" ]; then
      # 从 Xcode 已登录的账号里猜一个 team（多数情况下就是唯一那个）
      TEAM=$(security find-identity -v -p codesigning 2>/dev/null \
             | sed -n 's/.*"Apple Development: .*(\([A-Z0-9]\{10\}\))".*/\1/p' | head -1 || true)
    fi
    if [ -z "$TEAM" ]; then
      echo "❌ 没找到签名 team。两种办法任选其一："
      echo "   1) 打开 Xcode → Settings → Accounts 登录 Apple ID，然后重跑"
      echo "   2) TEAM_ID=你的10位TeamID ./build_ios.sh ipa"
      exit 1
    fi
    echo "==> 编译（真机，team $TEAM）"
    SIGN=(
      CODE_SIGNING_ALLOWED=YES
      CODE_SIGN_STYLE=Automatic
      DEVELOPMENT_TEAM="$TEAM"
      CODE_SIGN_IDENTITY="Apple Development"
      -allowProvisioningUpdates
    )
    xcodebuild "${COMMON[@]}" "${SIGN[@]}" -sdk iphoneos build | tail -40
    APP="$DERIVED/Build/Products/Release-iphoneos/Shooter.app"
    if [ ! -d "$APP" ]; then
      echo "❌ 没找到产物 $APP"
      exit 1
    fi
    rm -rf "$OUT/Shooter.app"
    cp -R "$APP" "$OUT/Shooter.app"
    echo "✅ 真机 .app: $(pwd)/$OUT/Shooter.app"

    if [ "$MODE" = "ipa" ]; then
      echo "==> 打包 .ipa"
      rm -rf "$OUT/Payload" "$OUT/Shooter.ipa"
      mkdir -p "$OUT/Payload"
      cp -R "$APP" "$OUT/Payload/Shooter.app"
      (cd "$OUT" && zip -qry Shooter.ipa Payload)
      rm -rf "$OUT/Payload"
      echo "✅ 安装包: $(pwd)/$OUT/Shooter.ipa"
      echo "   装到手机: 用 Xcode → Window → Devices，或 AltStore / Sideloadly 拖进去"
    fi
    ;;

  *)
    echo "用法: $0 [sim|device|ipa]"
    exit 2
    ;;
esac
