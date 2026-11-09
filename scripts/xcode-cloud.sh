#!/bin/bash
#
# GitHub Actions가 막혔을 때(무료 분 소진)의 대체 빌드 — Xcode Cloud를 App Store Connect API로 다룬다.
# 내 Mac에서는 빌드하지 않는다. 아카이브는 Apple 서버가 만들고, 업로드는 저장소의
# ci_scripts/ci_post_xcodebuild.sh가 지금 쓰는 번호 규칙 그대로 한다(Xcode Cloud 자체 배포는 쓰지 않는다 —
# 쓰면 App Store Connect가 Xcode Cloud의 빌드 번호를 쓴다).
#
#   bash scripts/app-store/xcode-cloud.sh setup          대체 워크플로를 만들거나 맞춘다 (처음 한 번, 설정을 바꿨을 때)
#   bash scripts/app-store/xcode-cloud.sh run [브랜치]   그 브랜치 최신 커밋으로 빌드하고 끝날 때까지 지켜본다 (기본 main)
#   bash scripts/app-store/xcode-cloud.sh watch <실행 ID> 이미 시작한 빌드를 다시 지켜본다
#
# 설정: 저장소 루트의 .xcode-cloud.json (XCODE_CLOUD_CONFIG로 바꿀 수 있다)
#   {"app_identifier": "com.x.y", "platform": "IOS|MACOS", "container": "App.xcodeproj",
#    "scheme": "App", "xcode": "Xcode 26.3", "workflow": "Release fallback",
#    "asc_key_path": "~/.appstoreconnect/private_keys/AuthKey_….p8", "asc_key_id": "…", "asc_issuer_id": "…"}
#
# API로 못 하는 것(사람이 한 번): 앱을 Xcode Cloud에 처음 연결(Xcode → Integrate → Create Workflow),
# 워크플로 환경변수(시크릿) 넣기. setup이 무엇이 빠졌는지 알려 준다.
# .p8 내용은 읽지 않는다 — openssl에 경로만 넘겨 서명한다.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
CONFIG="${XCODE_CLOUD_CONFIG:-.xcode-cloud.json}"
[ -f "$CONFIG" ] || { echo "설정 파일이 없다: $CONFIG" >&2; exit 1; }
CMD="${1:-}"; shift || true
case "$CMD" in setup|run|watch) ;; *) sed -n '8,10p' "$0" >&2; exit 2 ;; esac

exec python3 - "$CONFIG" "$CMD" "$@" <<'PY'
import base64, json, os, subprocess, sys, time, urllib.error, urllib.parse, urllib.request, zipfile, io, glob

cfg = json.load(open(sys.argv[1])); cmd = sys.argv[2]; args = sys.argv[3:]
KEY = os.path.expanduser(cfg["asc_key_path"]); KID = cfg["asc_key_id"]; ISS = cfg["asc_issuer_id"]
WF_NAME = cfg.get("workflow") or "Release fallback"
if not os.path.isfile(KEY): sys.exit(f"API 키 파일이 없다: {cfg['asc_key_path']}")

b64 = lambda b: base64.urlsafe_b64encode(b).rstrip(b"=").decode()
def token():
    now = int(time.time())
    msg = f'{b64(json.dumps({"alg":"ES256","kid":KID,"typ":"JWT"}).encode())}.{b64(json.dumps({"iss":ISS,"iat":now,"exp":now+1200,"aud":"appstoreconnect-v1"}).encode())}'
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", KEY], input=msg.encode(), capture_output=True, check=True).stdout
    i = 2 + (1 if der[1] & 0x80 else 0); out = b""
    for _ in range(2):  # DER ECDSA → r||s
        n = der[i + 1]; v = der[i + 2:i + 2 + n].lstrip(b"\0"); out += v.rjust(32, b"\0"); i += 2 + n
    return f"{msg}.{b64(out)}"

def api(method, path, body=None, ok404=False):
    url = path if path.startswith("http") else "https://api.appstoreconnect.apple.com" + path
    req = urllib.request.Request(url, method=method, data=json.dumps(body).encode() if body else None,
                                 headers={"Authorization": f"Bearer {token()}", "Content-Type": "application/json"})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                raw = r.read(); return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            if e.code == 404 and ok404: return None
            if e.code >= 500 and attempt < 2: time.sleep(5); continue
            sys.exit(f"App Store Connect {method} {path}: {e.code} {e.read().decode()[:600]}")
        except urllib.error.URLError:
            if attempt < 2: time.sleep(5); continue
            raise

def all_pages(path):
    out = []
    while path:
        d = api("GET", path); out += d.get("data", []); path = d.get("links", {}).get("next")
    return out

