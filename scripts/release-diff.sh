#!/bin/bash
#
# 두 커밋 사이에 App Store로 올릴 것이 바뀌었는지 판정한다. GitHub Actions가 출력을
# 그대로 `$GITHUB_OUTPUT`에 붙인다.
#
#   bash scripts/app-store/release-diff.sh <이전 커밋> <새 커밋>
#
#   build=true|false        빌드 번호가 바뀌었다 → 아카이브·업로드
#   metadata=true|false     fastlane/metadata가 바뀌었다 → 앱 정보 반영
#   screenshots=true|false  fastlane/screenshots가 바뀌었다 → 스크린샷 교체
#   version=, build_number= 새 커밋의 버전 (태그 이름에 쓴다)
#
# 빌드 번호를 기준으로 삼는다. 릴리스 스킬은 새 빌드를 올릴 때 빌드 번호를 늘 올리고,
# App Store Connect는 같은 번호를 두 번 받지 않는다.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

BASE="${1:?이전 커밋}"
HEAD="${2:?새 커밋}"
HERE="$(dirname "$0")"

read -r _ old_build < <(bash "$HERE/version.sh" get "$BASE" 2>/dev/null || echo "? ?")
read -r new_version new_build < <(bash "$HERE/version.sh" get "$HEAD")

changed() { git diff --quiet "$BASE" "$HEAD" -- "$1" && echo false || echo true; }

echo "build=$([ "$old_build" != "$new_build" ] && echo true || echo false)"
echo "metadata=$(changed fastlane/metadata)"
echo "screenshots=$(changed fastlane/screenshots)"
echo "version=$new_version"
echo "build_number=$new_build"
