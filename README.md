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

현재 구현된 유일한 프레젠테이션 경로는 **레거시 렌더링 모드(Legacy)** 입니다 —
원본 Java 아키텍처(마스코트마다 픽셀 알파 네이티브 윈도우)를 그대로 이어받은 방식으로,
`settings.properties`의 `RenderingMode=legacy` 키로 저장되고 설정 화면에서 확인/선택할 수
있습니다. 향후 렌더링 모드가 추가되면 같은 키로 확장됩니다.

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
- 트레이 아이콘 + 메뉴 (Call Shimeji, Reduce To One, Choose Shimeji, Settings, 체크박스 설정들)
- `conf/settings.properties` 저장/복원 (원본과 동일한 키)

## Java → Flutter 대응표

| 원본 (Java) | 포트 (Flutter/Dart) | 비고 |
|---|---|---|
| AWT/Swing 투명 JWindow(마스코트당 1개) | **마스코트당 네이티브 레이어드 윈도우** (`UpdateLayeredWindow`) | Dart 엔진이 포즈 비트맵(프리멀티플라이드 BGRA)을 채널로 밀고 네이티브가 표시 — 픽셀 알파 투명/클릭스루를 DWM이 처리 |
| JNA(jna-platform) Win32 접근 | [`win32`](https://pub.dev/packages/win32) (Dart FFI) | EnumWindows z-order 활성 창 탐지, DWM cloaked/maximized 필터, 모니터 작업 영역, SetWindowPos(창 던지기) |
| Nashorn JS 스크립트 (`#{...}`/`${...}`) | 자체 구현 JS 서브셋 평가기 (`lib/src/script/`) | Shimeji 설정이 쓰는 문법 전체(속성 탐색, `isOn()` 메서드 호출, `Math.*`, 삼항/비교/논리) 지원, 프레임별 재평가/캐시 의미론 보존 |
| javax.sound.sampled Clip | [`audioplayers`](https://pub.dev/packages/audioplayers) | dB 볼륨(MASTER_GAIN 호환) |
| Swing 트레이/메뉴/다이얼로그 | [`system_tray`](https://pub.dev/packages/system_tray) + **네이티브 Win32 팝업 메뉴** (`TrackPopupMenu`) | 마스코트 컨텍스트 메뉴는 네이티브 팝업(항목 선택 인덱스를 Dart 콜백에 매핑), 트레이에 이미지셋/언어 체크박스 서브메뉴 |
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

- **렌더링**: 원본과 동일하게 마스코트마다 최상위 투명 윈도우를 하나씩 갖습니다.
  Flutter 엔진은 헤드리스로 실행되고, 매 틱(40ms) 각 마스코트의 현재 포즈를
  프리멀티플라이드 BGRA 비트맵으로 변환해 `UpdateLayeredWindow`로 표시합니다
  (`lib/src/native/mascot_windows.dart` ↔ 러너 `mascot_windows.cpp`).
  픽셀 알파 투명과 클릭스루(알파 0 픽셀 통과)는 DWM 레벨에서 처리되므로
  원격 데스크톱/하이브리드 GPU에서도 동일하게 동작합니다. (DWM accent나 컬러키
  방식은 Flutter의 D3D 자식 뷰 픽셀에는 적용되지 않아 기각했습니다.)
- **좌표계**: 엔진 전체가 물리 픽셀 좌표(원본의 DPI 보정 문제를 우회).
- **입력**: 커서/버튼 상태를 틱마다 폴링(GetCursorPos/GetAsyncKeyState) — 누름→Dragged,
  놓음→Thrown, 우클릭 놓음→컨텍스트 메뉴. 메뉴는 러너의 `TrackPopupMenu`으로 표시되며
  선택된 항목 인덱스가 Dart의 동작 콜백으로 반환됩니다.
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

## 제한 사항 (원본 대비)

- 오버레이는 주 모니터 DPI 기준 가상 화면에 맞춰져 있습니다. 서로 다른 DPI의 다중 모니터
  경계에서는 원본과 유사한 한계가 있습니다.
- 스프라이트 불투명도(Opacity)는 네이티브 프레젠테이션에서 알파 배수로 적용됩니다.
- `InteractiveWindows` 기능(활성 창 던지기 등)은 설정에 타이틀 문자열을 넣어야 활성화됩니다
  (원본과 동일).
- 상세 설정 창(스케일/불투명도/대화형 창 목록 편집)은 `conf/settings.properties`를 직접
  편집하는 방식으로 대체했습니다(트레이 체크박스 항목은 모두 동작).
- X11/macOS 전용 플랫폼 레이어는 미포팅(Windows 우선).
- 가상 윈도우 모드(`Environment=virtual`, 디버그용 창 에뮬레이션)은 미포팅 — 설정 파일에는
  값이 그대로 보존됩니다.
- 트레이 언어 전환은 접속된 language_*.properties 기반(원본은 로캘 라디오 메뉴와 동일 효과).

## 라이선스

원본 Shimeji-Desktop의 Zlib/BSD-2-Clause, hqx-java의 LGPL-3.0을 따릅니다.
기본 이미지셋(Shimeji, KuroShimeji)과 conf는 원본 저장소에서 가져왔습니다.
