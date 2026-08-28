import Cocoa
import FlutterMacOS
import FinderSync
import UniformTypeIdentifiers

private class ArchiveFilePromiseDragSource: NSObject,
  NSFilePromiseProviderDelegate, NSDraggingSource {
  private let channel: FlutterMethodChannel
  private var itemByProvider: [ObjectIdentifier: [String: Any]] = [:]
  private var expectedPromiseCount = 0
  private var completedPromiseCount = 0
  private var sessionHasEnded = false
  private var didFinish = false
  var onEnded: (() -> Void)?

  init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  func register(_ provider: NSFilePromiseProvider, item: [String: Any]) {
    itemByProvider[ObjectIdentifier(provider)] = item
    expectedPromiseCount += 1
  }

  func filePromiseProvider(
    _ filePromiseProvider: NSFilePromiseProvider,
    fileNameForType fileType: String
  ) -> String {
    itemByProvider[ObjectIdentifier(filePromiseProvider)]?["name"] as? String
      ?? "Archive Item"
  }

  func filePromiseProvider(
    _ filePromiseProvider: NSFilePromiseProvider,
    writePromiseTo url: URL,
    completionHandler: @escaping (Error?) -> Void
  ) {
    guard let item = itemByProvider[ObjectIdentifier(filePromiseProvider)],
      let id = item["id"] as? String else {
      completionHandler(NSError(
        domain: "dev.jucier.file-drag",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "拖拽项目已失效"]))
      return
    }

    let accessing = url.startAccessingSecurityScopedResource()
    channel.invokeMethod(
      "materialize",
      arguments: ["id": id, "outputPath": url.path]
    ) { result in
      if accessing {
        url.stopAccessingSecurityScopedResource()
      }
      if let flutterError = result as? FlutterError {
        completionHandler(NSError(
          domain: "dev.jucier.file-drag",
          code: 2,
          userInfo: [NSLocalizedDescriptionKey: flutterError.message ?? "部分解压失败"]))
      } else {
        completionHandler(nil)
      }
      self.completedPromiseCount += 1
      self.finishIfPossible()
    }
  }

  func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
    OperationQueue.main
  }

  func draggingSession(
    _ session: NSDraggingSession,
    sourceOperationMaskFor context: NSDraggingContext
  ) -> NSDragOperation {
    context == .withinApplication ? [] : .copy
  }

  func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
    true
  }

  func draggingSession(
    _ session: NSDraggingSession,
    endedAt screenPoint: NSPoint,
    operation: NSDragOperation
  ) {
    sessionHasEnded = true
    if operation.isEmpty {
      finish()
    } else {
      finishIfPossible()
      DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
        self?.finish()
      }
    }
  }

  private func finishIfPossible() {
    if sessionHasEnded && completedPromiseCount >= expectedPromiseCount {
      finish()
    }
  }

  private func finish() {
    guard !didFinish else { return }
    didFinish = true
    onEnded?()
  }
}

class MainFlutterWindow: NSWindow {
  private let platformChannelName = "dev.jucier/platform"
  private let bookmarkKey = "fileAccessBookmark"
  private let bookmarkPathKey = "fileAccessBookmarkPath"
  private let permissionRequestedKey = "fileAccessPermissionRequested"
  private let themeModeKey = "themeMode"
  private let singleEntryExtractionModeKey = "singleEntryExtractionMode"
  private let compressionArchiveColumnsKey = "compressionArchiveColumns"
  private let extractionArchiveColumnsKey = "extractionArchiveColumns"
  private let finderContextMenuInstalledKey = "finderContextMenuInstalled"
  private var completedInitialArchiveOpenCheck = false
  private var scopedURL: URL?
  private var archiveDragSource: ArchiveFilePromiseDragSource?
  private var archiveDragResult: FlutterResult?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.minSize = NSSize(width: 720, height: 520)
    self.setContentSize(NSSize(width: 860, height: 620))
    self.center()

