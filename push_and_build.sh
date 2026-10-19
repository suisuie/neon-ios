#!/data/data/suicode.cn/files/usr/bin/bash
# ===========================================================================
#  一部手机搞定：建仓库 → 推送 → 云端编译 → 自动下载 ipa
#
#  用法（在 岁code 的 Terminal 里，或 Termux 里）：
#
#     bash push_and_build.sh ghp_你的token
#
#  只需要一个 GitHub Token（下面步骤 3 教你怎么拿，1 分钟）。
#  跑完最后会打印 ipa 的完整路径。
# ===========================================================================
set -uo pipefail
cd "$(dirname "$0")"

REPO="${REPO:-neon-ios}"
TOKEN="${1:-${GH_TOKEN:-}}"
API="https://api.github.com"

red()  { printf '\033[1;31m%s\033[0m\n' "$*"; }
grn()  { printf '\033[1;32m%s\033[0m\n' "$*"; }
cyn()  { printf '\033[1;36m%s\033[0m\n' "$*"; }
step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

if [ -z "$TOKEN" ]; then
  red "缺少 Token。"
  echo "用法: bash push_and_build.sh ghp_xxxxxxxx"
  echo "拿 Token: 浏览器打开 https://github.com/settings/tokens/new"
  echo "  勾选 repo 和 workflow 两项，生成后复制那串 ghp_ 开头的字符"
  exit 1
fi

command -v curl >/dev/null || { red "没有 curl"; exit 1; }
command -v git  >/dev/null || { red "没有 git"; exit 1; }
command -v python3 >/dev/null || { red "没有 python3"; exit 1; }

# ------------------------------------------------------------------ 0. 身份
step "0/5 校验 Token"
ME=$(curl -sS -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" "$API/user")
USER=$(printf '%s' "$ME" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("login",""))' 2>/dev/null)
if [ -z "$USER" ]; then
  red "Token 无效或没有权限。返回："
  printf '%s\n' "$ME" | head -5
  exit 1
fi
grn "登录身份: $USER"

# ------------------------------------------------------------------ 1. 建仓库
step "1/5 创建仓库 $USER/$REPO"
CODE=$(curl -sS -o /tmp/repo.json -w '%{http_code}' -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/vnd.github+json" \
  "$API/user/repos" \
  -d "{\"name\":\"$REPO\",\"private\":true,\"description\":\"霓虹突击 iOS\"}")
if [ "$CODE" = "201" ]; then
  grn "仓库已创建: https://github.com/$USER/$REPO"
elif [ "$CODE" = "422" ]; then
  cyn "仓库已存在，直接复用: https://github.com/$USER/$REPO"
else
  red "建仓库失败 HTTP $CODE"; head -c 400 /tmp/repo.json; echo; exit 1
fi

# ------------------------------------------------------------------ 2. 推送
step "2/5 推送代码"
if [ ! -d .git ]; then
  red "当前目录不是 git 仓库（应该在 shooter/ios 下运行本脚本）"; exit 1
fi
git remote remove origin 2>/dev/null || true
git remote add origin "https://$USER:$TOKEN@github.com/$USER/$REPO.git"
git branch -M main
if git push -u origin main --force 2>&1 | tail -5; then
  grn "推送完成"
else
  red "推送失败。常见原因：Token 没勾 workflow 权限（要推 .github/workflows 必须勾）"
  exit 1
fi
# 别把 token 留在 .git/config 里
git remote set-url origin "https://github.com/$USER/$REPO.git"

# ------------------------------------------------------------------ 3. 等编译
step "3/5 等待云端编译（首次约 8-15 分钟）"
RUN_ID=""
for i in $(seq 1 90); do
  sleep 20
  RUNS=$(curl -sS -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" \
    "$API/repos/$USER/$REPO/actions/runs?per_page=1")
  RUN_ID=$(printf '%s' "$RUNS" | python3 -c 'import sys,json;r=json.load(sys.stdin).get("workflow_runs",[]);print(r[0]["id"] if r else "")' 2>/dev/null)
  ST=$(printf '%s' "$RUNS" | python3 -c 'import sys,json;r=json.load(sys.stdin).get("workflow_runs",[]);print(r[0].get("status","") if r else "")' 2>/dev/null)
  CN=$(printf '%s' "$RUNS" | python3 -c 'import sys,json;r=json.load(sys.stdin).get("workflow_runs",[]);print((r[0].get("conclusion") or "") if r else "")' 2>/dev/null)
  printf '  [%02d] status=%s conclusion=%s\n' "$i" "${ST:-等待}" "${CN:-—}"
  if [ "$ST" = "completed" ]; then break; fi
done

if [ "$CN" != "success" ]; then
  red "编译没成功（conclusion=$CN）"
  echo "看日志: https://github.com/$USER/$REPO/actions/runs/$RUN_ID"
  echo "把失败那一步的最后 20 行发回来就能定位。"
  exit 1
fi
grn "编译成功"

# ------------------------------------------------------------------ 4. 下载产物
step "4/5 下载 ipa"
ARTS=$(curl -sS -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" \
  "$API/repos/$USER/$REPO/actions/runs/$RUN_ID/artifacts")
AID=$(printf '%s' "$ARTS" | python3 -c 'import sys,json;a=json.load(sys.stdin).get("artifacts",[]);print(a[0]["id"] if a else "")' 2>/dev/null)
if [ -z "$AID" ]; then
  red "这次运行没有产物（artifact）。看日志: https://github.com/$USER/$REPO/actions/runs/$RUN_ID"
  exit 1
fi
rm -rf out/github out/gh.zip
mkdir -p out
curl -sSL -H "Authorization: Bearer $TOKEN" \
  "$API/repos/$USER/$REPO/actions/artifacts/$AID/zip" -o out/gh.zip
python3 - <<'PY'
import zipfile, os, shutil
os.makedirs('out/github', exist_ok=True)
with zipfile.ZipFile('out/gh.zip') as z:
    z.extractall('out/github')
for root, dirs, files in os.walk('out/github'):
    for f in files:
        if f.endswith('.ipa'):
            src = os.path.join(root, f)
            dst = os.path.join('out', 'Shooter-unsigned.ipa')
            shutil.copy2(src, dst)
            print("ipa:", os.path.abspath(dst), os.path.getsize(dst), "bytes")
PY

# ------------------------------------------------------------------ 5. 收尾
step "5/5 完成"
if [ -f out/Shooter-unsigned.ipa ]; then
  cp out/Shooter-unsigned.ipa "$HOME/storage/downloads/Shooter-unsigned.ipa" 2>/dev/null || true
  grn "ipa: $(pwd)/out/Shooter-unsigned.ipa"
  grn "也复制到了: /storage/emulated/0/Download/Shooter-unsigned.ipa"
  echo
  echo "仓库地址: https://github.com/$USER/$REPO"
  echo
  echo "装到 iPhone（三选一）:"
  echo "  1) iOS<=17.0 且有 TrollStore: 把 ipa 传过去，TrollStore 里点 Install，永久"
  echo "  2) 有 Windows 电脑: Sideloadly 选这个 ipa + 自己的 Apple ID，签完 7 天有效"
  echo "  3) 纯手机: 买张个人证书，用 全能签/ESign 在手机上签这个 ipa"
else
  red "没在产物里找到 .ipa，检查 out/gh.zip"
  exit 1
fi
