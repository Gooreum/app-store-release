# app-store-release

iOS·macOS 앱을 App Store Connect에 올리는 [Claude Code](https://claude.com/claude-code) 스킬.
A Claude Code skill that sets up and runs App Store releases for any iOS/macOS project.

- **처음 한 번 — 설정:** 프로젝트를 살펴 fastlane(앱 정보·스크린샷)과 GitHub Actions(빌드 업로드) 파이프라인을 깐다.
- **머지할 때마다 — 릴리스:** 배포 여부·버전·업데이트 내용·앱 정보·스크린샷을 **탭 하나로 한 번에** 묻는다.
  답을 반영한 릴리스 커밋을 푸시하면 Actions가 올린다.
- **심사 제출은 하지 않는다.** App Store Connect에서 사람이 누른다.

## 설치

```bash
git clone https://github.com/Gooreum/app-store-release ~/.claude/skills/app-store-release
```

Claude Code에서 `/app-store-release`를 실행하거나 "앱스토어 배포 설정해 줘"라고 하면 된다.

## 무엇이 프로젝트에 깔리나

| 경로 | 하는 일 |
|---|---|
| `.app-store-release.json` | 플랫폼·번들 ID·팀·버전 위치·아카이브 방법·스크린샷 명령 ([예시](templates/app-store-release.example.json)) |
| `scripts/app-store/version.sh` | 버전·빌드 번호 읽기/쓰기 (Info.plist 또는 `MARKETING_VERSION`) |
| `scripts/app-store/release-diff.sh` | 두 커밋 사이에 빌드·앱 정보·스크린샷 중 무엇이 바뀌었는지 |
| `scripts/app-store/archive-upload.sh` | 아카이브 → App Store Connect 업로드 (API 키로 클라우드 서명) |
| `fastlane/Fastfile` | `metadata`(앱 정보·스크린샷 반영), `pull_metadata`(현재 값 내려받기) |
| `fastlane/metadata`, `fastlane/screenshots` | 앱 정보와 스크린샷 원본 — 저장소에서 관리 |
| `.github/workflows/app-store.yml` | 릴리스 커밋이 오면 바뀐 것만 올리고 태그 `v<버전>-<빌드>` |

## 필요한 것

- GitHub 저장소 + `gh` CLI 로그인
- App Store Connect API 키(**Admin** — CI에서 배포 인증서·프로파일을 받는다)
- 시크릿 `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`(.p8을 base64로) — 스킬이 명령을 알려 주고 사용자가 직접 넣는다
- macOS 러너 (공개 저장소는 무료)

## 흐름

```
PR 머지 → /app-store-release
  → [배포·버전 | 업데이트 내용 | 앱 정보 | 스크린샷] 한 번에 선택
  → 릴리스 커밋 푸시
  → GitHub Actions
       ├ 빌드 번호 바뀜          → 아카이브·업로드·태그
       ├ fastlane/metadata 바뀜    → 앱 정보 반영
       └ fastlane/screenshots 바뀜 → 스크린샷 교체
  → App Store Connect에서 심사 제출 (사람)
```

## 라이선스

MIT
