#include "../../windows/runner/win32_window.h"
#include <iostream>
#include <stdexcept>

void Check(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

int main() {
  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  try {
    Win32Window window;
    Check(window.Create(L"Jucier frame test", {100, 100}, {800, 600}), "create hidden window");
    const auto parent = window.GetHandle();
    const auto child = CreateWindowExW(0, L"STATIC", L"", WS_CHILD,
        0, 0, 0, 0, parent, nullptr, GetModuleHandleW(nullptr), nullptr);
    Check(child != nullptr, "create content");
    window.SetChildContent(child);
    RECT bounds{};
    GetWindowRect(parent, &bounds);
    const auto client = window.GetClientArea();
    Check(client.right == bounds.right - bounds.left &&
          client.bottom == bounds.bottom - bounds.top, "content fills system title bar");
    const auto dpi = GetDpiForWindow(parent);
    auto hit = [parent, dpi](int x, int y) {
      POINT point{MulDiv(x, dpi, 96), MulDiv(y, dpi, 96)};
      ClientToScreen(parent, &point);
      return SendMessageW(parent, WM_NCHITTEST, 0, MAKELPARAM(point.x, point.y));
    };
    Check(hit(200, 16) == HTCAPTION, "draggable immersive band");
    Check(hit(800 - 69, 16) == HTMAXBUTTON, "native maximize/Snap hit test");
    Check(hit(800 - 115, 16) == HTCLIENT, "Flutter minimize control");
    Check(hit(800 - 23, 16) == HTCLIENT, "Flutter close control");
    Check(hit(1, 1) == HTTOPLEFT, "resize corner");
    Check(hit(1, 200) == HTLEFT, "resize edge");
    Check(hit(200, 200) == HTCLIENT, "content interactions");
    POINT caption{MulDiv(200, dpi, 96), MulDiv(16, dpi, 96)};
    ClientToScreen(child, &caption);
    Check(SendMessageW(child, WM_NCHITTEST, 0, MAKELPARAM(caption.x, caption.y))
        == HTTRANSPARENT, "Flutter child routes caption hits to parent");
    MINMAXINFO sizes{};
    SendMessageW(parent, WM_GETMINMAXINFO, 0, reinterpret_cast<LPARAM>(&sizes));
    Check(sizes.ptMinTrackSize.x == MulDiv(520, dpi, 96) &&
          sizes.ptMinTrackSize.y == MulDiv(360, dpi, 96), "DPI-scaled minimum size");
    Check(!IsWindowVisible(parent), "test never shows a window");
    std::cout << "WINDOWS_FRAME_PASSED\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << "\n";
    return 1;
  }
}
