#!/bin/bash
#
# 앱 버전·빌드 번호를 읽고 쓴다. 어디에 적혀 있는지는 설정의 `version`이 정한다.
#
#   bash scripts/app-store/version.sh get [커밋]       → "1.0.3 9"
#   bash scripts/app-store/version.sh set 1.0.4 10
#   bash scripts/app-store/version.sh next 1.0.4        → 새 빌드 번호 (version.build_scheme을 따른다)
#
# version.build_scheme (선택, 기본 plus-one)
#   plus-one         현재 빌드 + 1. 버전을 올려도 1로 되돌리지 않는다.
#   version-encoded  주×10000 + 부×1000 + 패치×100 + 회차(01~99). 같은 버전을 다시 올리면 회차 +1, 버전이 바뀌면 01.
#                    예) 1.0.6 첫 빌드 = 10601. 저장소가 버전에서 번호를 정하는 앱(예: Sweep)용.
#
# version.kind
#   plist     Info.plist에 숫자가 직접 적혀 있다 (CFBundleShortVersionString / CFBundleVersion)
#   build-setting  project.pbxproj나 .xcconfig의 MARKETING_VERSION / CURRENT_PROJECT_VERSION
#                  (Info.plist가 $(MARKETING_VERSION)을 가리키는 요즘 Xcode 기본 구성)
#   swift     Tuist Project.swift처럼 Swift 딕셔너리에 "MARKETING_VERSION": "1.0.1"로 적혀 있다
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
elif kind == "swift":
    # 타깃마다 한 줄씩 있다. 값이 서로 다르면 업로드 뒤에야 App Store Connect가 거절하니 여기서 멈춘다.
    def pick(k):
        found = re.findall(r"\"%s\"\s*:\s*\"([^\"]*)\"" % k, text)
        if len(set(found)) > 1:
            sys.exit(f"{k} 값이 타깃마다 다르다: {sorted(set(found))}")
        return re.search(r"\"%s\"\s*:\s*\"([^\"]*)\"" % k, text)
    v, b = pick("MARKETING_VERSION"), pick("CURRENT_PROJECT_VERSION")
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
elif kind == "swift":
    # 타깃마다 한 줄씩 있다(앱·확장). 모두 같은 값으로 맞춘다.
    for key, value in [("MARKETING_VERSION", version), ("CURRENT_PROJECT_VERSION", build)]:
        text, n = re.subn(r"(\"%s\"\s*:\s*\")[^\"]*(\")" % key, r"\g<1>%s\g<2>" % value, text)
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
  next)
    NEW="${2:?새 버전}"
    read -r CUR_V CUR_B < <(bash "$0" get)
    python3 - "$(cfg version.build_scheme)" "$NEW" "$CUR_V" "$CUR_B" <<'PY'
import sys
scheme, new, cur_v, cur_b = sys.argv[1:]
if scheme in ("", "plus-one"):
    print(int(cur_b) + 1)
elif scheme == "version-encoded":
    major, minor, patch = (list(map(int, new.split("."))) + [0, 0])[:3]
    base = major * 10000 + minor * 1000 + patch * 100
    seq = int(cur_b) - base + 1 if new == cur_v and base < int(cur_b) <= base + 99 else 1
    if not 1 <= seq <= 99: sys.exit("회차가 01~99를 벗어난다")
    print(base + seq)
else:
    sys.exit(f"알 수 없는 version.build_scheme: {scheme}")
PY
    ;;
  *)
    echo "사용법: version.sh get [커밋] | set <버전> <빌드> | next <새 버전>" >&2; exit 1 ;;
esac
