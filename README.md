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

## 렌더링 모드

두 가지 프레젠테이션 경로가 있으며, 설정 화면의 **렌더링 모드** 드롭다운에서 런타임에
전환할 수 있습니다 (`settings.properties`의 `RenderingMode` 키로 저장).

- **레거시 (네이티브 창, `legacy`, 기본값)** — 원본 Java 아키텍처(마스코트마다 픽셀 알파
  네이티브 레이어드 윈도우, `UpdateLayeredWindow`)를 그대로 이어받은 방식입니다. 컨텍스트
  메뉴는 네이티브 Win32 팝업(`TrackPopupMenu`)으로 표시됩니다.
- **Flutter (`flutter`)** — 마스코트마다 네이티브 윈도우를 하나씩 갖는다는 점은 레거시와
  동일하지만(개별 오브젝트, 물리 좌표 지오메트리로 모니터 간 이동 가능, 전체화면 오버레이
  없음), 각 창이 자체 Flutter 엔진을 호스팅해 현재 포즈를 Flutter 위젯 트리로 렌더링합니다.
  투명도는 테두리 없는 창 + DWM 글래스 프레임 확장(`DwmExtendFrameIntoClientArea`)으로
  처리하고, 클릭스루는 네이티브 `WM_NCHITTEST`에서 포즈 알파를 조회해 레거시와 동일한
  픽셀 단위 규칙(알파 0 통과, 불투명 픽셀 흡수)을 적용합니다. 컨텍스트 메뉴도 별도의
  Flutter 윈도우(전용 엔진, 시작 시 프리워밍)로 렌더링합니다 — 서브메뉴는 팝업 대신
  우측 열 확장으로 열리고, 항목 선택/Esc/포커스 상실이 메인 엔진의 액션으로 이어집니다.

포즈 픽셀 데이터는 포즈가 실제로 바뀔 때만 전송되고(이동만 하는 틱은 네이티브
`SetWindowPos`로 채널 트래픽 없이 처리), 모드 전환 시 두 렌더러의 모든 창을 정리하고
마스코트를 새 프레젠터로 리스폰합니다(디코딩된 포즈는 재사용).

## 설정 화면 & 다국어

- 트레이 메뉴의 **Settings**로 설정 창이 열립니다 (호스트 윈도우를 일반 다이얼로그 크기로
  표시). 닫기(X)는 창을 숨길 뿐 엔진은 계속 실행됩니다.
- 설정 항목: 렌더링 모드, 언어(접속된 language_*.properties 전체), 스프라이트 스케일,
  불투명도, Breeding/Transients/Transformation/Throwing/Sound/Multiscreen 토글,
  Interactive Windows 타이틀 규칙.
- **다국어**: 트레이 Language 서브메뉴와 설정 화면에서 즉시 전환 가능하며, 21개 번역
  번들이 기본 포함되어 있습니다.

## 비상 통제 (트레이)

앱이 시작하면 **가장 먼저 트레이 아이콘과 메뉴**를 띄웁니다(구성 로딩보다 우선). 화면이
어떤 이유로 가려지더라도 트레이에서 Pause/Dismiss/Exit로 즉시 제어할 수 있고, 중복 실행은
싱글 인스턴스 뮤텍스로 차단됩니다. 트레이 맨 아래 Exit 항목은 언제든 프로세스를 종료합니다.

## 동작 (검증 완료)

- 마스코트 스폰 → 낙하 → 작업표시줄(작업 영역 하단) 위 걷기
- 벽/천장 등반, 창 가장자리 보행 (원본 Border 수학 그대로 이식)
- 마우스로 잡아 끌기(Dragged) → 흔들리며 따라옴 → 놓으면 커서 속도로 던져짐(Thrown → Fall)
- 브리딩(SplitIntoTwo 등), 행동 가중치 랜덤 선택, 조건 스크립트 평가
- 우클릭 컨텍스트 메뉴 (Call Another / Follow Cursor / 행동 목록 / Dismiss 등)
  — 레거시 네이티브 팝업과 Flutter 메뉴 윈도우 양쪽 모두 (항목 선택 → 액션 실행,
  서브메뉴 확장, Esc/포커스 상실 해제)