def product():
    apps = api("GET", "/v1/apps?" + urllib.parse.urlencode({"filter[bundleId]": cfg["app_identifier"]}))["data"]
    app = next((a for a in apps if a["attributes"]["bundleId"] == cfg["app_identifier"]), None)
    if not app: sys.exit(f"App Store Connect에 {cfg['app_identifier']} 앱이 없다")
    p = api("GET", f"/v1/apps/{app['id']}/ciProduct", ok404=True)
    if not p or not p.get("data"):
        sys.exit("이 앱은 아직 Xcode Cloud에 연결되지 않았다(사람이 한 번 해야 한다):\n"
                 f"  Xcode에서 {cfg['container']}를 열고 → 메뉴 Integrate → Create Workflow → 앱 선택 →\n"
                 "  GitHub 저장소 접근 허용까지 한 뒤, 기본 워크플로는 저장만 하고 빌드는 시작하지 않는다.\n"
                 "  그다음 이 명령(setup)을 다시 돌리면 기본 워크플로를 끄고 대체 워크플로를 만든다.")
    return p["data"]["id"]

def repository(pid):
    repos = api("GET", f"/v1/ciProducts/{pid}/primaryRepositories")["data"]
    if not repos: sys.exit("Xcode Cloud 제품에 연결된 저장소가 없다")
    return repos[0]

def workflows(pid):
    return all_pages(f"/v1/ciProducts/{pid}/workflows?limit=50")

AUTO = ("branchStartCondition", "tagStartCondition", "pullRequestStartCondition", "scheduledStartCondition")

def setup():
    pid = product(); repo = repository(pid)
    xv = next((x for x in api("GET", "/v1/ciXcodeVersions?limit=50")["data"] if x["attributes"]["name"] == cfg.get("xcode", "Latest Release")), None)
    if not xv: sys.exit(f"Xcode Cloud에 '{cfg.get('xcode')}'가 없다 — ciXcodeVersions 이름 중 하나를 쓴다")
    macs = api("GET", f"/v1/ciXcodeVersions/{xv['id']}/macOsVersions?limit=50")["data"]
    mac = next((m for m in macs if m["attributes"]["name"] == "Latest Release"), None) or macs[0]
    attrs = {
        "name": WF_NAME,
        "description": "GitHub Actions 무료 분이 막혔을 때 배포 스킬이 API로 시작하는 대체 빌드. 자동 시작 없음. "
                       "아카이브만 하고 업로드는 ci_scripts/ci_post_xcodebuild.sh가 한다.",
        "isEnabled": True, "clean": True, "containerFilePath": cfg["container"],
        "manualBranchStartCondition": {"source": {"isAllMatch": True, "patterns": []}},
        "branchStartCondition": None, "tagStartCondition": None, "pullRequestStartCondition": None, "scheduledStartCondition": None,
        "actions": [{"name": f"Archive - {cfg['platform'].title()}", "actionType": "ARCHIVE", "platform": cfg["platform"],
                     "scheme": cfg["scheme"], "isRequiredToPass": True}],
    }
    rel = {"xcodeVersion": {"data": {"type": "ciXcodeVersions", "id": xv["id"]}},
           "macOsVersion": {"data": {"type": "ciMacOsVersions", "id": mac["id"]}}}
    wfs = workflows(pid)
    mine = next((w for w in wfs if w["attributes"]["name"] == WF_NAME), None)
    if mine:
        api("PATCH", f"/v1/ciWorkflows/{mine['id']}", {"data": {"type": "ciWorkflows", "id": mine["id"], "attributes": attrs, "relationships": rel}})
        wid = mine["id"]; print(f"워크플로 '{WF_NAME}' 맞춤 ({wid})")
    else:
        rel |= {"product": {"data": {"type": "ciProducts", "id": pid}}, "repository": {"data": {"type": "scmRepositories", "id": repo["id"]}}}
        wid = api("POST", "/v1/ciWorkflows", {"data": {"type": "ciWorkflows", "attributes": attrs, "relationships": rel}})["data"]["id"]
        print(f"워크플로 '{WF_NAME}' 만듦 ({wid})")
    # 자동으로 시작하는 다른 워크플로(온보딩 기본값은 브랜치 변경마다 돈다)는 끈다 — 25시간을 갉아먹는다.
    for w in wfs:
        a = w["attributes"]
        if w["id"] != wid and a.get("isEnabled") and any(a.get(k) for k in AUTO):
            api("PATCH", f"/v1/ciWorkflows/{w['id']}", {"data": {"type": "ciWorkflows", "id": w["id"], "attributes": {"isEnabled": False}}})
            print(f"자동 시작 워크플로 '{a['name']}'를 껐다 ({w['id']})")
    print(f"Xcode {xv['attributes']['version']} · macOS {mac['attributes']['name']} · {cfg['container']} · scheme {cfg['scheme']}")
    print("환경변수(시크릿)는 API로 넣을 수 없다. App Store Connect → 앱 → Xcode Cloud → Manage Workflows →\n"
          f"  '{WF_NAME}' → Environment에서 저장소의 ci_scripts가 요구하는 값을 Secret으로 넣는다.")

