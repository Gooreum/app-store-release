#!/bin/bash
#
# 업로드가 끝난 릴리스를 카카오톡 방에 알린다. 영어 먼저, 그다음 한국어를 메시지 하나에 담는다.
# 업데이트 내용은 fastlane/metadata/<언어>/release_notes.txt에서 읽는다.
#
#   bash scripts/app-store/kakao-notify.sh [--dry-run]
#
# 방 이름은 설정 notify.kakao_room. 없으면 아무것도 하지 않는다.
# 알림이 실패해도 배포 결과는 바꾸지 않는다 — 경고만 찍고 0으로 끝난다.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
HERE="$(dirname "$0")"
[ -f .app-store-release.json ] || { echo "⚠️ 설정 파일이 없어 카톡 알림을 건너뜀" >&2; exit 0; }
. "$HERE/lib.sh"

ROOM=$(cfg notify.kakao_room)
[ -n "$ROOM" ] || { echo "설정에 notify.kakao_room이 없어 카톡 알림을 건너뜀"; exit 0; }

read -r VERSION BUILD < <(bash "$HERE/version.sh" get) || { echo "⚠️ 버전을 읽지 못해 카톡 알림을 건너뜀" >&2; exit 0; }
# 실제로 올라간 빌드만 알린다. 업로드가 끝나면 태그 v<버전>-<빌드>가 생긴다(dry-run은 확인만 하니 건너뛴다).
if [ "${1:-}" != --dry-run ]; then
  git fetch -q origin "refs/tags/v$VERSION-$BUILD:refs/tags/v$VERSION-$BUILD" 2>/dev/null || true
  git rev-parse -q --verify "refs/tags/v$VERSION-$BUILD" >/dev/null \
    || { echo "⚠️ 태그 v$VERSION-$BUILD가 없어(아직 안 올라감) 카톡 알림을 건너뜀" >&2; exit 0; }
fi
M=fastlane/metadata
name_en=$(cat "$M/en-US/name.txt" 2>/dev/null || cfg app_identifier)
name_ko=$(cat "$M/ko/name.txt" 2>/dev/null || echo "$name_en")
notes_en=$(cat "$M/en-US/release_notes.txt" 2>/dev/null || true)
notes_ko=$(cat "$M/ko/release_notes.txt" 2>/dev/null || true)

MSG="[$name_en Release]
Version: $VERSION (build $BUILD)
Status: Uploaded to App Store Connect (not yet submitted for review)

What's new
$notes_en

[$name_ko 배포]
버전: $VERSION (빌드 $BUILD)
구분: App Store Connect 업로드 완료 (심사 제출 전)

배포 내용
$notes_ko"

if ! bash "$HERE/kakao-send.sh" "$ROOM" "$MSG" "${1:-}"; then
  echo "⚠️ 카톡 알림 실패 — 배포는 그대로다. 필요하면 다시 돌린다: bash scripts/app-store/kakao-notify.sh" >&2
fi
exit 0
