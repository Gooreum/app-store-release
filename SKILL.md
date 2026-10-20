---
name: app-store-release
description: iOS·macOS 앱을 App Store Connect에 배포한다. 메인 브랜치에 PR을 머지한 직후, 또는 사용자가 "배포", "릴리스", "스토어에 올려", "앱스토어 자동 배포 설정"이라고 할 때 쓴다. 처음이면 프로젝트에 fastlane·GitHub Actions 배포 파이프라인을 깔고, 그 뒤로는 배포 여부·버전·업데이트 내용·앱 정보·스크린샷을 탭 하나로 한 번에 물어 릴리스 커밋을 만든다. 업로드는 GitHub Actions가 하고 심사 제출은 사람이 한다.
---

# app-store-release

사용자에게 보이는 말은 사용자의 언어로 쓴다.

두 가지 모드가 있다. 저장소 루트에 `.app-store-release.json`이 없으면 **설정**, 있으면 **릴리스**.

`SKILL_DIR`은 이 파일이 있는 폴더다(보통 `~/.claude/skills/app-store-release`).

## 질문 규칙 (두 모드 공통)

- 질문은 **한 번에** 띄운다 — AskUserQuestion 한 호출에 탭 여러 개(최대 4개). 사용자가 좌우 키로
  탭을 넘기며 고른다. 탭을 한 개씩 따로 묻지 않는다.
- 탭 하나의 보기는 최대 4개다. "없음"·"배포 안 함"처럼 고를 만한 답은 Other에 쓰게 하지 말고
  **반드시 보기로** 둔다. Other는 직접 입력(버전 숫자, 고칠 내용)에만 쓴다.
- 질문에 넣을 초안(업데이트 내용 등)은 **묻기 전에 미리 써서** `preview`에 넣는다.
- 후속 질문이 필요하면 해당하는 것만 모아 다시 한 번에 묻는다.

## 보안 규칙

- App Store Connect API 키(.p8) **내용을 읽거나 복사하거나 출력하지 않는다.** 경로만 다룬다.
- GitHub 시크릿은 사용자가 직접 넣는다. 명령을 보여 주고 `! 명령`으로 실행하라고 안내한다.
- 공개 저장소에 심사 담당자 연락처(`fastlane/metadata/review_information/`)를 커밋하지 않는다 —
  `.gitignore`에 넣는다.

---

## 설정 모드 — 파이프라인 깔기

### 1. 프로젝트 살피기 (읽기만)

```bash
git rev-parse --show-toplevel; git remote get-url origin; gh repo view --json visibility,defaultBranchRef
ls *.xcworkspace *.xcodeproj Project.swift project.yml 2>/dev/null
xcodebuild -list -json 2>/dev/null | head -40
grep -rl "CFBundleShortVersionString" --include=Info.plist . | grep -v -e /build/ -e /Pods/ | head
grep -h "MARKETING_VERSION\|PRODUCT_BUNDLE_IDENTIFIER\|DEVELOPMENT_TEAM" */project.pbxproj 2>/dev/null | sort -u | head
```

추려 낼 값:
- `platform`: `ios` 또는 `osx`
- `app_identifier`, `team_id`
- `version.kind`/`version.file`: Info.plist에 숫자가 직접 있으면 `plist` + 그 파일,
  `$(MARKETING_VERSION)`이면 `build-setting` + 값이 적힌 `project.pbxproj`(또는 `.xcconfig`)
- `archive`: `workspace` 또는 `project`, `scheme`. Tuist·XcodeGen처럼 프로젝트를 생성하거나 자체
  아카이브 스크립트가 있으면 `archive.command`에 그 명령을 쓰고 `archive.path`에 결과 경로를 둔다.
- `ci.setup`: CI에서 아카이브 전에 깔 것(예: `brew install tuist && tuist install`). 없으면 빈 값.
- `runner`: 로컬 Xcode 메이저 버전에 맞는 GitHub macOS 러너(`macos-15`, `macos-26` …).

### 2. 한 번에 확인받기 — AskUserQuestion 1회

추린 값으로 탭을 만든다(예):

| header | 질문 | 보기 |
|---|---|---|
| 앱 | 이 앱이 맞나요? (`com.x.y`, iOS, 팀 `ABCDE12345`) | `맞다` / 다른 후보들 |
| 버전 위치 | 버전을 어디서 읽고 쓸까요? | 찾은 후보 파일들 |
| 아카이브 | 아카이브는 어떻게 만들까요? | `xcodebuild (scheme X)` / 찾은 스크립트 / … |
| 스크린샷 | 스크린샷은 어떻게 만들까요? | `직접 넣는다(업로드만)` / `캡처·합성 명령을 설정` / `스크린샷 안 씀` |

