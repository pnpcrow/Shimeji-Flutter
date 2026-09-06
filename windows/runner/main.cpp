#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // Single instance, like the original launch4j mutex: a second launch must
  // not stack a second set of mascot windows.
  HANDLE instance_mutex =
      ::CreateMutexW(nullptr, TRUE, L"ShimejiFlutterSingleInstance");
  if (instance_mutex == nullptr ||
      ::GetLastError() == ERROR_ALREADY_EXISTS) {
    if (instance_mutex != nullptr) {
      ::CloseHandle(instance_mutex);
    }
    return EXIT_FAILURE;
  }

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));
  // On hybrid-GPU handhelds the default adapter selection can present to an
  // adapter with no scanout (black window); prefer the integrated GPU.
  project.set_gpu_preference(flutter::GpuPreference::HighPerformancePreference);
  project.set_impeller_switch(flutter::ImpellerSwitch::Disabled);

  FlutterWindow window(project);
  // The overlay covers the entire virtual desktop in physical pixels.
  const int vs_x = GetSystemMetrics(SM_XVIRTUALSCREEN);
  const int vs_y = GetSystemMetrics(SM_YVIRTUALSCREEN);
  const int vs_w = GetSystemMetrics(SM_CXVIRTUALSCREEN);
  const int vs_h = GetSystemMetrics(SM_CYVIRTUALSCREEN);
  Win32Window::Point origin(vs_x, vs_y);
  Win32Window::Size size(vs_w, vs_h);
  if (!window.Create(L"shimeji_flutter", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (instance_mutex != nullptr) {
    ::CloseHandle(instance_mutex);
  }
  return EXIT_SUCCESS;
}
