# Shimeji Flutter

[Shimeji-Desktop](https://github.com/DalekCraft2/Shimeji-Desktop)(Shimeji-ee 1.0.22 포크, Java)를
**Pure Flutter/Dart로 재작성**한 데스크톱 마스코트 앱입니다. 원본의 124개 Java 소스 파일을
Dart로 포팅했고, Java 런타임/JNA/Nashorn에 의존하던 부분은 pub.dev 플러그인과 자체 구현으로
대체했습니다.

```
flutter build windows --release
build\windows\x64\runner\Release\shimeji_flutter.exe
```

빌드가 곧 배포입니다 — 원본 Shimeji-ee와 마찬가지로 exe를 실행하면 같은 폴더에
`conf/`, `img/`(번들 에셋에서 1회 추출)가 만들어지고, 이후에는 그 파일들을 직접 수정해
마스코트를 커스터마이징할 수 있습니다.

## 동작 (검증 완료)

- 마스코트 스폰 → 낙하 → 작업표시줄(작업 영역 하단) 위 걷기
- 벽/천장 등반, 창 가장자리 보행 (원본 Border 수학 그대로 이식)
- 마우스로 잡아 끌기(Dragged) → 흔들리며 따라옴 → 놓으면 커서 속도로 던져짐(Thrown → Fall)
- 브리딩(SplitIntoTwo 등), 행동 가중치 랜덤 선택, 조건 스크립트 평가
- 우클릭 컨텍스트 메뉴 (Call Another / Follow Cursor / 행동 목록 / Dismiss 등)
- 트레이 아이콘 + 메뉴 (Call Shimeji, Reduce To One, Choose Shimeji, Settings, 체크박스 설정들)
- `conf/settings.properties` 저장/복원 (원본과 동일한 키)

## Java → Flutter 대응표

| 원본 (Java) | 포트 (Flutter/Dart) | 비고 |
|---|---|---|
| AWT/Swing 투명 JWindow(마스코트당 1개) | **단일 오버레이 윈도우** + 컬러키 투명 | `WS_EX_LAYERED` + `LWA_COLORKEY`(마젠타) — 픽셀 단위 클릭스루를 OS가 처리 |
| JNA(jna-platform) Win32 접근 | [`win32`](https://pub.dev/packages/win32) (Dart FFI) | EnumWindows z-order 활성 창 탐지, DWM cloaked/maximized 필터, 모니터 작업 영역, SetWindowPos(창 던지기) |
| Nashorn JS 스크립트 (`#{...}`/`${...}`) | 자체 구현 JS 서브셋 평가기 (`lib/src/script/`) | Shimeji 설정이 쓰는 문법 전체(속성 탐색, `isOn()` 메서드 호출, `Math.*`, 삼항/비교/논리) 지원, 프레임별 재평가/캐시 의미론 보존 |
| javax.sound.sampled Clip | [`audioplayers`](https://pub.dev/packages/audioplayers) | dB 볼륨(MASTER_GAIN 호환) |
| Swing 트레이/메뉴/다이얼로그 | [`system_tray`](https://pub.dev/packages/system_tray) + Flutter 오버레이 UI | 이미지셋 선택기/설정/통계 패널을 오버레이에 렌더링 |
| ImageIO + hqx(Hq2x/3x/4x) | `dart:ui` 디코딩 + **hqx 순수 Dart 포팅** (`tool/convert_hqx.py`로 Java→Dart 자동 변환) | nearest/bicubic은 Flutter FilterQuality, hqx는 픽셀 알고리즘 그대로 |
| java.util.ResourceBundle (.properties) | 자체 properties 파서 (`Settings`, `LanguageBundle`) | 언어 파일 21개 국어 그대로 사용 |
| Swing Timer 틱 루프(40ms/25FPS) | `Timer.periodic(40ms)` 단일 isolate | 로직/렌더 2-pass 구조 보존 |

### 포팅된 엔진 (`lib/src/`)

- `action/` — 원본 30여 개 액션 전부: Walk/Move/Stay/Animate/Jump/Fall/Dragged/Regist/
  Turn/Look/Offset/Mute/SelfDestruct/Transform/Breed(+Move/Jump)/Interact/ScanMove/
  ScanJump/ScanInteract/ComplexMove/ComplexJump/ThrowIE/FallWithIE/WalkWithIE/
  Sequence/Select + deprecated 계열(Broadcast*, MoveWithTurn)
- `config/` — actions.xml/behaviors.xml 파서(ActionBuilder/AnimationBuilder/
  BehaviorBuilder/BehaviorRef), 스키마(영어/일본어 태그명 모두 지원)
- `behavior/` — UserBehavior(핫스팟, 드래그/던지기, 화면 밖 텔레포트 복귀)
- `environment/` — Area/Border/FloorCeiling/Wall(창 이동 추적 Δ클램프 포함),
  WindowsEnvironment(활성 창 화이트리스트/블랙리스트 캐시 포함)
- `image/` — ImagePairs 캐시, 앵커/좌우 반전, 알파 마스크(히트 테스트), hqx
- `mascot.dart`, `manager.dart` — 틱 동기화, affordance/스캔, 브리딩, 개체 관리

## 아키텍처 노트

- **렌더링**: 원본은 마스코트당 투명 윈도우였지만, Flutter는 단일 전체화면
  always-on-top 오버레이로 모든 마스코트를 그립니다(25FPS CustomPaint).
  오버레이 배경은 순수 마젠타(`0xFFFF00FF`)이고 러너가 이 색을 컬러키로 지정해
  투명+클릭스루 처리합니다. 마젠타 픽셀은 실제 화면에서 완전히 투명하며 마우스 이벤트도
  통과합니다(`WindowFromPoint`로 검증). DWM accent 방식과 달리 원격 데스크톱에서도 동작합니다.
- **좌표계**: 엔진 전체가 물리 픽셀 좌표(원본의 DPI 보정 문제를 우회), 렌더링 시에만
  devicePixelRatio로 변환합니다.
- **입력**: 커서/버튼 상태를 틱마다 폴링(GetCursorPos/GetAsyncKeyState) — 원본의 이벤트
  기반 흐름과 동일한 의미론(누름→Dragged, 놓음→Thrown)을 유지합니다.
- **hqx**: `tool/convert_hqx.py`가 Java 소스를 자동 변환했습니다(`lib/src/image/hqx/`).
  `Filter=hqx` 설정 시 2/3/4배수 스케일에서 사용됩니다.

## 제한 사항 (원본 대비)

- 오버레이는 주 모니터 DPI 기준 가상 화면에 맞춰져 있습니다. 서로 다른 DPI의 다중 모니터
  경계에서는 원본과 유사한 한계가 있습니다.
- 컬러키 방식 특성상 반투명 합성(불투명도 슬라이더, 그림자)은 마젠타와의 블렌딩으로
  표현됩니다. 스프라이트에 순수 마젠타(#FF00FF) 픽셀이 있으면 구멍이 됩니다.
- `InteractiveWindows` 기능(활성 창 던지기 등)은 설정에 타이틀 문자열을 넣어야 활성화됩니다
  (원본과 동일).
- X11/macOS 전용 플랫폼 레이어는 미포팅(Windows 우선).

## 라이선스

원본 Shimeji-Desktop의 Zlib/BSD-2-Clause, hqx-java의 LGPL-3.0을 따릅니다.
기본 이미지셋(Shimeji, KuroShimeji)과 conf는 원본 저장소에서 가져왔습니다.