### 3. 파일 깔기

```bash
mkdir -p scripts/app-store fastlane .github/workflows
cp "$SKILL_DIR"/scripts/{lib,version,release-diff,archive-upload}.sh scripts/app-store/
cp "$SKILL_DIR"/templates/fastlane/Fastfile fastlane/Fastfile
sed -e "s|__BRANCH__|$BRANCH|g" -e "s|__VERSION_FILE__|$VERSION_FILE|g" -e "s|__RUNNER__|$RUNNER|g" \
  "$SKILL_DIR"/templates/workflows/app-store.yml > .github/workflows/app-store.yml
```

`.app-store-release.json`은 `templates/app-store-release.example.json` 모양대로 쓴다.
이미 같은 이름의 파일이 있으면 덮어쓰지 말고 차이를 보여 준 뒤 묻는다.

`.gitignore`에 추가: `fastlane/metadata/review_information/`, `fastlane/report.xml`, `build/app-store/`.

확인: `bash scripts/app-store/version.sh get` → 지금 버전이 나와야 한다.

### 4. 시크릿 — 사용자가 직접

App Store Connect → 사용자 및 액세스 → 통합 → App Store Connect API에서 **Admin** 키를 만들고
`.p8`을 받는다(이미 있으면 `~/.appstoreconnect/private_keys/`를 본다 — 파일 이름만, 내용은 열지 않는다).
Issuer ID는 같은 화면 위쪽에 있다. 사용자에게 아래를 `!`로 실행하라고 안내한다:

```
! gh secret set ASC_KEY_ID --body <키 ID>
! gh secret set ASC_ISSUER_ID --body <Issuer ID>
! base64 -i ~/.appstoreconnect/private_keys/AuthKey_<키 ID>.p8 | gh secret set ASC_KEY_P8
```

`gh secret list`로 셋이 들어갔는지 본다.

### 5. 현재 앱 정보 내려받기

App Store Connect 값을 그대로 가져와 시작점으로 삼는다(지어내지 않는다):

```bash
ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_….p8 fastlane pull_metadata
```

fastlane이 없으면 `brew install fastlane`. 키 ID·Issuer ID는 사용자에게 받은 값을 쓴다.

### 6. 커밋·확인

파일을 하나씩 `git add`하고 커밋·푸시한다(프로젝트의 커밋 규칙을 따른다).
그다음 서명까지 되는지 본다:

```bash
gh workflow run app-store.yml -f build=true -f dry_run=true
sleep 5; gh run watch "$(gh run list --workflow app-store.yml --limit 1 --json databaseId -q '.[0].databaseId')" --exit-status
```

실패하면 `gh run view <id> --log-failed | tail -60`을 읽고 고친다. 흔한 원인:
키 권한이 Admin이 아님, 러너의 Xcode가 프로젝트보다 낮음, `ci.setup` 누락.

---

## 릴리스 모드

### 0. 준비 — 묻기 전에 읽기만 한다

이 단계에서는 파일을 하나도 바꾸지 않는다. 하나라도 어긋나면 묻지 말고 멈춰 무엇이 문제인지 말한다.

```bash
. scripts/app-store/lib.sh; BRANCH=$(cfg branch); BRANCH=${BRANCH:-main}
git switch "$BRANCH" && git pull --ff-only
git status --short -- "$(cfg version.file)" fastlane scripts/app-store .github   # 비어 있어야 한다
gh secret list   # ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8
bash scripts/app-store/version.sh get            # → "X.Y.Z B"
BASE=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null \
       || git log -1 --format=%H -G "CFBundleShortVersionString|MARKETING_VERSION" -- "$(cfg version.file)")
git log --no-merges --format='%h %s' "$BASE"..HEAD
```

**업데이트 내용 초안을 여기서 미리 쓴다.** 사용자에게 보이는 변화만 고른다 — 리팩터·테스트·문서·CI·
버전 커밋은 뺀다. `fastlane/metadata/<언어>/release_notes.txt`의 이전 문체를 따라 **있는 언어 전부**
쓴다. 파일에는 아직 쓰지 않는다. 앱에 보이는 변화가 없으면 지금 문구를 그대로 초안으로 둔다.

