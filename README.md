# Quota — macOS 메뉴바 Claude 사용량 표시 앱

맥 메뉴바에 Claude 사용량을 Claude 마크 + `5h NN% · 7d NN%`로 상시 표시하고, 클릭하면
5시간 한도·7일 한도·요금 상태를 보여주는 팝오버가 열리는 메뉴바 앱입니다. 

<img width="136" height="50" alt="image" src="https://github.com/user-attachments/assets/d01dd02e-0eff-4366-93ae-cb75ac4850f1" />
<img width="626" height="984" alt="image" src="https://github.com/user-attachments/assets/e988ab74-489b-4530-9bf4-4559608c125f" />



## 메뉴바 표시
**Claude 마크(테라코타 스타버스트)** + `5h NN% (14:40) · 7d NN% (일 21:59)` —
5시간 창 사용률과 주간 전체 모델 사용률, 그리고 각 할당량의 **초기화 시각**(연한
글자)을 동시에 표시합니다. 색상 코딩 켜짐 시 각 퍼센트 숫자가 사용량 3단계(초록 <50 ·
주황 <80 · 빨강 ≥80)로 개별 색칠되고, 둘 중 하나라도 90% 이상이면 마크가 맥동합니다.

## 설치 — 각자 빌드해서 쓰기 (Apple 계정 불필요)
직접 빌드한 앱은 Gatekeeper에 막히지 않습니다. 필요한 건 **macOS 14+ 와 Xcode
(또는 Command Line Tools)** 뿐.
```bash
git clone <이 저장소 URL> && cd ClaudeGauge
./scripts/make_app.sh          # release 빌드 → Quota.app 생성(로컬 ad-hoc 서명)
open Quota.app                 # 메뉴바에 아이콘 등장
```
처음 실행하면:
- **Claude Code 사용자**: "키체인 접근 허용" 프롬프트 → *항상 허용* → 바로 실제 사용량 표시.
- 그 외: 팝오버의 **로그인** → 브라우저에서 Claude 로그인·승인 → 자동 복귀.

> `swift run`으로 맨 바이너리를 직접 실행하면 UserNotifications가 앱 번들을 요구해
> 크래시합니다. 항상 `.app` 번들(`make_app.sh`)로 실행하세요.

### 개발용
```bash
./scripts/make_app.sh debug && open Quota.app          # 디버그 빌드
swift build && QUOTA_SNAPSHOT=/tmp/quota_snaps ./.build/debug/Quota   # 아이콘/팝오버 PNG 렌더
```

## 구조
```
Sources/Quota/
  QuotaApp.swift            @main (Settings 씬은 비어 있음 — UI는 상태바+팝오버)
  App/AppDelegate.swift     NSStatusItem + NSPopover + 설정창 관리
  App/SnapshotRenderer.swift 오프스크린 PNG QA 렌더러(QUOTA_SNAPSHOT)
  Views/ClaudeMarkView.swift Claude 스타버스트 마크 Canvas 렌더러
  Views/MenuBarIconView.swift 상태바 마크+5h/7d % (다크/라이트 적응, 맥동)
  Views/PopoverView.swift   라이트 팝오버 308px
  Views/SettingsView.swift  색상·폴링·알림·계정
  Models/…                  Preferences, UsageState, UsageModel(폴링/알림)
  Services/…                Config, Credentials(Keychain), UsageAPIClient, AuthService(PKCE), TimeText
```

## 데이터 소스 & 인증
- **인증 우선순위**: 자체 OAuth 로그인 토큰(Keychain) → 없으면 Claude Code CLI 토큰
  (Keychain `Claude Code-credentials` 또는 `~/.claude/.credentials.json`) 자동 감지.
  - Claude Code 사용자는 **로그인 없이** 앱이 기존 토큰을 재사용합니다. 다른 앱이 그 항목을
    읽으므로 **첫 실행 시 "키체인 접근 허용" 프롬프트**가 뜹니다 → "항상 허용".
  - Claude Code가 없으면 **OAuth 로그인**: 브라우저가 열리고 로그인·승인 후 표시되는 인증
    코드를 앱에 붙여넣습니다(콘솔 콜백 방식).
- **엔드포인트**: `GET https://api.anthropic.com/api/oauth/usage`.
  - 헤더: `Authorization: Bearer …`, `anthropic-beta: oauth-2025-04-20`,
    **`User-Agent: claude-code/<version>` (필수 — 없으면 429 도배)**.
  - 응답: `five_hour.utilization`, `seven_day.utilization`, `seven_day_<model>.utilization`
    (각각 0–100 %) + `resets_at`(ISO8601).
- **폴링**: 기본 300초, 최소 180초. 429 시 지수 백오프.
- **토큰은 각자 Keychain에만 저장**, 외부 서버로 절대 전송하지 않습니다.

## ⚠️ 배포 전 반드시 알아둘 것 (비공식 도구)
- Claude **구독(Pro/Max) 한도에는 공식 API가 없습니다.** 위 엔드포인트는 **비공개**이며
  예고 없이 변경·차단될 수 있습니다.
- 자체 OAuth는 Claude Code의 client_id/User-Agent를 사용 → **공식 클라이언트 사칭 성격의
  ToS 회색지대**입니다. 공개 배포·사용은 본인 책임입니다.
- 엔드포인트/스키마/헤더와 OAuth 파라미터는 커뮤니티 리버스엔지니어링으로 확인된 실제 값을
  사용합니다. 로그인·토큰이 없으면 UI는 샘플 데이터로 렌더됩니다.

## 배포 (지인에게 서명된 dmg 공유)
`scripts/make_app.sh`는 로컬 개발용 ad-hoc 서명까지만 하므로, 남에게 주면 Gatekeeper가
차단합니다. 서명·공증된 `.dmg`는 `scripts/release.sh`로 만듭니다.

**준비물(1회):** Apple Developer 계정($99/년) + **Developer ID Application** 인증서.
```bash
# 인증서 확인
security find-identity -v -p codesigning
# 공증 자격증명 저장(앱 암호는 appleid.apple.com에서 발급)
xcrun notarytool store-credentials quota-notary \
  --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-pw"
```
**릴리스:**
```bash
DEV_ID="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="quota-notary" scripts/release.sh
# → Quota.dmg 생성. 받는 사람은 Applications로 드래그 후 실행.
```
정식 Developer ID로 서명하면 **로그인 토큰이 업데이트 후에도 유지**됩니다(ad-hoc은 빌드마다
서명이 바뀌어 재로그인 필요). 각 사용자는 자기 Claude 계정으로 로그인하며, 토큰은 각자
Keychain에만 저장됩니다.

> **주의:** 이 앱은 Claude Code의 client_id/User-Agent와 비공개 엔드포인트를 사용하는
> 비공식 도구입니다(ToS 회색지대). 공유·사용은 본인 책임이며, 위 README의 경고를 함께
> 전달하세요.
