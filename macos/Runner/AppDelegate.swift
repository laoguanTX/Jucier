import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var archiveOpenChannel: FlutterMethodChannel?
  private var pendingOpenPaths: [String] = []

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
    let paths = urls.filter(\.isFileURL).map(\.path)
    for path in paths where !pendingOpenPaths.contains(path) {
      pendingOpenPaths.append(path)
    }
    if !paths.isEmpty {
      archiveOpenChannel?.invokeMethod("archiveFilesAvailable", arguments: nil)
    }
  }

  func attachArchiveOpenChannel(_ channel: FlutterMethodChannel) {
    archiveOpenChannel = channel
  }

  func takePendingOpenPaths() -> [String] {
    let paths = pendingOpenPaths
    pendingOpenPaths.removeAll()
    return paths
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
