#!/usr/bin/env bash
# sandbox-exec profile 的成對驗證（M5 第 ③ 段）。
#
# ⚠️ **只測「擋得住」會得到假的通過。**
# (deny default) 之下被 exec 的程式連 dyld 都讀不到，幾乎任何東西都會失敗——
# 一個「什麼都擋」的壞 profile 會通過每一條負向測試。所以每條規則都要雙向驗：
#
#   負向：禁止的事在沙箱內失敗，**而且無沙箱時成功**（證明是 profile 擋的，
#         不是那件事本來就會失敗）
#   正向：允許的事在沙箱內**仍然成功**（證明 profile 沒把該放的也擋掉）
#
# 沒有無沙箱對照組的負向測試不算數，這裡會標成「無效」而不是「通過」。
#
# 用法：./scripts/sandbox-verify.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WS="$(mktemp -d /tmp/copartner-sbpl-ws.XXXXXX)"
OUTSIDE="$(mktemp -d /tmp/copartner-sbpl-outside.XXXXXX)"
PROFILE="$(mktemp /tmp/copartner-sbpl.XXXXXX.sb)"
PROFILE_NO_RUNTIME="$(mktemp /tmp/copartner-sbpl-nort.XXXXXX.sb)"
cleanup() { rm -rf "$WS" "$OUTSIDE" "$PROFILE" "$PROFILE_NO_RUNTIME"; }
trap cleanup EXIT

mkdir -p "$WS/.secrets"
echo "workspace content" > "$WS/hello.txt"
echo "SECRET" > "$WS/.secrets/token"
echo "outside content" > "$OUTSIDE/other.txt"

# exec 白名單刻意包含 curl：這樣「網路被擋」與「執行被擋」才分得開。
# 少了這一步，網路測試失敗可能只是因為 curl 根本不准執行。
ALLOWED_CAT=/bin/cat
ALLOWED_TOUCH=/usr/bin/touch
ALLOWED_CURL=/usr/bin/curl
NOT_ALLOWED=/bin/date

echo "產生 profile（來源：SbplProfileBuilder，非腳本自己拼）…"
swift run --package-path "$REPO_ROOT/packages/CoPartnerKit" copartner-sbpl \
  --workspace "$WS" \
  --exec "$ALLOWED_CAT" --exec "$ALLOWED_TOUCH" --exec "$ALLOWED_CURL" \
  --deny "$WS/.secrets" > "$PROFILE" || { echo "❌ 產生 profile 失敗"; exit 2; }

swift run --package-path "$REPO_ROOT/packages/CoPartnerKit" copartner-sbpl \
  --workspace "$WS" --exec "$ALLOWED_CAT" --no-runtime-minimum > "$PROFILE_NO_RUNTIME" 2>/dev/null

echo
echo "── profile ──"
cat "$PROFILE"
echo "─────────────"
echo

pass=0; fail=0; invalid=0

# run_case <名稱> <deny|allow> <指令…>
#   deny  = 無沙箱應成功、沙箱內應失敗
#   allow = 沙箱內應成功
run_case() {
  local name="$1"; local expect="$2"; shift 2
  local bare_rc sandboxed_rc
  "$@" >/dev/null 2>&1; bare_rc=$?
  sandbox-exec -f "$PROFILE" "$@" >/dev/null 2>&1; sandboxed_rc=$?

  if [ "$expect" = "deny" ]; then
    if [ $bare_rc -ne 0 ]; then
      # 對照組就失敗 → 這條測不出任何東西，不可當成通過
      printf '  ⚠️  無效  %-34s 無沙箱就失敗了(rc=%d)，無法歸因於 profile\n' "$name" "$bare_rc"
      invalid=$((invalid+1))
    elif [ $sandboxed_rc -ne 0 ]; then
      printf '  ✅ 擋住  %-34s 無沙箱 rc=0 / 沙箱 rc=%d\n' "$name" "$sandboxed_rc"
      pass=$((pass+1))
    else
      printf '  ❌ 沒擋  %-34s 沙箱內照樣成功\n' "$name"
      fail=$((fail+1))
    fi
  else
    if [ $sandboxed_rc -eq 0 ]; then
      printf '  ✅ 放行  %-34s 沙箱內仍成功\n' "$name"
      pass=$((pass+1))
    else
      printf '  ❌ 誤殺  %-34s 沙箱內失敗(rc=%d)——profile 把該放的也擋了\n' "$name" "$sandboxed_rc"
      fail=$((fail+1))
    fi
  fi
}

echo "正向（允許的事必須仍然成功——沒有這組，負向全過也不代表什麼）"
run_case "讀工作目錄內的檔案"        allow "$ALLOWED_CAT" "$WS/hello.txt"
run_case "寫工作目錄內的檔案"        allow "$ALLOWED_TOUCH" "$WS/created"
echo
echo "負向（禁止的事必須失敗，且無沙箱時要成功）"
run_case "網路（curl 可執行但應斷網）" deny "$ALLOWED_CURL" -s -m 5 -o /dev/null https://example.com
run_case "讀工作目錄外的檔案"        deny "$ALLOWED_CAT" "$OUTSIDE/other.txt"
run_case "寫工作目錄外的檔案"        deny "$ALLOWED_TOUCH" "$OUTSIDE/probe"
run_case "讀工作目錄內的秘密子路徑"  deny "$ALLOWED_CAT" "$WS/.secrets/token"
run_case "執行白名單外的程式"        deny "$NOT_ALLOWED"

echo
echo "對照實驗：沒有 runtime 最小讀取集合時，正向案例應該連跑都跑不起來"
if sandbox-exec -f "$PROFILE_NO_RUNTIME" "$ALLOWED_CAT" "$WS/hello.txt" >/dev/null 2>&1; then
  echo "  ⚠️  竟然跑得起來——代表 runtimeReadSubpaths 是多餘的，應該拿掉（寧可少放）"
else
  echo "  ✅ 跑不起來——證明 runtimeReadSubpaths 確實是必要的，不是憑感覺加的"
fi

echo
echo "結果：通過 $pass、失敗 $fail、無效 $invalid"
echo
echo "「讀工作目錄內的秘密子路徑」這條特別重要：它驗的是 sbpl「最後一條相符的規則勝出」。"
echo "秘密路徑就在工作目錄底下，allow 在前、deny 在後——擋不住就代表順序假設是錯的，"
echo "那會讓 ~/.ssh 之類的路徑在工作目錄底下時完全不受保護。"

[ $fail -eq 0 ] && [ $invalid -eq 0 ]
