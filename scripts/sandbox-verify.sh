#!/usr/bin/env bash
# sandbox-exec profile 的成對驗證（M5 第 ③ 段）。
#
# ⚠️ **只測「擋得住」會得到假的通過。**
# (deny default) 之下被 exec 的程式連 dyld 都讀不到，幾乎任何東西都會失敗——
# 一個「什麼都擋」的壞 profile 會通過每一條負向測試。
#
# 第一次真機實測就是這樣：沙箱內每一條都回 rc=134（Abort trap: 6），
# 包括**應該放行**的正向案例。同樣的 rc 出現在兩邊，代表那些「擋住」全是
# 程式根本沒起來，不是 profile 擋的。
#
# 因此這個腳本有三條規矩：
#   1. **負向結果依賴正向基準**。正向基準沒過 → 所有負向一律標「無效」，不准報通過。
#   2. **失敗要印 stderr**。看不到 dyld 抱怨什麼就只能猜。
#   3. 無沙箱對照組若失敗，該條也是「無效」——測不出東西就不要假裝測到了。
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WS="$(mktemp -d /tmp/copartner-sbpl-ws.XXXXXX)"
OUTSIDE="$(mktemp -d /tmp/copartner-sbpl-outside.XXXXXX)"
PROFILE="$(mktemp /tmp/copartner-sbpl.XXXXXX.sb)"
PROFILE_NO_RUNTIME="$(mktemp /tmp/copartner-sbpl-nort.XXXXXX.sb)"
ERRLOG="$(mktemp /tmp/copartner-sbpl-err.XXXXXX)"
cleanup() { rm -rf "${WS}" "${OUTSIDE}" "${PROFILE}" "${PROFILE_NO_RUNTIME}" "${ERRLOG}"; }
trap cleanup EXIT

mkdir -p "${WS}/.secrets"
echo "workspace content" > "${WS}/hello.txt"
echo "SECRET" > "${WS}/.secrets/token"
echo "outside content" > "${OUTSIDE}/other.txt"

# exec 白名單刻意包含 curl：這樣「網路被擋」與「執行被擋」才分得開。
ALLOWED_CAT=/bin/cat
ALLOWED_TOUCH=/usr/bin/touch
ALLOWED_CURL=/usr/bin/curl
NOT_ALLOWED=/bin/date

echo "產生 profile（來源：SbplProfileBuilder，非腳本自己拼）…"
swift run --package-path "${REPO_ROOT}/packages/CoPartnerKit" copartner-sbpl \
  --workspace "${WS}" \
  --exec "${ALLOWED_CAT}" --exec "${ALLOWED_TOUCH}" --exec "${ALLOWED_CURL}" \
  --deny "${WS}/.secrets" > "${PROFILE}" || { echo "❌ 產生 profile 失敗"; exit 2; }

swift run --package-path "${REPO_ROOT}/packages/CoPartnerKit" copartner-sbpl \
  --workspace "${WS}" --exec "${ALLOWED_CAT}" --no-runtime-minimum \
  > "${PROFILE_NO_RUNTIME}" 2>/dev/null

echo
echo "── profile ──"
cat "${PROFILE}"
echo "─────────────"
echo

pass=0; fail=0; invalid=0

# 為什麼不能只靠子程序的 stderr：
# `(deny default)` 連**寫到終端機**都擋，所以 dyld 抱怨的那句話根本吐不出來，
# 只剩 SIGABRT。真機第一輪就是這樣——ERRLOG 全空。
# 沙箱的拒絕紀錄在**統一日誌**裡，那條路不依賴子程序有沒有辦法開口。
show_diagnostics() {
  if [ -s "${ERRLOG}" ]; then
    echo "        stderr: $(head -c 400 "${ERRLOG}" | tr '\n' ' ')"
  else
    echo "        stderr: （空——沙箱可能連寫終端機都擋掉了）"
  fi
  local denials
  denials="$(log show --last 20s --style compact \
              --predicate 'eventMessage CONTAINS "deny"' 2>/dev/null \
             | grep -vi 'sandbox-verify' | tail -8)"
  if [ -n "${denials}" ]; then
    echo "        統一日誌裡的拒絕紀錄："
    echo "${denials}" | sed 's/^/          /'
  else
    echo "        統一日誌：20 秒內沒有 deny 紀錄（可能需要 sudo，或訊息不含 deny 字樣）"
  fi
}

sandboxed() { sandbox-exec -f "${PROFILE}" "$@" >/dev/null 2>"${ERRLOG}"; }