- Flutter 렌더러 모드: 마스코트별 Flutter 엔진 창 렌더링(투명·픽셀 단위 클릭스루),
  설정 화면에서 레거시 ⇄ Flutter 실시간 전환(마스코트 리스폰 + 설정 영속화)
- 트레이 아이콘 + 메뉴 (Call Shimeji, Reduce To One, Choose Shimeji, Settings, 체크박스 설정들)
- `conf/settings.properties` 저장/복원 (원본과 동일한 키)

## Java → Flutter 대응표

| 원본 (Java) | 포트 (Flutter/Dart) | 비고 |
|---|---|---|
| AWT/Swing 투명 JWindow(마스코트당 1개) | **마스코트당 네이티브 윈도우 1개** — 레거시: 레이어드 윈도우(`UpdateLayeredWindow`), Flutter: 자체 엔진 호스팅 창 | 레거시는 Dart 엔진이 포즈 비트맵(프리멀티플라이드 BGRA)을 밀고 네이티브가 표시. Flutter는 포즈 RGBA를 엔진에 전달해 위젯 트리로 렌더링. 두 모드 모두 픽셀 알파 투명/클릭스루 보존 |
| JNA(jna-platform) Win32 접근 | [`win32`](https://pub.dev/packages/win32) (Dart FFI) | EnumWindows z-order 활성 창 탐지, DWM cloaked/maximized 필터, 모니터 작업 영역, SetWindowPos(창 던지기) |
| Nashorn JS 스크립트 (`#{...}`/`${...}`) | 자체 구현 JS 서브셋 평가기 (`lib/src/script/`) | Shimeji 설정이 쓰는 문법 전체(속성 탐색, `isOn()` 메서드 호출, `Math.*`, 삼항/비교/논리) 지원, 프레임별 재평가/캐시 의미론 보존 |
| javax.sound.sampled Clip | [`audioplayers`](https://pub.dev/packages/audioplayers) | dB 볼륨(MASTER_GAIN 호환) |
| Swing 트레이/메뉴/다이얼로그 | [`system_tray`](https://pub.dev/packages/system_tray) + 마스코트 컨텍스트 메뉴(레거시: **네이티브 Win32 팝업** `TrackPopupMenu`, Flutter: **Flutter 메뉴 윈도우**) | 항목 선택 id가 Dart 콜백에 매핑되는 구조는 두 모드 동일, 트레이에 이미지셋/언어 체크박스 서브메뉴 |
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

- **렌더링(레거시)**: 원본과 동일하게 마스코트마다 최상위 투명 윈도우를 하나씩 갖습니다.
  Flutter 엔진은 헤드리스로 실행되고, 매 틱(40ms) 각 마스코트의 현재 포즈를
  프리멀티플라이드 BGRA 비트맵으로 변환해 `UpdateLayeredWindow`로 표시합니다
  (`lib/src/native/mascot_windows.dart` ↔ 러너 `mascot_windows.cpp`).
  픽셀 알파 투명과 클릭스루(알파 0 픽셀 통과)는 DWM 레벨에서 처리되므로
  원격 데스크톱/하이브리드 GPU에서도 동일하게 동작합니다. (DWM accent나 컬러키
  방식은 Flutter의 D3D 자식 뷰 픽셀에는 적용되지 않아 기각했습니다.)
- **렌더링(Flutter 모드)**: 같은 엔진 틱에서 프레젠터만 교체됩니다
  (`lib/src/native/flutter_mascot_windows.dart` ↔ 러너 `flutter_mascot_windows.cpp`).
  창은 `WS_EX_TRANSPARENT` 자식 Flutter 뷰 위에서 부모 `WM_NCHITTEST`가 포즈 알파를
  조회하는 구조이고, 마스코트 엔진은 `['mascot_window', '<id>']` 엔트리포인트 인자로
  `main()`이 분기해 최소 위젯 트리(`RawImage`)만 구동합니다. 컨텍스트 메뉴 엔진은
  `context_menu_window` 엔트리포인트로 부팅하며(`context_menu_window.cpp` ↔
  `lib/src/flutter_renderer/context_menu_window_app.dart`), 원하는 크기를 측정해
  되돌리면 네이티브가 모니터 작업 영역에 맞춰 배치/활성화합니다.
- **좌표계**: 엔진 전체가 물리 픽셀 좌표(원본의 DPI 보정 문제를 우회).
- **입력**: 커서/버튼 상태를 틱마다 폴링(GetCursorPos/GetAsyncKeyState) — 누름→Dragged,
  놓음→Thrown, 우클릭 놓음→컨텍스트 메뉴. 메뉴는 레거시에서는 러너의 `TrackPopupMenu`으로,
  Flutter 모드에서는 Flutter 메뉴 윈도우로 표시되며 선택된 항목 id가 Dart의 동작 콜백으로
  반환됩니다.
- **hqx**: `tool/convert_hqx.py`가 Java 소스를 자동 변환했습니다(`lib/src/image/hqx/`).
  `Filter=hqx` 설정 시 2/3/4배수 스케일에서 사용됩니다.

## 요구사항 감사 결과 (원본 대비 검증)

- 액션 클래스 1:1 대응 확인 (원본 39개 파일 ↔ Dart, deprecated Broadcast*/MoveWithTurn 별칭 포함)
- settings.properties 키 1:1 대응 확인 (DisabledBehaviours.<set> 동적 키 포함)
- 스키마 태그/속성명: 영어(en) + 일본어(ja) 매핑 이식
- hqx(Hq2x) 런타임 검증: `Filter=hqx` + `Scaling=2`로 실제 2배 업스케일 렌더링 확인
- 설정 플래그(Breeding/Transients/Transformation/Throwing/Sounds/Multiscreen/
  ShowTrayIcon/AlwaysShowShimejiChooser/AlwaysShowInformationScreen/DrawShimejiBounds/
  InteractiveWindows[Blacklist]/Language/Opacity/Scaling/Filter) 모두 연결됨
- 렌더링 모드(`RenderingMode=legacy|flutter`) 런타임 전환 검증: 양방향 전환 시
  창 클래스 전환(네이티브 레이어드 ⇄ Flutter 엔진 창)과 설정 영속화 확인

## 제한 사항 (원본 대비)

- 마스코트 창은 물리 픽셀 좌표로 관리되므로 서로 다른 DPI의 다중 모니터 경계에서는
  스케일이 자동 보정되지 않습니다 (원본과 유사한 한계).
- 스프라이트 불투명도(Opacity)는 레거시에서는 비트맵 알파 배수로, Flutter 모드에서는
  위젯 불투명도로 적용됩니다.
- `InteractiveWindows` 기능(활성 창 던지기 등)은 설정에 타이틀 문자열을 넣어야 활성화됩니다
  (원본과 동일).
- X11/macOS 전용 플랫폼 레이어는 미포팅(Windows 우선).
- 가상 윈도우 모드(`Environment=virtual`, 디버그용 창 에뮬레이션)은 미포팅 — 설정 파일에는
  값이 그대로 보존됩니다.
- 트레이 언어 전환은 접속된 language_*.properties 기반(원본은 로캘 라디오 메뉴와 동일 효과).

## 라이선스

원본 Shimeji-Desktop의 Zlib/BSD-2-Clause, hqx-java의 LGPL-3.0을 따릅니다.
기본 이미지셋(Shimeji, KuroShimeji)과 conf는 원본 저장소에서 가져왔습니다.
