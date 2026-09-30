#include "../../windows/runner/shell_integration.h"
#include <shellapi.h>
#include <shlobj.h>
#include <iostream>
#include <stdexcept>

void Check(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

// Explorer's data object, containing two Unicode paths including a directory.
class Selection final : public IDataObject {
 public:
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** output) override {
    *output = nullptr;
    if (iid != IID_IUnknown && iid != IID_IDataObject) return E_NOINTERFACE;
    *output = this;
    AddRef();
    return S_OK;
  }
  ULONG STDMETHODCALLTYPE AddRef() override { return ++references_; }
  ULONG STDMETHODCALLTYPE Release() override { return --references_; }
  HRESULT STDMETHODCALLTYPE GetData(FORMATETC* format, STGMEDIUM* medium) override {
    if (FAILED(QueryGetData(format))) return DV_E_FORMATETC;
    const wchar_t paths[] = L"C:\\资料\\a space.zip\0C:\\资料\\文件夹\0";
    const SIZE_T bytes = sizeof(DROPFILES) + sizeof(paths);
    const auto memory = GlobalAlloc(GHND, bytes);
    if (!memory) return E_OUTOFMEMORY;
    auto* drop = static_cast<DROPFILES*>(GlobalLock(memory));
    drop->pFiles = sizeof(DROPFILES);
    drop->fWide = TRUE;
    memcpy(reinterpret_cast<BYTE*>(drop) + sizeof(DROPFILES), paths, sizeof(paths));
    GlobalUnlock(memory);
    medium->tymed = TYMED_HGLOBAL;
    medium->hGlobal = memory;
    medium->pUnkForRelease = nullptr;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE QueryGetData(FORMATETC* format) override {
    return format && format->cfFormat == CF_HDROP ? S_OK : DV_E_FORMATETC;
  }
  HRESULT STDMETHODCALLTYPE GetDataHere(FORMATETC*, STGMEDIUM*) override { return E_NOTIMPL; }
  HRESULT STDMETHODCALLTYPE GetCanonicalFormatEtc(FORMATETC*, FORMATETC*) override { return E_NOTIMPL; }
  HRESULT STDMETHODCALLTYPE SetData(FORMATETC*, STGMEDIUM*, BOOL) override { return E_NOTIMPL; }
  HRESULT STDMETHODCALLTYPE EnumFormatEtc(DWORD, IEnumFORMATETC**) override { return E_NOTIMPL; }
  HRESULT STDMETHODCALLTYPE DAdvise(FORMATETC*, DWORD, IAdviseSink*, DWORD*) override { return E_NOTIMPL; }
  HRESULT STDMETHODCALLTYPE DUnadvise(DWORD) override { return E_NOTIMPL; }
  HRESULT STDMETHODCALLTYPE EnumDAdvise(IEnumSTATDATA**) override { return E_NOTIMPL; }
 private:
  ULONG references_ = 1;
};

int main() {
  Check(SUCCEEDED(OleInitialize(nullptr)), "OLE initialization");
  // Redirect all HKCU accesses to a unique test root. No production
  // menu registrations or preferences are read, modified or removed.
  const auto root = L"Software\\Jucier\\ShellTest-" + std::to_wstring(GetCurrentProcessId());
  HKEY sandbox = nullptr;
  Check(RegCreateKeyExW(HKEY_CURRENT_USER, root.c_str(), 0, nullptr,
      REG_OPTION_NON_VOLATILE, KEY_ALL_ACCESS, nullptr, &sandbox, nullptr) == ERROR_SUCCESS,
      "create isolated registry");
  Check(RegOverridePredefKey(HKEY_CURRENT_USER, sandbox) == ERROR_SUCCESS,
        "redirect registry");
  int result = 0;
  try {
    Check(!shell_integration::Available(), "initially uninstalled");
    Check(shell_integration::Uninstall() == ERROR_SUCCESS, "uninstall absent keys");
    Check(shell_integration::Install() == ERROR_SUCCESS, "install");
    Check(shell_integration::Available(), "installed status");
    Check(shell_integration::Install() == ERROR_SUCCESS, "idempotent reinstall");
    HKEY other = nullptr;
    Check(RegCreateKeyExW(HKEY_CURRENT_USER, L"Software\\Classes\\*\\shell\\OtherApp", 0,
        nullptr, 0, KEY_ALL_ACCESS, nullptr, &other, nullptr) == ERROR_SUCCESS, "other app key");
    RegCloseKey(other);
    Check(RegDeleteTreeW(HKEY_CURRENT_USER,
        L"Software\\Classes\\CLSID\\{A1F81380-4843-4CE9-B842-1893FD8C4103}\\LocalServer32")
        == ERROR_SUCCESS, "damage one registration");
    Check(!shell_integration::Available(), "partial install detected");
    Check(shell_integration::Install() == ERROR_SUCCESS, "repair");
    Check(shell_integration::Available(), "repair restores status");

    std::string action;
    std::vector<std::string> paths;
    Check(SUCCEEDED(shell_integration::Register([&](const auto& name, const auto& items) {
      action = name;
      paths = items;
    })), "register COM classes");
    const char* actions[] = {"extractHere", "extractTo", "compressZip", "compress"};
    for (int index = 0; index < 4; ++index) {
      const auto id = L"{A1F81380-4843-4CE9-B842-1893FD8C410" + std::to_wstring(index + 1) + L"}";
      CLSID clsid{};
      CLSIDFromString(id.c_str(), &clsid);
      IDropTarget* target = nullptr;
      Check(SUCCEEDED(CoCreateInstance(clsid, nullptr, CLSCTX_LOCAL_SERVER,
          IID_IDropTarget, reinterpret_cast<void**>(&target))), "activate drop target");
      Selection selection;
      DWORD effect = DROPEFFECT_COPY;
      Check(SUCCEEDED(target->DragEnter(&selection, 0, {}, &effect)), "drag enter");
      Check(effect == DROPEFFECT_COPY, "supported selection");
      Check(SUCCEEDED(target->Drop(&selection, 0, {}, &effect)), "drop selection");
      target->Release();
      Check(action == actions[index], "correct action");
      Check(paths == std::vector<std::string>{"C:\\资料\\a space.zip", "C:\\资料\\文件夹"},
            "Unicode multi-selection round trip");
    }
    shell_integration::Unregister();
    Check(shell_integration::Uninstall() == ERROR_SUCCESS, "uninstall");
    Check(!shell_integration::Available(), "uninstalled status");
    Check(RegOpenKeyExW(HKEY_CURRENT_USER, L"Software\\Classes\\*\\shell\\OtherApp",
        0, KEY_READ, &other) == ERROR_SUCCESS, "preserve other apps");
    RegCloseKey(other);
    Check(shell_integration::Uninstall() == ERROR_SUCCESS, "idempotent uninstall");
    std::cout << "WINDOWS_SHELL_INTEGRATION_PASSED\n";
  } catch (const std::exception& error) {
    std::cerr << error.what() << "\n";
    result = 1;
    shell_integration::Unregister();
  }
  RegOverridePredefKey(HKEY_CURRENT_USER, nullptr);
  RegCloseKey(sandbox);
  RegDeleteTreeW(HKEY_CURRENT_USER, root.c_str());
  OleUninitialize();
  return result;
}
