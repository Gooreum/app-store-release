#!/bin/bash
#
# 앱 버전·빌드 번호를 읽고 쓴다. 어디에 적혀 있는지는 설정의 `version`이 정한다.
#
#   bash scripts/app-store/version.sh get [커밋]       → "1.0.3 9"
#   bash scripts/app-store/version.sh set 1.0.4 10
#
# version.kind
#   plist     Info.plist에 숫자가 직접 적혀 있다 (CFBundleShortVersionString / CFBundleVersion)
#   build-setting  project.pbxproj나 .xcconfig의 MARKETING_VERSION / CURRENT_PROJECT_VERSION
#                  (Info.plist가 $(MARKETING_VERSION)을 가리키는 요즘 Xcode 기본 구성)
#
# 쓰기는 정규식으로 그 줄만 바꾼다. PlistBuddy·plutil은 파일을 통째로 다시 써서
# 주석과 키 순서를 망친다.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
. "$(dirname "$0")/lib.sh"

KIND=$(cfg version.kind)
FILE=$(cfg version.file)
[ -n "$KIND" ] && [ -n "$FILE" ] || { echo "설정에 version.kind·version.file이 필요하다" >&2; exit 1; }

case "${1:-}" in
  get)
    if [ -n "${2:-}" ]; then content=$(git show "$2:$FILE"); else content=$(cat "$FILE"); fi
    printf '%s' "$content" | python3 -c '
import re, sys
kind, text = sys.argv[1], sys.stdin.read()
if kind == "plist":
    pick = lambda k: re.search(r"<key>%s</key>\s*<string>([^<]*)</string>" % k, text)
    v, b = pick("CFBundleShortVersionString"), pick("CFBundleVersion")
else:
    pick = lambda k: re.search(r"\b%s\s*=\s*\"?([^;\"\n]+?)\"?\s*(;|$)" % k, text, re.M)
    v, b = pick("MARKETING_VERSION"), pick("CURRENT_PROJECT_VERSION")
if not (v and b):
    sys.exit("버전·빌드 번호를 찾지 못했다")
print(v.group(1).strip(), b.group(1).strip())
' "$KIND"
    ;;
  set)
    VERSION="${2:?버전}"; BUILD="${3:?빌드 번호}"
    for n in "$VERSION" "$BUILD"; do
      [[ "$n" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || { echo "'$n' — 정수 1~3개를 점으로 이은 형식이어야 한다" >&2; exit 1; }
    done
    python3 - "$KIND" "$FILE" "$VERSION" "$BUILD" <<'PY'
import re, sys
kind, path, version, build = sys.argv[1:]
text = open(path).read()
if kind == "plist":
    pairs = [("CFBundleShortVersionString", version), ("CFBundleVersion", build)]
    for key, value in pairs:
        text, n = re.subn(r"(<key>%s</key>\s*<string>)[^<]*(</string>)" % key, r"\g<1>%s\g<2>" % value, text)
        if n == 0: sys.exit(f"{key}를 찾지 못했다: {path}")
else:
    # 타깃·구성마다 한 줄씩 있다. 모두 같은 값으로 맞춘다.
    for key, value in [("MARKETING_VERSION", version), ("CURRENT_PROJECT_VERSION", build)]:
        text, n = re.subn(r"(\b%s\s*=\s*)\"?[^;\"\n]+?\"?(\s*(;|$))" % key, r"\g<1>%s\g<2>" % value, text, flags=re.M)
        if n == 0: sys.exit(f"{key}를 찾지 못했다: {path}")
open(path, "w").write(text)
PY
    bash "$0" get
    ;;
  *)
    echo "사용법: version.sh get [커밋] | set <버전> <빌드>" >&2; exit 1 ;;
esac
