import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private let platformChannelName = "dev.jucier/platform"
  private let bookmarkKey = "fileAccessBookmark"
  private let bookmarkPathKey = "fileAccessBookmarkPath"
  private let permissionRequestedKey = "fileAccessPermissionRequested"
  private var scopedURL: URL?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.minSize = NSSize(width: 720, height: 520)
    self.setContentSize(NSSize(width: 860, height: 620))
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)
    configurePlatformChannel(flutterViewController)
    restoreFileAccess()

    super.awakeFromNib()
  }

  private func configurePlatformChannel(_ controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: platformChannelName,
      binaryMessenger: controller.engine.binaryMessenger)

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "fileAccessStatus":
        result(self.fileAccessStatus())
      case "requestFileAccess":
        self.requestFileAccess(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func fileAccessStatus() -> [String: Any] {
    var status: [String: Any] = [
      "requested": UserDefaults.standard.bool(forKey: permissionRequestedKey),
      "granted": scopedURL != nil,
    ]
    if let path = scopedURL?.path
      ?? UserDefaults.standard.string(forKey: bookmarkPathKey) {
      status["directory"] = path
    }
    return status
  }

  private func requestFileAccess(result: @escaping FlutterResult) {
    UserDefaults.standard.set(true, forKey: permissionRequestedKey)

    let panel = NSOpenPanel()
    panel.title = "允许文件与文件夹访问"
    panel.message = "请选择 Jucier 可以打开、创建和解压文件的文件夹。建议选择你的个人文件夹。"
    panel.prompt = "授权"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true

    panel.beginSheetModal(for: self) { [weak self] response in
      guard let self else { return }
      guard response == .OK, let url = panel.url else {
        result(self.fileAccessStatus())
        return
      }

      do {
        try self.saveAndActivateBookmark(for: url)
        result(self.fileAccessStatus())
      } catch {
        result(FlutterError(
          code: "bookmark_failed",
          message: "无法保存文件夹访问权限",
          details: error.localizedDescription))
      }
    }
  }

  private func saveAndActivateBookmark(for url: URL) throws {
    let data = try url.bookmarkData(
      options: .withSecurityScope,
      includingResourceValuesForKeys: nil,
      relativeTo: nil)
    UserDefaults.standard.set(data, forKey: bookmarkKey)
    UserDefaults.standard.set(url.path, forKey: bookmarkPathKey)
    try activateBookmark(data)
  }

  private func restoreFileAccess() {
    guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
    do {
      try activateBookmark(data)
    } catch {
      UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }
  }

  private func activateBookmark(_ data: Data) throws {
    var isStale = false
    let url = try URL(
      resolvingBookmarkData: data,
      options: .withSecurityScope,
      relativeTo: nil,
      bookmarkDataIsStale: &isStale)

    scopedURL?.stopAccessingSecurityScopedResource()
    scopedURL = url.startAccessingSecurityScopedResource() ? url : nil

    if isStale {
      let refreshed = try url.bookmarkData(
        options: .withSecurityScope,
        includingResourceValuesForKeys: nil,
        relativeTo: nil)
      UserDefaults.standard.set(refreshed, forKey: bookmarkKey)
    }
  }
}