**이름이 바뀌었는지도 본다.** 이번 변경에서 화면의 메뉴·기능 이름을 바꿨거나 새 기능이 생겼다면,
`fastlane/metadata/<언어>/description.txt`·`keywords.txt`·`subtitle.txt`에 옛 이름이 남았는지, 새 기능이
빠졌는지 `grep`으로 확인한다. 남아 있으면 앱 정보 탭의 설명에 "설명에 옛 이름 'X'가 남아 있어요"라고 적는다.
스크린샷과 설명의 이름이 앱과 다르면 심사에서 "설명과 앱이 다르다"는 지적을 받는다.

### 1. 한 번에 묻기 — AskUserQuestion 1회, 탭 4개

| header | 질문 | 보기 (최대 4개) |
|---|---|---|
| 배포·버전 | 이번 머지를 App Store에 배포할까요? 한다면 버전은? (지금 X.Y.Z (B)) | `패치 X.Y.(Z+1)` / `마이너 X.(Y+1).0` / `X.Y.Z 그대로 (빌드 안 올림)` / `이번엔 배포 안 함` |
| 업데이트 | 업데이트 내용을 이대로 쓸까요? | `확정` / `고쳐 줘` — 두 보기 모두 `preview`에 언어별 초안 전문 |
| 앱 정보 | 바꿀 앱 정보가 있나요? (multiSelect) | `없음` / `이름·부제·키워드` / `설명·프로모션 문구` / `URL·저작권·카테고리` |
| 스크린샷 | 스크린샷을 바꿀까요? | `그대로 둔다` / `전부 다시` / `특정 화면만 다시` |

- 첫 탭이 배포 여부다. 다른 탭보다 앞에 둔다.
- `(Recommended)`: 앱 커밋이 있으면 `패치`, 없으면 `그대로`. 스크린샷은 `그대로 둔다`.
- 메이저·직접 입력(예: 같은 버전에 빌드만 올리기)은 Other로 받는다.
- 설정에 `screenshots.capture`가 없으면 스크린샷 보기는 `그대로 둔다` / `새 이미지를 fastlane/screenshots에 넣었다`로 바꾼다.

### 2. 답 처리

- `이번엔 배포 안 함` → 다른 탭 답은 버리고 아무 파일도 바꾸지 않고 한 줄로 끝낸다.
- 앱 정보에서 `없음`과 다른 항목을 같이 골랐으면 `없음`은 무시한다.
- 직접 입력 버전: 정수 1~3개를 점으로 이은 형식이 아니거나 현재보다 낮으면 그 질문만 다시 묻는다.

후속 질문 — 아래 중 해당하는 것만 탭으로 묶어 **한 번에** 묻는다. 없으면 생략한다.
- 업데이트 `고쳐 줘` → "무엇을 고칠까요?" (Other)
- 앱 정보 항목마다 → "무엇으로 바꿀까요?" (Other)
- `특정 화면만` → `screenshots.scenes`를 multiSelect로, 4개씩 나눠 탭 여러 개

고친 초안이 있으면 탭마다 `preview`로 띄워 `확정` / `고쳐 줘`를 한 번에 묻는다.
**업데이트 내용이 `확정`되기 전에는 파일을 바꾸거나 커밋하지 않는다.**

### 3. 파일 반영

**버전** — 새 빌드를 올리면 빌드 번호는 늘 현재 값 + 1이다. 묻지 않는다. 버전을 올려도 1로 되돌리지
않는다(App Store Connect는 이전보다 큰 번호만 받는다). `그대로`면 버전 파일을 건드리지 않는다.

```bash
bash scripts/app-store/version.sh set <새 버전> <새 빌드>
```

**업데이트 내용·앱 정보** — 확정된 초안을 `fastlane/metadata/<언어>/`의 파일에 **언어마다** 쓴다.

| 보기 | 파일 | 제한 |
|---|---|---:|
| 이름·부제·키워드 | `name.txt` / `subtitle.txt` / `keywords.txt` | 30 / 30 / 100자(쉼표 구분, 이름에 있는 낱말 제외) |
| 설명·프로모션 문구 | `description.txt` / `promotional_text.txt` | 4000 / 170자 |
| URL·저작권·카테고리 | `support_url.txt`, `marketing_url.txt`, `privacy_url.txt`, `copyright.txt`, `primary_category.txt` | |
| (업데이트) | `release_notes.txt` | 4000자 |

