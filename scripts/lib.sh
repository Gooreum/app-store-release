#!/bin/bash
# app-store-release 공통 함수. 다른 스크립트가 `. scripts/app-store/lib.sh`로 읽는다.
#
# 설정 파일: 저장소 루트의 `.app-store-release.json` (APP_STORE_RELEASE_CONFIG로 바꿀 수 있다)

CONFIG="${APP_STORE_RELEASE_CONFIG:-.app-store-release.json}"
[ -f "$CONFIG" ] || { echo "설정 파일이 없다: $CONFIG — app-store-release 스킬의 설정 단계를 먼저 하라" >&2; exit 1; }

# 점으로 이은 키의 값을 읽는다. 없으면 빈 문자열. 목록·객체는 JSON으로.
#   cfg archive.scheme
cfg() {
  python3 - "$CONFIG" "$1" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for k in sys.argv[2].split("."):
    d = d.get(k, "") if isinstance(d, dict) else ""
print(json.dumps(d, ensure_ascii=False) if isinstance(d, (list, dict)) else d)
PY
}