# ── 步驟 1：正向基準 ──────────────────────────────────────────────
# 一個「連最基本的允許操作都跑不起來」的 profile，其負向結果一律沒有意義。
echo "步驟 1／基準：允許的操作在沙箱內跑得起來嗎？"
baseline_ok=1
if sandboxed "${ALLOWED_CAT}" "${WS}/hello.txt"; then
  echo "  ✅ 讀工作目錄內的檔案 — 沙箱內成功"
  pass=$((pass+1))
else
  rc=$?
  echo "  ❌ 讀工作目錄內的檔案 — 沙箱內失敗 (rc=${rc})"
  show_diagnostics
  baseline_ok=0
  fail=$((fail+1))
fi
if sandboxed "${ALLOWED_TOUCH}" "${WS}/created"; then
  echo "  ✅ 寫工作目錄內的檔案 — 沙箱內成功"
  pass=$((pass+1))
else
  rc=$?
  echo "  ❌ 寫工作目錄內的檔案 — 沙箱內失敗 (rc=${rc})"
  show_diagnostics
  baseline_ok=0
  fail=$((fail+1))
fi

echo
if [ ${baseline_ok} -eq 0 ]; then
  echo "步驟 2／負向：**全部標為無效**。"
  echo "  基準都跑不起來，任何「被擋住」都無法歸因於 profile 的規則——"
  echo "  那只是程式沒能啟動。先把上面的 stderr 修好，這些才有意義。"
fi

# run_deny <名稱> <指令…>：無沙箱應成功、沙箱內應失敗。
run_deny() {
  local name="$1"; shift
  local bare_rc sandboxed_rc
  "$@" >/dev/null 2>&1; bare_rc=$?
  sandboxed "$@"; sandboxed_rc=$?

  if [ ${bare_rc} -ne 0 ]; then
    printf '  ⚠️  無效  %-30s 無沙箱就失敗了(rc=%d)，無法歸因\n' "${name}" "${bare_rc}"
    invalid=$((invalid+1))
  elif [ ${baseline_ok} -eq 0 ]; then
    printf '  ⚠️  無效  %-30s 沙箱 rc=%d，但基準未通過 → 不算擋住\n' "${name}" "${sandboxed_rc}"
    invalid=$((invalid+1))
  elif [ ${sandboxed_rc} -ne 0 ]; then
    printf '  ✅ 擋住  %-30s 無沙箱 rc=0 / 沙箱 rc=%d\n' "${name}" "${sandboxed_rc}"
    pass=$((pass+1))
  else
    printf '  ❌ 沒擋  %-30s 沙箱內照樣成功\n' "${name}"
    fail=$((fail+1))
  fi
}

[ ${baseline_ok} -eq 1 ] && echo "步驟 2／負向：禁止的事必須失敗，且無沙箱時要成功"
run_deny "網路（curl 可執行但應斷網）" "${ALLOWED_CURL}" -s -m 5 -o /dev/null https://example.com
run_deny "讀工作目錄外的檔案"          "${ALLOWED_CAT}" "${OUTSIDE}/other.txt"
run_deny "寫工作目錄外的檔案"          "${ALLOWED_TOUCH}" "${OUTSIDE}/probe"
run_deny "讀工作目錄內的秘密子路徑"    "${ALLOWED_CAT}" "${WS}/.secrets/token"
run_deny "執行白名單外的程式"          "${NOT_ALLOWED}"

# ── 步驟 3：runtime 最小集合到底有沒有用 ──────────────────────────
echo
echo "步驟 3／對照：拿掉 runtime 最小讀取集合"
if sandbox-exec -f "${PROFILE_NO_RUNTIME}" "${ALLOWED_CAT}" "${WS}/hello.txt" >/dev/null 2>&1; then
  echo "  ⚠️  竟然跑得起來 → runtimeReadSubpaths 是多餘的，應該拿掉（寧可少放）"
else
  if [ ${baseline_ok} -eq 1 ]; then
    echo "  ✅ 跑不起來 → 證明 runtimeReadSubpaths 確實必要"
  else
    echo "  ⚠️  跑不起來，但有它也跑不起來 → 這個對照現在沒有資訊量"
  fi
fi

echo
echo "結果：通過 ${pass}、失敗 ${fail}、無效 ${invalid}"
if [ ${baseline_ok} -eq 0 ]; then
  echo
  echo "下一步：把上面基準案例的 stderr 貼回來。dyld 少什麼它會直說，"
  echo "        比繼續猜 runtimeReadSubpaths 該放哪些路徑快得多。"
fi

[ ${fail} -eq 0 ] && [ ${invalid} -eq 0 ]