    // Hide the system-drawn title text while keeping the native traffic-light
    // buttons, which float over the top-left corner of the Flutter content.
    self.title = "Jucier"
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)
    applyThemeMode(storedThemeMode())

    RegisterGeneratedPlugins(registry: flutterViewController)
    configurePlatformChannel(flutterViewController)
    configureArchiveOpenChannel(flutterViewController)
    configureFinderActionChannel(flutterViewController)
    configureFileDragChannel(flutterViewController)
    restoreFileAccess()

    super.awakeFromNib()
  }

  private func configureFileDragChannel(_ controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "dev.jucier/file_drag",
      binaryMessenger: controller.engine.binaryMessenger)

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      guard call.method == "beginDrag" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.beginArchiveEntryDrag(call.arguments, channel: channel, result: result)
    }
  }

  private func configureArchiveOpenChannel(_ controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "dev.jucier/archive_open",
      binaryMessenger: controller.engine.binaryMessenger)
    (NSApp.delegate as? AppDelegate)?.attachArchiveOpenChannel(channel)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result([])
        return
      }
      switch call.method {
      case "takePendingOpenFiles":
        if self.completedInitialArchiveOpenCheck {
          result((NSApp.delegate as? AppDelegate)?.takePendingOpenPaths() ?? [])
        } else {
          self.completedInitialArchiveOpenCheck = true
          // On a cold document launch, Launch Services may deliver openURLs
          // just after Flutter's first frame. Keep the initial launch gate in
          // place until that native event has had a chance to enter the queue.
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            result((NSApp.delegate as? AppDelegate)?.takePendingOpenPaths() ?? [])
          }
        }
      case "quitApplication":
        result(nil)
        DispatchQueue.main.async {
          NSApp.terminate(nil)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func configureFinderActionChannel(_ controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "dev.jucier/finder_action",
      binaryMessenger: controller.engine.binaryMessenger)
    (NSApp.delegate as? AppDelegate)?.attachFinderActionChannel(channel)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "takePendingFinderActions":
        result((NSApp.delegate as? AppDelegate)?.takePendingFinderActions() ?? [])
      case "finderContextMenuAvailable":
        result(
          self.finderExtensionURL() != nil
            && UserDefaults.standard.bool(forKey: self.finderContextMenuInstalledKey))
      case "repairFinderContextMenu":
        self.repairFinderContextMenu(result: result)
      case "uninstallFinderContextMenu":
        self.uninstallFinderContextMenu(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func beginArchiveEntryDrag(
    _ value: Any?,
    channel: FlutterMethodChannel,
    result: @escaping FlutterResult
  ) {
    guard archiveDragSource == nil else {
      result(FlutterError(
        code: "drag_in_progress",
        message: "已有文件拖拽正在进行",
        details: nil))
      return
    }
    guard let items = value as? [[String: Any]], !items.isEmpty,
      let event = NSApp.currentEvent,
      let contentView else {
      result(FlutterError(
        code: "invalid_drag",
        message: "无法开始文件拖拽，请重新拖动文件",
        details: value))
      return
    }

    let source = ArchiveFilePromiseDragSource(channel: channel)
    let point = contentView.convert(event.locationInWindow, from: nil)
    var draggingItems: [NSDraggingItem] = []
    for item in items {
      guard let name = item["name"] as? String,
        let id = item["id"] as? String else { continue }
      let isDirectory = item["isDirectory"] as? Bool ?? false
      let contentType: UTType = isDirectory ? .folder : .data
      let fileType = contentType.identifier
      let provider = NSFilePromiseProvider(fileType: fileType, delegate: source)
      source.register(provider, item: [
        "id": id,
        "name": name,
        "isDirectory": isDirectory,
      ])
      let draggingItem = NSDraggingItem(pasteboardWriter: provider)
      let image = NSWorkspace.shared.icon(for: contentType)
      draggingItem.setDraggingFrame(
        NSRect(x: point.x - 24, y: point.y - 24, width: 48, height: 48),
        contents: image)
      draggingItems.append(draggingItem)
    }
    guard !draggingItems.isEmpty else {
      result(FlutterError(
        code: "invalid_drag_items",
        message: "没有可拖出的文件",
        details: value))
      return
    }

    archiveDragSource = source
    archiveDragResult = result
    source.onEnded = { [weak self] in
      self?.archiveDragResult?(nil)
      self?.archiveDragResult = nil
      self?.archiveDragSource = nil
    }
    contentView.beginDraggingSession(
      with: draggingItems,
      event: event,
      source: source)
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
      case "themeMode":
        result(self.storedThemeMode())
      case "setThemeMode":
        self.setThemeMode(call.arguments, result: result)
      case "openFile":
        self.openFile(call.arguments, result: result)
      case "singleEntryExtractionMode":
        result(self.storedSingleEntryExtractionMode())
      case "setSingleEntryExtractionMode":
        self.setSingleEntryExtractionMode(call.arguments, result: result)
      case "archiveColumnPreferences":
        result(self.storedArchiveColumnPreferences())
      case "setArchiveColumnPreferences":
        self.setArchiveColumnPreferences(call.arguments, result: result)
      case "archiveFileAssociationStatus":
        result(self.archiveFileAssociationStatus(call.arguments))
      case "setDefaultArchiveFormats":
        self.setDefaultArchiveFormats(call.arguments, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func archiveExtensions(_ value: Any?) -> [String] {
    guard let values = value as? [String] else { return [] }
    var extensions: [String] = []
    for value in values {
      let normalized = value.lowercased()
        .trimmingCharacters(in: CharacterSet(charactersIn: "."))
      if !normalized.isEmpty && !extensions.contains(normalized) {
        extensions.append(normalized)
      }
    }
    return extensions
  }

  private func finderExtensionURL() -> URL? {
    let url = Bundle.main.bundleURL
      .appendingPathComponent("Contents", isDirectory: true)
      .appendingPathComponent("PlugIns", isDirectory: true)
      .appendingPathComponent("JucierFinderExtension.appex")
    guard FileManager.default.fileExists(atPath: url.path) else {
      return nil
    }
    return url
  }

  private func repairFinderContextMenu(result: @escaping FlutterResult) {
    guard let extensionURL = finderExtensionURL() else {
      result(FlutterError(
        code: "finder_extension_missing",
        message: "应用包中缺少 Jucier Finder 扩展，请重新安装 Jucier",
        details: nil))
      return
    }

    var didFinish = false
    func finish() {
      DispatchQueue.main.async {
        guard !didFinish else { return }
        didFinish = true
        UserDefaults.standard.set(true, forKey: self.finderContextMenuInstalledKey)
        FIFinderSyncController.showExtensionManagementInterface()
        result(nil)
      }
    }

    // The sandboxed pluginkit process can take a while to contact macOS's
    // extension registry. Keep the UI responsive and show system management
    // even if registration continues in the background.
    DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: finish)

    runPluginKit(["-a", extensionURL.path]) {
      self.runPluginKit([
        "-e", "ignore", "-i", "dev.jucier.app.FinderExtension",
      ]) {
        self.runPluginKit([
          "-e", "use", "-i", "dev.jucier.app.FinderExtension",
        ]) {
          finish()
        }
      }
    }
  }

  private func uninstallFinderContextMenu(result: @escaping FlutterResult) {
    var didFinish = false
    func finish() {
      DispatchQueue.main.async {
        guard !didFinish else { return }
        didFinish = true
        UserDefaults.standard.set(false, forKey: self.finderContextMenuInstalledKey)
        result(nil)
      }
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: finish)
    runPluginKit([
      "-e", "ignore", "-i", "dev.jucier.app.FinderExtension",
    ]) {
      guard let extensionURL = self.finderExtensionURL() else {
        finish()
        return
      }
      self.runPluginKit(["-r", extensionURL.path]) {
        finish()
      }
    }
  }

  private func runPluginKit(
    _ arguments: [String],
    completion: @escaping () -> Void
  ) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
    task.arguments = arguments
    task.terminationHandler = { _ in completion() }
    do {
      try task.run()
    } catch {
      DispatchQueue.main.async {
        completion()
      }
    }
  }

  private func archiveFileAssociationStatus(_ value: Any?) -> [String: Any] {
    let applicationURL = Bundle.main.bundleURL.standardizedFileURL
    let defaults = archiveExtensions(value).filter { fileExtension in
      guard let contentType = UTType(filenameExtension: fileExtension),
        let handlerURL = NSWorkspace.shared.urlForApplication(toOpen: contentType)
      else {
        return false
      }
      return handlerURL.standardizedFileURL == applicationURL
    }
    return ["available": true, "defaults": defaults]
  }

  private func setDefaultArchiveFormats(_ value: Any?, result: @escaping FlutterResult) {
    let extensions = archiveExtensions(value)
    guard !extensions.isEmpty else {
      result(FlutterError(
        code: "empty_archive_formats",
        message: "请至少选择一种压缩包格式",
        details: nil))
      return
    }

    let applicationURL = Bundle.main.bundleURL
    var index = 0
    var failures: [String] = []

    func bindNext() {
      guard index < extensions.count else {
        DispatchQueue.main.async {
          if failures.isEmpty {
            result(self.archiveFileAssociationStatus(extensions))
          } else {
            result(FlutterError(
              code: "archive_association_failed",
              message: "无法绑定以下格式：\(failures.joined(separator: ", "))",
              details: failures))
          }
        }
        return
      }

      let fileExtension = extensions[index]
      index += 1
      guard let contentType = UTType(filenameExtension: fileExtension) else {
        failures.append(fileExtension)
        bindNext()
        return
      }
      NSWorkspace.shared.setDefaultApplication(
        at: applicationURL,
        toOpen: contentType
      ) { error in
        if error != nil {
          failures.append(fileExtension)
        }
        bindNext()
      }
    }

    bindNext()
  }

  private func openFile(_ value: Any?, result: FlutterResult) {
    guard let path = value as? String, !path.isEmpty else {
      result(FlutterError(
        code: "invalid_file_path",
        message: "预览文件路径无效",
        details: value))
      return
    }

    if NSWorkspace.shared.open(URL(fileURLWithPath: path)) {
      result(nil)
    } else {
      result(FlutterError(
        code: "open_file_failed",
        message: "没有可用于打开该文件的应用",
        details: path))
    }
  }

  private func storedThemeMode() -> String {
    UserDefaults.standard.string(forKey: themeModeKey) ?? "system"
  }

  private func storedSingleEntryExtractionMode() -> String {
    UserDefaults.standard.string(forKey: singleEntryExtractionModeKey)
      ?? "preserveArchiveStructure"
  }

  private func setSingleEntryExtractionMode(_ value: Any?, result: FlutterResult) {
    guard let mode = value as? String,
      ["preserveArchiveStructure", "selectedOnly"].contains(mode) else {
      result(FlutterError(
        code: "invalid_single_entry_extraction_mode",
        message: "不支持的单文件解压模式",
        details: value))
      return
    }

    UserDefaults.standard.set(mode, forKey: singleEntryExtractionModeKey)
    result(nil)
  }

  private func storedArchiveColumnPreferences() -> [String: [String]] {
    return [
      "compression": normalizedArchiveColumns(
        UserDefaults.standard.stringArray(forKey: compressionArchiveColumnsKey)
          ?? ["name", "size", "modified"]),
      "extraction": normalizedArchiveColumns(
        UserDefaults.standard.stringArray(forKey: extractionArchiveColumnsKey)
          ?? ["name", "size", "packedSize", "modified"]),
    ]
  }

  private func setArchiveColumnPreferences(_ value: Any?, result: FlutterResult) {
    guard let preferences = value as? [String: Any],
      let compression = preferences["compression"] as? [String],
      let extraction = preferences["extraction"] as? [String] else {
      result(FlutterError(
        code: "invalid_archive_column_preferences",
        message: "文件树菜单栏设置无效",
        details: value))
      return
    }

    UserDefaults.standard.set(
      normalizedArchiveColumns(compression),
      forKey: compressionArchiveColumnsKey)
    UserDefaults.standard.set(
      normalizedArchiveColumns(extraction),
      forKey: extractionArchiveColumnsKey)
    result(nil)
  }

  private func normalizedArchiveColumns(_ columns: [String]) -> [String] {
    let allowed = Set([
      "name", "type", "path", "size", "totalSize", "itemCount",
      "packedSize", "compressionRatio", "modified", "method", "encrypted",
      "crc", "sourcePath", "attributes",
    ])
    var normalized: [String] = []
    for column in columns where allowed.contains(column) && !normalized.contains(column) {
      normalized.append(column)
    }
    if !normalized.contains("name") {
      normalized.insert("name", at: 0)
    }
    return normalized
  }

  private func setThemeMode(_ value: Any?, result: FlutterResult) {
    guard let mode = value as? String,
      ["system", "light", "dark"].contains(mode) else {
      result(FlutterError(
        code: "invalid_theme_mode",
        message: "不支持的外观模式",
        details: value))
      return
    }

    UserDefaults.standard.set(mode, forKey: themeModeKey)
    applyThemeMode(mode)
    result(nil)
  }

  private func applyThemeMode(_ mode: String) {
    switch mode {
    case "light":
      appearance = NSAppearance(named: .aqua)
    case "dark":
      appearance = NSAppearance(named: .darkAqua)
    default:
      appearance = nil
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
