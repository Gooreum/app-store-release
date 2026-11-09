#!/bin/bash
#
# 맥 카카오톡 방에 메시지 하나를 보낸다. 개인 카카오톡에는 보내기 API가 없어 접근성(UI 자동화)으로 한다.
#
#   bash scripts/app-store/kakao-send.sh <방 이름> <메시지> [--dry-run]
#
# 조건: 맥, 카카오톡 로그인, 이 스크립트를 부르는 터미널에 접근성 권한, cliclick(방을 처음 열 때만).
# 카카오톡을 잠깐 앞으로 가져온다(몇 초). 보낸 뒤 원래 앞에 있던 앱으로 되돌린다.
# --dry-run은 입력창에 넣어 확인한 뒤 비우고 보내지 않는다.
# 입력창에 값을 넣고 Return으로 보낸다. 방 창이 이미 열려 있으면 검색·좌표 클릭 없이 바로 보낸다.
# 방 창이 없을 때만 메인 창에서 검색하고 첫 결과를 좌표로 더블클릭한다.
set -euo pipefail
ROOM="${1:?방 이름}"; MSG="${2:?메시지}"; MODE="${3:-send}"

PREV=$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null || true)
restore() { [ -n "$PREV" ] && [ "$PREV" != KakaoTalk ] && osascript -e "tell application \"System Events\" to set frontmost of process \"$PREV\" to true" >/dev/null 2>&1 || true; }
trap restore EXIT

has_room() { osascript - "$ROOM" <<'AS' 2>/dev/null
on run argv
  tell application "System Events" to tell process "KakaoTalk" to return (exists window (item 1 of argv)) as text
end run
AS
}

osascript -e 'tell application "KakaoTalk" to reopen' -e 'tell application "KakaoTalk" to activate' >/dev/null
sleep 0.5

# 방 창이 없으면 메인 창에서 검색해 첫 결과를 연다. 창 제목이 방 이름과 같은지 아래에서 다시 본다.
if [ "$(has_room)" != true ]; then
  POS=$(osascript - "$ROOM" <<'AS'
on run argv
  tell application "System Events" to tell process "KakaoTalk"
    repeat 20 times
      if exists window "카카오톡" then exit repeat
      delay 0.25
    end repeat
    set w to window "카카오톡"
    if (count of text fields of w) is 0 then
      click (first button of w whose description is "검색")
      delay 0.5
    end if
    set value of (first text field of w) to (item 1 of argv)
    delay 1
    set {x, y} to position of w
    set {ww, wh} to size of w
    return (x as text) & " " & (y as text) & " " & (ww as text) & " " & (wh as text)
  end tell
end run
AS
)
  # AppleScript 목록은 "x, y, w, h"처럼 온다. 보조 모니터가 왼쪽·위에 있으면 음수다.
  read -r X Y W H < <(printf '%s' "$POS" | grep -oE -- '-?[0-9]+' | head -4 | paste -sd' ' -)
  CX=$((X+490)); CY=$((Y+125))
  if [ -z "${H:-}" ] || [ "$CX" -ge $((X+W)) ] || [ "$CY" -ge $((Y+H)) ]; then
    echo "검색 결과 위치가 메인 창 밖이다 — 클릭하지 않는다 ($POS)" >&2; exit 1
  fi
  cliclick "dc:=$CX,=$CY"  # = 를 붙여야 음수도 절대 좌표로 받는다
  for _ in 1 2 3 4 5 6 7 8; do [ "$(has_room)" = true ] && break; sleep 0.25; done
fi

OUT=$(osascript - "$ROOM" "$MSG" "$MODE" <<'AS'
on run argv
  set room to item 1 of argv
  -- 카카오톡이 앞에 없으면 창이 접근성 트리에서 잠깐 사라진다. 앞으로 가져오고 창과 입력창이 잡힐 때까지 기다린다.
  tell application "KakaoTalk" to activate
  tell application "System Events" to tell process "KakaoTalk"
    set ta to missing value
    repeat 20 times
      try
        perform action "AXRaise" of window room
        set ta to text area 1 of scroll area 2 of window room
        exit repeat
      end try
      delay 0.15
    end repeat
    if ta is missing value then error "방 창이 열리지 않음: " & room
    set value of ta to (item 2 of argv)
    -- 값이 반영될 때까지 잠깐 기다린다(긴 문구는 늦게 들어온다)
    repeat 10 times
      if (value of ta) is (item 2 of argv) then exit repeat
      delay 0.15
    end repeat
    if (value of ta) is not (item 2 of argv) then
      set value of ta to ""
      error "입력창 값 불일치"
    end if
    if (item 3 of argv) is "--dry-run" then
      set value of ta to ""
      return "DRY-RUN OK (" & room & ")"
    end if
    -- Return은 맨 앞 앱으로 간다. 그 사이 사용자가 다른 앱을 눌렀을 수 있으니 바로 앞에서 다시 확인한다.
    set frontmost to true
    delay 0.2
    if not frontmost then
      set value of ta to ""
      error "카카오톡을 앞으로 가져오지 못해 보내지 않음"
    end if
    set focused of ta to true
    key code 36
    delay 0.8
    if (value of ta) is not "" then
      set value of ta to ""
      error "전송 실패: 입력창에 문구가 남음(Enter 줄바꿈 설정일 수 있다)"
    end if
    return "SENT OK (" & room & ")"
  end tell
end run
AS
)
echo "$OUT"