제한을 넘으면 초안을 내기 전에 줄인다.

**스크린샷** — 설정의 `screenshots`를 쓴다. `{scenes}`는 고른 장면 id를 공백으로 이은 것이다.

1. 캡처: `screenshots.capture` 명령. 앱 창이 잠깐씩 앞으로 뜬다고 먼저 말한다.
   Stage Manager 때문에 `could not create image from window`나 썸네일 크기(수백 px)로 실패할 수 있다.
   실패하면 캡처 폴더를 지우고 **최대 3번까지** 다시 돌린다. 그래도 안 되면 사용자에게 보고한다.
   영어 캡처에 한국어(원문 언어)가 남아 있으면 데모 데이터의 문구가 실제 앱 문구와 다른 것이다 —
   데모가 `String(localized:)`로 실제 화면과 **같은 키**를 쓰는지 고친 뒤 다시 찍는다.
2. 합성: `screenshots.compose` 명령. `composer`가 `codex`이고 `codex` CLI가 있으면 Codex에 맡긴다
   (`codex exec -s workspace-write`). 프롬프트에는 장면 목록, compose 명령, "아트디렉션·카피를 바꾸지
   말 것", "결과를 한 장씩 열어 글자 깨짐·잘림·크기·언어 섞임을 검수할 것", "소스·메타데이터는
   건드리지 말 것"을 담는다. 아니면 직접 돌린다.
3. 결과는 `fastlane/screenshots/<언어>/`에 있어야 한다. `git diff --stat fastlane/screenshots`로 고른
   장면만 바뀌었는지 보고, 결과 이미지를 직접 열어 확인한 뒤 사용자에게 보여 주고 `확정` / `다시`를 묻는다.

### 4. 릴리스 커밋 → 워크플로 확인

바뀐 파일만 하나씩 `git add`한다(`git add .` 금지). 프로젝트의 커밋 규칙을 따른다. 예:
`chore: X.Y.Z (B) 릴리스 — 업데이트 내용·스크린샷 반영`. 그리고 푸시한다.

```bash
sleep 5; RUN=$(gh run list --workflow app-store.yml --limit 1 --json databaseId -q '.[0].databaseId')
gh run watch "$RUN" --exit-status
```

- 성공: 무엇이 올라갔는지(빌드/앱 정보/스크린샷), 태그, 그리고 **심사 제출은 사람이 App Store Connect에서
  한다**고 보고한다. 빌드는 업로드 뒤 처리에 몇 분~수십 분 걸린다.
- 실패: `gh run view "$RUN" --log-failed | tail -60`을 읽고 원인을 요약한다. 고칠 수 있으면 고치고,
  같은 빌드 번호로 다시 올리지 않는지 확인한 뒤 `gh workflow run app-store.yml -f build=true`처럼 수동 실행한다.
- 빌드 없이 앱 정보만 바꾼 커밋이면 태그는 생기지 않는다. `workflow_dispatch`로 `build=false`로 다시 돌린 뒤에도
  마찬가지라, 빌드가 이미 올라가 있으면 태그를 직접 찍어 올린다: `git tag v<버전>-<빌드> <릴리스 커밋> && git push origin v<버전>-<빌드>`.
  태그가 없으면 다음 릴리스의 `BASE`(마지막 릴리스 기준점)가 어긋난다.
- **스크린샷 교체가 `Failed to delete screenshot ... APP_DESKTOP` / `Failed verification of all screenshots
  deleted`로 실패하면**: 이미 올라가 있는 스크린샷을 API로 지우지 못하는 것이다(빌드 업로드는 이미 끝났다).
  같은 명령을 다시 돌리지 말고 사용자에게 **App Store Connect 웹에서 해당 버전의 기존 스크린샷을 지워 달라**고
  부탁한다. 지운 뒤 `gh workflow run app-store.yml -f metadata=true -f screenshots=true`로 앱 정보·스크린샷만
  다시 올린다(빌드는 다시 올리지 않는다).

## 참고

- 서명만 확인: `gh workflow run app-store.yml -f build=true -f dry_run=true`
- 앱 정보를 App Store Connect 값으로 다시 맞추기: 설정 5단계의 `fastlane pull_metadata`
- 스크립트를 고치면 이 저장소의 `scripts/`를 고치고, 각 프로젝트의 `scripts/app-store/`로 다시 복사한다.
