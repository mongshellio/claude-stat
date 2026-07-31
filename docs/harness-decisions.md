# Harness Decisions

개발 하네스(mongshell-dev 플러그인) 를 이 프로젝트에 적용하면서 내린 **프로젝트 로컬** 결정 기록. 하네스 본체의 설계는 플러그인 SSOT 저장소가 권위이며, 여기에는 "이 프로젝트에서만 다르게 하기로 한 것" 만 남긴다.

형식은 [architecture-decisions.md](architecture-decisions.md) 와 같다.

## 상태 인덱스

| # | 결정 한 줄 | 상태 |
|---|-----------|------|
| #12 | 하네스 이식 시 `docs/design.md` 와 `browser-scenarios.md` 를 생략 | active |

---

## Decision #12: 하네스 이식 시 `docs/design.md` 와 `.claude/browser-scenarios.md` 를 생략

- **도입**: v1.1.0 (#12)
- **컨텍스트**: 하네스 이식 가이드는 UI 프로젝트에 `docs/design.md`(UI/UX 의 "왜") 와 `.claude/browser-scenarios.md`(브라우저 검증 시나리오) 를 요구한다. 이 프로젝트는 UI 가 있지만 **웹이 아니라 macOS 네이티브 메뉴바 앱**이다.
- **결정**: 두 문서를 만들지 않는다. 시각 검증 경로는 `MONGSHELL_SNAPSHOT` 스냅샷 렌더러이며 그 사용법은 [development.md](development.md) 가 권위다.
- **이유**:
  - `browser-scenarios.md` 는 라우트·로그인 절차를 전제하는데 이 앱에는 둘 다 없다. 브라우저가 등장하는 유일한 지점은 OAuth 로그인이고 그건 검증 시나리오가 아니라 인증 흐름이다.
  - `design.md` 가 요구하는 "새 primitive 추가 신호" 는 디자인 시스템을 전제한다. 이 앱의 UI 표면은 메뉴바 아이콘·팝오버·설정창 셋뿐이고, 색·치수 토큰은 `Design/Palette.swift` 가 이미 코드 레벨 SSOT 다. 문서를 하나 더 두면 토큰 권위가 둘로 갈린다.
- **결과**:
  - `/qa` 는 이 두 문서에 의존하는 단계를 "권위 문서 부재 — skip" 으로 처리한다. **의도된 skip 이며 이식 누락이 아니다.**
  - UI 의 "왜" 는 [PHILOSOPHY.md](PHILOSOPHY.md) § Design Principles 와 [architecture-decisions.md](architecture-decisions.md) 의 `#3`/`#5`/`#8` 이 나눠 갖는다.
  - UI 목업 게이트(루트 `CLAUDE.md` 상시 코어)는 그대로 유효하다 — 목업 산출물은 `design/` 디렉토리에 둔다.
- **재검토 조건**: UI 표면이 늘어나 `Palette` 만으로 일관성을 유지하기 어려워지면 `design.md` 를 도입한다.
