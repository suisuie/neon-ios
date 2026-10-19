#!/bin/bash
# ===========================================================================
#  霓虹突击 iOS —— 一键打包（macOS 上双击运行）
#
#  谁用：代打包的人 / 借到的 Mac / 云 Mac。
#  怎么用：双击这个文件。或者终端里  ./一键打包.command
#
#  想要签名好的 ipa（能直接装）：
#      签名版：在 Xcode 里登录一个 Apple ID 后，本脚本会自动找 team 并签名。
#      也可以手动指定：TEAM_ID=ABCDE12345 ./一键打包.command
#
#  产物（会打印在最后，并自动在访达里打开）：
#      out/Shooter-unsigned.ipa    未签名（给 AltStore/Sideloadly/TrollStore 用）
#      out/Shooter.ipa             已签名（如果找得到 team）
# ===========================================================================
set -uo pipefail
cd "$(dirname "$0")" || exit 1

BUNDLE_ID="${BUNDLE_ID:-com.suicode.shooter}"
OUT="out"
LOG="$OUT/build.log"
mkdir -p "$OUT"

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }
die() { printf '\n\033[1;31m❌ %s\033[0m\n' "$1"; printf '详细日志: %s\n' "$LOG"; read -r -p "按回车关闭…" _; exit 1; }

# ---------------------------------------------------------------- 环境检查
if ! command -v xcodebuild >/dev/null 2>&1; then
  die "没装 Xcode。请从 App Store 安装 Xcode（不是 Command Line Tools），装完再双击本文件。"
fi
if ! xcodebuild -version >/dev/null 2>&1; then
  die "Xcode 还没初始化。先运行一次:  sudo xcodebuild -license accept"
fi
say "Xcode: $(xcodebuild -version | head -1)"

PROJ=""
for p in Shooter.xcodeproj */Shooter.xcodeproj; do
  [ -d "$p" ] && PROJ="$p" && break
done
[ -n "$PROJ" ] || die "找不到 Shooter.xcodeproj，请把整个 ios 目录一起拷过来。"
PROJDIR=$(dirname "$PROJ")
say "工程: $PROJ"

# ---------------------------------------------------------------- 1. 未签名 ipa
say "编译中（不签名，约 1-3 分钟）…"
rm -rf "$OUT/DerivedData"
xcodebuild \
  -project "$PROJ" -scheme Shooter -configuration Release -sdk iphoneos \
  -derivedDataPath "$OUT/DerivedData" -destination "generic/platform=iOS" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  build >"$LOG" 2>&1
[ $? -eq 0 ] || die "编译失败（把 $LOG 最后 40 行发回来就能定位）"

APP=$(find "$OUT/DerivedData/Build/Products/Release-iphoneos" -maxdepth 1 -name "*.app" | head -1)
[ -n "$APP" ] || die "编译跑完了但没找到 .app"
say "编译成功: $APP"

pack() { # $1 = 输出 ipa 名
  rm -rf "$OUT/Payload" "$OUT/$1"
  mkdir -p "$OUT/Payload"
  cp -R "$APP" "$OUT/Payload/Shooter.app"
  (cd "$OUT" && zip -qry "$1" Payload)
  rm -rf "$OUT/Payload"
}
pack "Shooter-unsigned.ipa"
say "未签名 ipa: $(pwd)/$OUT/Shooter-unsigned.ipa"

# ---------------------------------------------------------------- 2. 签名版（可选）
TEAM="${TEAM_ID:-}"
if [ -z "$TEAM" ]; then
  TEAM=$(security find-identity -v -p codesigning 2>/dev/null \
         | sed -n 's/.*"Apple Development: .*(\([A-Z0-9]\{10\}\))".*/\1/p' | head -1)
fi

if [ -n "$TEAM" ]; then
  say "找到签名 team $TEAM，开始签名编译…"
  xcodebuild \
    -project "$PROJ" -scheme Shooter -configuration Release -sdk iphoneos \
    -derivedDataPath "$OUT/DerivedData-signed" -destination "generic/platform=iOS" \
    CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_IDENTITY="Apple Development" \
    -allowProvisioningUpdates \
    PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
    build >>"$LOG" 2>&1
  SAPP="$OUT/DerivedData-signed/Build/Products/Release-iphoneos/Shooter.app"
  if [ -d "$SAPP" ]; then
    APP="$SAPP"
    pack "Shooter.ipa"
    say "已签名 ipa: $(pwd)/$OUT/Shooter.ipa"
  else
    printf '\n\033[1;33m⚠️  签名编译没成功，未签名 ipa 仍然可用（用 AltStore/Sideloadly 签）\033[0m\n'
  fi
else
  printf '\n\033[1;33m提示：没找到 Apple 签名身份，只出了未签名 ipa。\033[0m\n'
  printf '  要签好名的 ipa：Xcode → Settings → Accounts 登录 Apple ID 后重新双击本文件，\n'
  printf '  或者  TEAM_ID=你的TeamID ./一键打包.command\n'
fi

# ---------------------------------------------------------------- 完成
printf '\n\033[1;32m================ 打包完成 ================\033[0m\n'
ls -lh "$OUT"/*.ipa 2>/dev/null
printf '\n把上面这些 .ipa 发出去就行：\n'
printf '  · 未签名 → 用 AltStore / Sideloadly / TrollStore 装\n'
printf '  · 已签名 → 直接 AirDrop / 爱思助手 / 网页分发安装\n\n'
open "$OUT" 2>/dev/null || true
read -r -p "按回车关闭…" _
