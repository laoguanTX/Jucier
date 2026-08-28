import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var archiveOpenChannel: FlutterMethodChannel?
  private var finderActionChannel: FlutterMethodChannel?
  private var pendingOpenPaths: [String] = []
  private var pendingFinderActions: [[String: Any]] = []

  @IBAction func showSettings(_ sender: Any?) {
    guard
      let window = mainFlutterWindow,
      let controller = window.contentViewController as? FlutterViewController
    else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "dev.jucier/platform",
      binaryMessenger: controller.engine.binaryMessenger)
    channel.invokeMethod("openSettings", arguments: nil)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func application(_ application: NSApplication, open urls: [URL]) {
    var receivedAction = false
    for url in urls where url.scheme?.lowercased() == "jucier"
      && url.host == "finder-action" {
      guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
      else { continue }
      let items = components.queryItems ?? []
      guard let action = items.first(where: { $0.name == "action" })?.value,
        ["extractHere", "extractTo", "compressZip", "compress"].contains(action)
      else { continue }
      let paths = items
        .filter { $0.name == "path" }
        .compactMap(\.value)
        .filter { !$0.isEmpty }
      guard !paths.isEmpty else { continue }
      pendingFinderActions.append(["action": action, "paths": paths])
      receivedAction = true
    }

    let paths = urls.filter(\.isFileURL).map(\.path)
    for path in paths where !pendingOpenPaths.contains(path) {
      pendingOpenPaths.append(path)
    }
    if !paths.isEmpty {
      archiveOpenChannel?.invokeMethod("archiveFilesAvailable", arguments: nil)
    }
    if receivedAction {
      finderActionChannel?.invokeMethod("finderActionsAvailable", arguments: nil)
    }
  }

  func attachArchiveOpenChannel(_ channel: FlutterMethodChannel) {
    archiveOpenChannel = channel
  }

  func attachFinderActionChannel(_ channel: FlutterMethodChannel) {
    finderActionChannel = channel
  }

  func takePendingOpenPaths() -> [String] {
    let paths = pendingOpenPaths
    pendingOpenPaths.removeAll()
    return paths
  }

  func takePendingFinderActions() -> [[String: Any]] {
    let actions = pendingFinderActions
    pendingFinderActions.removeAll()
    return actions
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