def git_ref(repo_id, branch):
    for r in all_pages(f"/v1/scmRepositories/{repo_id}/gitReferences?limit=200"):
        a = r["attributes"]
        if a.get("kind") == "BRANCH" and a.get("name") == branch and not a.get("isDeleted"):
            return r["id"]
    sys.exit(f"Xcode Cloud가 브랜치 {branch}를 모른다 — 푸시했는지 본다")

def run():
    branch = args[0] if args else "main"
    pid = product(); repo = repository(pid)
    wf = next((w for w in workflows(pid) if w["attributes"]["name"] == WF_NAME), None) or sys.exit(f"워크플로 '{WF_NAME}'가 없다 — 먼저 setup")
    sha = subprocess.run(["git", "rev-parse", f"origin/{branch}"], capture_output=True, text=True).stdout.strip()
    d = api("POST", "/v1/ciBuildRuns", {"data": {"type": "ciBuildRuns", "relationships": {
        "workflow": {"data": {"type": "ciWorkflows", "id": wf["id"]}},
        "sourceBranchOrTag": {"data": {"type": "scmGitReferences", "id": git_ref(repo["id"], branch)}}}}})["data"]
    print(f"Xcode Cloud 빌드 #{d['attributes'].get('number')} 시작 ({d['id']}) — {branch} {sha[:7] if sha else ''}")
    watch(d["id"], sha)

def watch(rid, expect_sha=""):
    last = None; start = time.time()
    while True:
        a = api("GET", f"/v1/ciBuildRuns/{rid}")["data"]["attributes"]
        state = (a.get("executionProgress"), a.get("completionStatus"))
        if state != last:
            print(f"  {time.strftime('%H:%M:%S')} {state[0]} {state[1] or ''}", flush=True); last = state
        got = ((a.get("sourceCommit") or {}).get("commitSha") or "")
        if expect_sha and got and not got.startswith(expect_sha[:7]):
            print(f"  주의: 빌드 커밋 {got[:7]} ≠ 로컬 origin 커밋 {expect_sha[:7]} — git fetch가 늦었거나 그 사이 푸시가 있었다")
            expect_sha = ""
        if a.get("executionProgress") == "COMPLETE": break
        if time.time() - start > 3 * 3600: sys.exit("3시간이 지나도 안 끝났다 — App Store Connect에서 확인한다")
        time.sleep(30)
    print(f"결과 {a.get('completionStatus')} · 커밋 {got[:7]} · {(a.get('startedDate') or '')[:16]} → {(a.get('finishedDate') or '')[:16]}")
    for act in api("GET", f"/v1/ciBuildRuns/{rid}/actions")["data"]:
        aa = act["attributes"]; print(f"  액션 {aa.get('name')}: {aa.get('completionStatus')}")
        ic = aa.get("issueCounts") or {}
        if aa.get("completionStatus") != "SUCCEEDED" or ic.get("errors"):
            for iss in all_pages(f"/v1/ciBuildActions/{act['id']}/issues?limit=50")[:15]:
                ia = iss["attributes"]; loc = (ia.get("fileSource") or {}).get("path", "")
                print(f"    {ia.get('issueType')}: {ia.get('message','')[:300]} {loc}")
            dump_logs(act["id"])
    sys.exit(0 if a.get("completionStatus") == "SUCCEEDED" else 1)

def dump_logs(action_id):
    # 로그 묶음을 받아 ci_scripts 출력의 끝부분을 보여 준다(업로드 실패는 여기에만 남는다).
    out = os.path.join("build", "xcode-cloud", action_id); os.makedirs(out, exist_ok=True)
    for art in api("GET", f"/v1/ciBuildActions/{action_id}/artifacts")["data"]:
        aa = art["attributes"]
        if aa.get("fileType") != "LOG_BUNDLE" or not aa.get("downloadUrl"): continue
        zipfile.ZipFile(io.BytesIO(urllib.request.urlopen(aa["downloadUrl"], timeout=120).read())).extractall(out)
    logs = [p for p in glob.glob(f"{out}/**/*", recursive=True) if os.path.isfile(p) and "ci_" in os.path.basename(p)]
    for p in logs:
        print(f"  ── {os.path.relpath(p, out)} (끝 40줄)")
        print("".join(open(p, errors="replace").readlines()[-40:]))
    print(f"  전체 로그: {out}")

{"setup": setup, "run": run, "watch": lambda: watch(args[0] if args else sys.exit("실행 ID가 필요하다"))}[cmd]()
PY
