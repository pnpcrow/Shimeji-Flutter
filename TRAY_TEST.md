# 트레이 콜백 진단 — 사용자 확인 절차

지금 실행 중인 디버그 빌드에서:

1. 트레이 아이콘 우클릭 → 메뉴가 열리면 "Call Shimeji" 클릭
2. 이어서 "Exit" 클릭

그 후 아래 파일을 보내주시면 됩니다:
C:\Develop\Repositories\shimeji-flutter\cb.log

확인 포인트:
- "TRAY CallShimeji clicked" / "TRAY Exit clicked" 가 찍히는지
  → 찍히면 콜백은 살아있고 버그는 다른 곳
- 안 찍히면 system_tray의 Dart 콜백 라우팅이 깨진 것 (menuId 불일치)
