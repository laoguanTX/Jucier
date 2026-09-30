#include "platform_services.h"

#include <flutter/standard_message_codec.h>
#include <flutter/standard_method_codec.h>
#include <shellapi.h>

#include <optional>
#include <utility>

namespace {
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
using List = flutter::EncodableList;
constexpr wchar_t kPreferences[] = L"Software\\Jucier\\Preferences";

std::wstring Wide(const std::string& text) {
  if (text.empty()) return {};
  const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
      text.data(), static_cast<int>(text.size()), nullptr, 0);
  if (length == 0) return {};
  std::wstring result(length, L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(),
      static_cast<int>(text.size()), result.data(), length);
  return result;
}

std::optional<Value> ReadPreference(const std::string& name) {
  DWORD bytes = 0;
  const auto key = Wide(name);
  if (RegGetValueW(HKEY_CURRENT_USER, kPreferences, key.c_str(),
      RRF_RT_REG_BINARY, nullptr, nullptr, &bytes) != ERROR_SUCCESS ||
      bytes == 0 || bytes > 65536) return std::nullopt;
  std::vector<uint8_t> data(bytes);
  if (RegGetValueW(HKEY_CURRENT_USER, kPreferences, key.c_str(),
      RRF_RT_REG_BINARY, nullptr, data.data(), &bytes) != ERROR_SUCCESS) {
    return std::nullopt;
  }
  auto value = flutter::StandardMessageCodec::GetInstance().DecodeMessage(
      data.data(), bytes);
  if (!value) return std::nullopt;
  return *value;
}

bool WritePreference(const std::string& name, const Value& value) {
  HKEY registry = nullptr;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, kPreferences, 0, nullptr, 0,
      KEY_SET_VALUE, nullptr, &registry, nullptr) != ERROR_SUCCESS) return false;
  const auto data = flutter::StandardMessageCodec::GetInstance().EncodeMessage(value);
  const auto key = Wide(name);
  const auto status = RegSetValueExW(registry, key.c_str(), 0, REG_BINARY,
      data->data(), static_cast<DWORD>(data->size()));
  RegCloseKey(registry);
  return status == ERROR_SUCCESS;
}

Value FileAccess() {
  // Windows has no macOS security-scoped bookmark permission prompt. Actual
  // filesystem permissions are checked by each operation, using the OS errors.
  return Value(Map{{Value("requested"), Value(true)},
                   {Value("granted"), Value(true)}});
}

bool OpenFile(HWND window, const std::wstring& path) {
  SHELLEXECUTEINFOW info = {};
  info.cbSize = sizeof(info);
  info.fMask = SEE_MASK_NOASYNC | SEE_MASK_FLAG_NO_UI;
  info.hwnd = window;
  info.lpVerb = L"open";
  info.lpFile = path.c_str();
  info.nShow = SW_SHOWNORMAL;
  return ShellExecuteExW(&info) != FALSE;
}
}  // namespace

PlatformServices::PlatformServices(flutter::BinaryMessenger* messenger,
    HWND window, const std::vector<std::string>& arguments) {
  platform_ = std::make_unique<flutter::MethodChannel<Value>>(
      messenger, "dev.jucier/platform", &flutter::StandardMethodCodec::GetInstance());
  platform_->SetMethodCallHandler([window](const auto& call, auto result) {
    const auto& method = call.method_name();
    if (method == "fileAccessStatus" || method == "requestFileAccess") {
      result->Success(FileAccess());
    } else if (method == "openFile") {
      const auto* path = call.arguments()
          ? std::get_if<std::string>(call.arguments()) : nullptr;
      if (!path || path->empty() || path->find('\0') != std::string::npos) {
        result->Error("invalid_path", "无效的预览文件路径");
      } else if (!OpenFile(window, Wide(*path))) {
        result->Error("open_failed", "无法使用默认应用打开文件，请检查文件权限或默认应用设置");
      } else {
        result->Success();
      }
    } else if (method == "archiveFileAssociationStatus" ||
               method == "setDefaultArchiveFormats" ||
               method == "restoreDefaultArchiveFormats") {
      // Windows default handlers are chosen by the user in system settings.
      result->Success(Value(Map{{Value("available"), Value(false)}}));
    } else if (method == "themeMode" || method == "singleEntryExtractionMode" ||
               method == "smartExtractionEnabled" || method == "archiveColumnPreferences") {
      const auto stored = ReadPreference(method);
      if (stored) result->Success(*stored);
      else result->Success();
    } else {
      std::string key;
      if (method == "setThemeMode") key = "themeMode";
      else if (method == "setSingleEntryExtractionMode") key = "singleEntryExtractionMode";
      else if (method == "setSmartExtractionEnabled") key = "smartExtractionEnabled";
      else if (method == "setArchiveColumnPreferences") key = "archiveColumnPreferences";
      if (key.empty()) {
        result->NotImplemented();
      } else if (!call.arguments()) {
        result->Error("invalid_preference", "缺少设置值");
      } else if (!WritePreference(key, *call.arguments())) {
        result->Error("preference_failed", "无法保存设置");
      } else {
        result->Success();
      }
    }
  });

  List pending;
  for (const auto& argument : arguments) {
    const auto path = Wide(argument);
    const DWORD attributes = GetFileAttributesW(path.c_str());
    if (attributes != INVALID_FILE_ATTRIBUTES &&
        (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0) {
      pending.emplace_back(argument);
    }
  }
  archive_open_ = std::make_unique<flutter::MethodChannel<Value>>(
      messenger, "dev.jucier/archive_open", &flutter::StandardMethodCodec::GetInstance());
  archive_open_->SetMethodCallHandler(
      [window, pending = std::move(pending)](const auto& call, auto result) mutable {
    if (call.method_name() == "takePendingOpenFiles") {
      result->Success(Value(pending));
      pending.clear();
    } else if (call.method_name() == "quitApplication") {
      result->Success();
      PostMessageW(window, WM_CLOSE, 0, 0);
    } else {
      result->NotImplemented();
    }
  });
}

PlatformServices::~PlatformServices() {
  platform_->SetMethodCallHandler(nullptr);
  archive_open_->SetMethodCallHandler(nullptr);
}
