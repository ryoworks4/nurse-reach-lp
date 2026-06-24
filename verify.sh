#!/usr/bin/env bash
# verify.sh — 静的HTML検証ループ（bash verify.sh で実行。exit 0 = PASS / 非0 = FAIL）
# 依存: bash + node + python3 stdlib のみ。
cd "$(dirname "$0")" || exit 1

# ===== プロジェクト固有パラメータ（コピー先で書き換えるのはここだけ）=====
HTML_MODE="list"                  # "list" = 下のリストのみ / "find" = 再帰検索
HTML_FILES="index.html privacy.html thanks.html company.html"           # HTML_MODE=list のとき有効（スペース区切り）
JS_FILES=""              # node --check 対象。無ければ ""
# ========================================================================

FAILS=0
fail() { echo "[FAIL] $1"; FAILS=$((FAILS+1)); }
ok()   { echo "[ ok ] $1"; }

check_html() {
  python3 - "$1" <<'PYEOF'
import re, sys, pathlib, urllib.parse
p = pathlib.Path(sys.argv[1])
t = p.read_text(encoding='utf-8')
errs = []
if not re.search(r'<html[^>]*\blang=', t): errs.append('<html lang=...> が無い')
if not re.search(r'<title>[^<]+</title>', t): errs.append('<title> が無い')
i = t.rfind('</html>')
if i < 0: errs.append('</html> が無い')
elif t[i+7:].strip(): errs.append('</html> の後に残骸: %r' % t[i+7:].strip()[:40])
for m in re.finditer(r'(?:href|src)="([^"]+)"', t):
    ref = m.group(1)
    if ref.startswith(('http://','https://','mailto:','tel:','#','data:','//','javascript:')):
        continue
    ref = urllib.parse.unquote(ref.split('#')[0].split('?')[0])
    if ref and not (p.parent / ref).exists():
        errs.append('参照先が存在しない: ' + ref)
for e in errs: print('       - ' + e)
sys.exit(1 if errs else 0)
PYEOF
}

echo "== V1: HTML 検査（lang/title/残骸/参照切れ）=="
if [ "$HTML_MODE" = "find" ]; then
  while IFS= read -r f; do
    if check_html "$f"; then ok "$f"; else fail "$f"; fi
  done < <(find . -name "*.html" -not -path "./.git/*" -not -path "./node_modules/*" | sort)
else
  for f in $HTML_FILES; do
    if check_html "$f"; then ok "$f"; else fail "$f"; fi
  done
fi

echo "== V2: JS 構文 (node --check) =="
for f in $JS_FILES; do
  if node --check "$f" 2>/dev/null; then ok "$f"
  else node --check "$f"; fail "$f 構文エラー"; fi
done

echo "== V3: API キー直書き検出 =="
LEAK=$(grep -rnE "AIza|sk-ant-" --include="*.js" --include="*.html" \
       --exclude-dir=node_modules --exclude-dir=.git . 2>/dev/null | grep -v "verify.sh")
if [ -n "$LEAK" ]; then echo "$LEAK"; fail "API キー直書きの疑い"
else ok "鍵直書きなし"; fi

echo
if [ "$FAILS" -eq 0 ]; then echo "VERIFY PASS"; exit 0
else echo "VERIFY FAIL ($FAILS 件)"; exit 1; fi
