#!/bin/bash
#
# Xcode Cloud — 아카이브 직후. GitHub Actions가 막혔을 때의 대체 빌드(워크플로 "Release fallback") 업로드.
# Xcode Cloud 자체 배포는 끈다 — 켜면 App Store Connect가 Xcode Cloud 빌드 번호를 써서 소스 번호와 어긋난다.
# 그래서 여기서 API 키로 직접 내보내 올린다. 아카이브 번호가 소스(version.sh get)와 다르면 올리지 않는다.
#
# 워크플로 환경변수(Secret): ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8(.p8을 base64로 — GitHub 시크릿과 같은 값)
# main이 아닌 브랜치는 올리지 않고 서명된 결과물까지만 만든다(시험용).
set -euo pipefail
[ "${CI_WORKFLOW:-}" = "Release fallback" ] && [ "${CI_XCODEBUILD_ACTION:-}" = archive ] || exit 0
[ "${CI_XCODEBUILD_EXIT_CODE:-1}" = 0 ] || { echo "아카이브 실패 — 올리지 않는다"; exit 0; }
cd "$CI_PRIMARY_REPOSITORY_PATH"
. scripts/app-store/lib.sh

: "${ASC_KEY_ID:?워크플로 환경변수 ASC_KEY_ID가 없다}" "${ASC_ISSUER_ID:?ASC_ISSUER_ID가 없다}" "${ASC_KEY_P8:?ASC_KEY_P8이 없다}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
printf '%s' "$ASC_KEY_P8" | base64 --decode > "$TMP/AuthKey.p8"; chmod 600 "$TMP/AuthKey.p8"

read -r VERSION BUILD < <(bash scripts/app-store/version.sh get)
av=$(/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleShortVersionString" "$CI_ARCHIVE_PATH/Info.plist")
ab=$(/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleVersion" "$CI_ARCHIVE_PATH/Info.plist")
[ "$av" = "$VERSION" ] && [ "$ab" = "$BUILD" ] || { echo "아카이브 $av ($ab) ≠ 소스 $VERSION ($BUILD) — 올리지 않는다" >&2; exit 1; }

MAIN=$(cfg branch); if [ "${CI_BRANCH:-}" = "${MAIN:-main}" ]; then DEST=upload; else DEST="export"; fi
cat > "$TMP/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
	<key>method</key><string>app-store-connect</string>
	<key>destination</key><string>$DEST</string>
	<key>teamID</key><string>$(cfg team_id)</string>
	<key>signingStyle</key><string>automatic</string>
	<key>manageAppVersionAndBuildNumber</key><false/>
	<key>uploadSymbols</key><true/>
</dict></plist>
PLIST
echo "── 내보내기 $VERSION ($BUILD) → $DEST (브랜치 ${CI_BRANCH:-?}) ──"
if ! xcodebuild -exportArchive -archivePath "$CI_ARCHIVE_PATH" -exportOptionsPlist "$TMP/ExportOptions.plist" \
     -exportPath "$TMP/export" -allowProvisioningUpdates -authenticationKeyPath "$TMP/AuthKey.p8" \
     -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID" > "$TMP/export.log" 2>&1; then
  tail -60 "$TMP/export.log"; exit 1
fi
grep -E "Upload succeeded|EXPORT SUCCEEDED" "$TMP/export.log"
