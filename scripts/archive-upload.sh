#!/bin/bash
#
# 아카이브를 만들어 App Store Connect에 올린다. Organizer의
# Distribute App → App Store Connect → Upload와 같은 일이다.
#
#   bash scripts/app-store/archive-upload.sh
#
# 로컬에서는 Xcode에 로그인된 계정으로 서명한다. CI처럼 계정이 없으면 API 키를 준다 —
# 그 키로 배포 인증서·프로파일을 받는다(클라우드 서명, 키 권한이 Admin이어야 한다):
#
#   ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_KEY_PATH=…/AuthKey_….p8 bash scripts/app-store/archive-upload.sh
#
# DESTINATION=export면 올리지 않고 서명된 결과물만 만든다 — 서명이 되는지만 볼 때.
#
# 설정 archive.command가 있으면 아카이브는 그 명령이 만들고(archive.path에 둔다),
# 없으면 archive.workspace|project + archive.scheme으로 xcodebuild archive를 돌린다.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
HERE="$(dirname "$0")"
. "$HERE/lib.sh"

ARCHIVE="$(cfg archive.path)"; ARCHIVE="${ARCHIVE:-build/app-store/App.xcarchive}"
EXPORT=build/app-store/export
PLATFORM=$(cfg platform)
TEAM_ID=$(cfg team_id)

AUTH=()
if [ -n "${ASC_KEY_PATH:-}" ]; then
  AUTH=(-authenticationKeyPath "$ASC_KEY_PATH"
        -authenticationKeyID "${ASC_KEY_ID:?ASC_KEY_ID}"
        -authenticationKeyIssuerID "${ASC_ISSUER_ID:?ASC_ISSUER_ID}")
fi

read -r VERSION BUILD < <(bash "$HERE/version.sh" get)
echo "── 아카이브 $VERSION ($BUILD) ──"
rm -rf "$ARCHIVE"
mkdir -p "$(dirname "$ARCHIVE")"
custom=$(cfg archive.command)
if [ -n "$custom" ]; then
  bash -c "$custom"
else
  src=()
  ws=$(cfg archive.workspace); pj=$(cfg archive.project)
  if [ -n "$ws" ]; then src=(-workspace "$ws"); else src=(-project "${pj:?설정에 archive.workspace나 archive.project가 필요하다}"); fi
  dest="generic/platform=$([ "$PLATFORM" = osx ] && echo macOS || echo iOS)"
  LOG=build/app-store/archive.log
  if ! xcodebuild "${src[@]}" -scheme "$(cfg archive.scheme)" -configuration Release \
       -destination "$dest" -archivePath "$ARCHIVE" \
       -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"} archive > "$LOG" 2>&1; then
    tail -30 "$LOG" >&2
    echo "아카이브 실패 — 전체 로그: $LOG" >&2
    exit 1
  fi
fi
[ -d "$ARCHIVE" ] || { echo "아카이브가 없다: $ARCHIVE" >&2; exit 1; }

# 빌드 설정이 버전을 덮어쓰면 소스와 다른 번호가 올라간다. 올리기 전에 잡는다.
props="$ARCHIVE/Info.plist"
av=$(/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleShortVersionString" "$props")
ab=$(/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleVersion" "$props")
[ "$av" = "$VERSION" ] && [ "$ab" = "$BUILD" ] \
  || { echo "아카이브 버전 $av ($ab)이 소스 $VERSION ($BUILD)와 다르다" >&2; exit 1; }

echo "── 내보내기 (${DESTINATION:-upload}) ──"
rm -rf "$EXPORT"; mkdir -p "$EXPORT"
OPTIONS="$(mktemp -d)/ExportOptions.plist"
# manageAppVersionAndBuildNumber를 켜 두면 번호가 겹칠 때 조용히 올려서 소스와 어긋난다
cat > "$OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>app-store-connect</string>
	<key>destination</key><string>${DESTINATION:-upload}</string>
	<key>teamID</key><string>$TEAM_ID</string>
	<key>signingStyle</key><string>automatic</string>
	<key>manageAppVersionAndBuildNumber</key><false/>
	<key>uploadSymbols</key><true/>
</dict>
</plist>
PLIST

LOG="$EXPORT.log"
if ! xcodebuild -exportArchive -archivePath "$ARCHIVE" \
     -exportOptionsPlist "$OPTIONS" -exportPath "$EXPORT" \
     -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"} > "$LOG" 2>&1; then
  tail -30 "$LOG" >&2
  echo "내보내기 실패 — 전체 로그: $LOG" >&2
  exit 1
fi
grep -E "Upload succeeded|EXPORT SUCCEEDED" "$LOG"
