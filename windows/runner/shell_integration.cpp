#include "shell_integration.h"

#include <shellapi.h>
#include <shlobj.h>
#include <array>
#include <utility>

namespace shell_integration {
namespace {
constexpr wchar_t kClasses[] = L"Software\\Classes\\";
struct Action {
  const wchar_t* id;
  const wchar_t* label;
  const char* name;
};
constexpr std::array<Action, 4> kActions = {{
    {L"{A1F81380-4843-4CE9-B842-1893FD8C4101}", L"解压到当前位置", "extractHere"},
    {L"{A1F81380-4843-4CE9-B842-1893FD8C4102}", L"解压到…", "extractTo"},
    {L"{A1F81380-4843-4CE9-B842-1893FD8C4103}", L"压缩为 ZIP", "compressZip"},
    {L"{A1F81380-4843-4CE9-B842-1893FD8C4104}", L"压缩…", "compress"},
}};
constexpr std::array<const wchar_t*, 2> kMenus = {
    L"*\\shell\\Jucier", L"Directory\\shell\\Jucier"};
// Keep aligned with supportedArchiveExtensions in lib/archive/archive_formats.dart.
constexpr const wchar_t* kExtensions[] = {
    L"zip", L"7z", L"rar", L"tar", L"gz", L"tgz", L"bz2", L"tbz2",
    L"tbz", L"xz", L"txz", L"zst", L"tzst", L"zipx", L"jar", L"apk",
    L"xpi", L"epub", L"cab", L"iso", L"dmg", L"wim", L"swm", L"esd",
    L"lzh", L"lha", L"arj", L"cpio", L"deb", L"rpm", L"xar", L"xip", L"001"};

struct Entry { std::wstring key; std::wstring name; std::wstring value; };
std::vector<Entry> Entries() {
  wchar_t executable[32768];
  const auto length = GetModuleFileNameW(nullptr, executable, 32768);
  if (!length || length >= 32768) return {};
  const std::wstring command = L"\"" + std::wstring(executable) + L"\" --shell-server";
  std::wstring archives;
  for (const auto* extension : kExtensions) {
    if (!archives.empty()) archives += L" OR ";
    archives += L"System.FileExtension:=\"." + std::wstring(extension) + L"\"";
  }
  std::vector<Entry> entries;
  for (size_t index = 0; index < kActions.size(); ++index) {
    const auto& action = kActions[index];
    const std::wstring clsid = std::wstring(kClasses) + L"CLSID\\" + action.id;
    entries.push_back({clsid, L"", L"Jucier Explorer action"});
    entries.push_back({clsid + L"\\LocalServer32", L"", command});
    for (const auto* menu : kMenus) {
      if (menu == kMenus[1] && index < 2) continue;
      const std::wstring root = std::wstring(kClasses) + menu;
      if (index == 2) {
        entries.push_back({root, L"MUIVerb", L"Jucier"});
        entries.push_back({root, L"Icon", L"\"" + std::wstring(executable) + L"\",0"});
        entries.push_back({root, L"SubCommands", L""});
        entries.push_back({root, L"MultiSelectModel", L"Player"});
      }
      const std::wstring verb = root + L"\\shell\\" + std::to_wstring(index);
      entries.push_back({verb, L"MUIVerb", action.label});
      entries.push_back({verb, L"MultiSelectModel", L"Player"});
      entries.push_back({verb + L"\\DropTarget", L"CLSID", action.id});
      if (index < 2) entries.push_back({verb, L"AppliesTo", archives});
    }
  }
  return entries;
}

std::array<DWORD, 4> cookies{};
ActionHandler on_action;

class DropTarget final : public IDropTarget {
 public:
  explicit DropTarget(size_t action) : action_(action) {}
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** result) override {
    if (!result) return E_POINTER;
    *result = nullptr;
    if (iid != IID_IUnknown && iid != IID_IDropTarget) return E_NOINTERFACE;
    *result = static_cast<IDropTarget*>(this);
    AddRef();
    return S_OK;
  }
  ULONG STDMETHODCALLTYPE AddRef() override { return ++references_; }
  ULONG STDMETHODCALLTYPE Release() override {
    const auto count = --references_;
    if (!count) delete this;
    return count;
  }
  HRESULT STDMETHODCALLTYPE DragEnter(IDataObject* data, DWORD, POINTL,
                                      DWORD* effect) override {
    FORMATETC format{CF_HDROP, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
    supported_ = data && SUCCEEDED(data->QueryGetData(&format));
    *effect = supported_ ? DROPEFFECT_COPY : DROPEFFECT_NONE;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE DragOver(DWORD, POINTL, DWORD* effect) override {
    *effect = supported_ ? DROPEFFECT_COPY : DROPEFFECT_NONE;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE DragLeave() override { return S_OK; }
  HRESULT STDMETHODCALLTYPE Drop(IDataObject* data, DWORD, POINTL,
                                 DWORD* effect) override {
    *effect = DROPEFFECT_NONE;
    if (!data || !on_action) return E_INVALIDARG;
    FORMATETC format{CF_HDROP, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
    STGMEDIUM medium{};
    const auto status = data->GetData(&format, &medium);
    if (FAILED(status)) return status;
    const auto drop = static_cast<HDROP>(medium.hGlobal);
    const auto count = DragQueryFileW(drop, 0xffffffff, nullptr, 0);
    std::vector<std::string> paths;
    for (UINT index = 0; index < count; ++index) {
      const auto length = DragQueryFileW(drop, index, nullptr, 0);
      std::wstring path(length + 1, L'\0');
      DragQueryFileW(drop, index, path.data(), length + 1);
      path.resize(length);
      const auto bytes = WideCharToMultiByte(CP_UTF8, 0, path.data(),
          static_cast<int>(length), nullptr, 0, nullptr, nullptr);
      std::string utf8(bytes, '\0');
      WideCharToMultiByte(CP_UTF8, 0, path.data(), static_cast<int>(length),
          utf8.data(), bytes, nullptr, nullptr);
      if (!utf8.empty()) paths.push_back(std::move(utf8));
    }
    ReleaseStgMedium(&medium);
    if (paths.empty()) return E_INVALIDARG;
    on_action(kActions[action_].name, paths);
    *effect = DROPEFFECT_COPY;
    return S_OK;
  }
 private:
  ULONG references_ = 1;
  size_t action_;
  bool supported_ = false;
};

class Factory final : public IClassFactory {
 public:
  explicit Factory(size_t action) : action_(action) {}
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** result) override {
    if (!result) return E_POINTER;
    *result = nullptr;
    if (iid != IID_IUnknown && iid != IID_IClassFactory) return E_NOINTERFACE;
    *result = static_cast<IClassFactory*>(this);
    AddRef();
    return S_OK;
  }
  ULONG STDMETHODCALLTYPE AddRef() override { return ++references_; }
  ULONG STDMETHODCALLTYPE Release() override {
    const auto count = --references_;
    if (!count) delete this;
    return count;
  }
  HRESULT STDMETHODCALLTYPE CreateInstance(IUnknown* outer, REFIID iid,
                                           void** result) override {
    if (outer) return CLASS_E_NOAGGREGATION;
    auto* target = new DropTarget(action_);
    const auto status = target->QueryInterface(iid, result);
    target->Release();
    return status;
  }
  HRESULT STDMETHODCALLTYPE LockServer(BOOL) override { return S_OK; }
 private:
  ULONG references_ = 1;
  size_t action_;
};
}  // namespace

bool Available() {
  const auto entries = Entries();
  if (entries.empty()) return false;
  for (const auto& entry : entries) {
    DWORD bytes = 0;
    if (RegGetValueW(HKEY_CURRENT_USER, entry.key.c_str(), entry.name.c_str(),
        RRF_RT_REG_SZ, nullptr, nullptr, &bytes) != ERROR_SUCCESS) return false;
    if (bytes > 65536) return false;
    std::wstring value(bytes / sizeof(wchar_t), L'\0');
    if (RegGetValueW(HKEY_CURRENT_USER, entry.key.c_str(), entry.name.c_str(),
        RRF_RT_REG_SZ, nullptr, value.data(), &bytes) != ERROR_SUCCESS) return false;
    // The size query may reserve an extra terminator; use the bytes read.
    value.resize(bytes / sizeof(wchar_t));
    if (value != entry.value + L'\0') return false;
  }
  return true;
}

LSTATUS Install() {
  const auto entries = Entries();
  if (entries.empty()) return ERROR_BAD_PATHNAME;
  for (const auto& entry : entries) {
    HKEY key = nullptr;
    auto status = RegCreateKeyExW(HKEY_CURRENT_USER, entry.key.c_str(), 0,
        nullptr, 0, KEY_SET_VALUE, nullptr, &key, nullptr);
    if (status != ERROR_SUCCESS) return status;
    status = RegSetValueExW(key, entry.name.c_str(), 0, REG_SZ,
        reinterpret_cast<const BYTE*>(entry.value.c_str()),
        static_cast<DWORD>((entry.value.size() + 1) * sizeof(wchar_t)));
    RegCloseKey(key);
    if (status != ERROR_SUCCESS) return status;
  }
  SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nullptr, nullptr);
  return ERROR_SUCCESS;
}

LSTATUS Uninstall() {
  LSTATUS result = ERROR_SUCCESS;
  auto remove = [&result](const std::wstring& path) {
    const auto status = RegDeleteTreeW(HKEY_CURRENT_USER, path.c_str());
    if (status != ERROR_SUCCESS && status != ERROR_FILE_NOT_FOUND &&
        status != ERROR_PATH_NOT_FOUND) result = status;
  };
  for (const auto* menu : kMenus) remove(std::wstring(kClasses) + menu);
  for (const auto& action : kActions)
    remove(std::wstring(kClasses) + L"CLSID\\" + action.id);
  SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nullptr, nullptr);
  return result;
}

HRESULT Register(ActionHandler handler) {
  on_action = std::move(handler);
  for (size_t index = 0; index < kActions.size(); ++index) {
    CLSID clsid{};
    CLSIDFromString(kActions[index].id, &clsid);
    auto* factory = new Factory(index);
    const auto status = CoRegisterClassObject(clsid, factory, CLSCTX_LOCAL_SERVER,
        REGCLS_MULTIPLEUSE, &cookies[index]);
    factory->Release();
    if (FAILED(status)) { Unregister(); return status; }
  }
  return S_OK;
}

void Unregister() {
  for (auto& cookie : cookies) {
    if (cookie) CoRevokeClassObject(cookie);
    cookie = 0;
  }
  on_action = nullptr;
}
}  // namespace shell_integration
