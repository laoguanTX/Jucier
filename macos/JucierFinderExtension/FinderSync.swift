import Cocoa
import FinderSync

final class FinderSync: FIFinderSync {
  private enum Action: String {
    case extractHere
    case extractTo
    case compressZip
    case compress
  }

  private let archiveExtensions: Set<String> = [
    "zip", "7z", "rar", "tar", "gz", "tgz", "bz2", "tbz2", "tbz",
    "xz", "txz", "zst", "tzst", "zipx", "jar", "apk", "xpi", "epub",
    "cab", "iso", "dmg", "wim", "swm", "esd", "lzh", "lha", "arj",
    "cpio", "deb", "rpm", "xar", "xip", "001",
  ]

  override init() {
    super.init()
    // Monitoring the filesystem root makes the contextual menu available in
    // every local Finder folder. Finder still supplies only the user's current
    // selection to the extension.
    FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
  }

  override func menu(for menuKind: FIMenuKind) -> NSMenu? {
    guard menuKind == .contextualMenuForItems else { return nil }
    let selection = selectedURLs()
    guard !selection.isEmpty else { return nil }

    let archives = selection.filter(isArchive)
    let submenu = NSMenu(title: "Jucier")
    submenu.addItem(menuItem("解压", action: #selector(extractHere(_:)),
      enabled: archives.count == selection.count))
    submenu.addItem(menuItem("解压到", action: #selector(extractTo(_:)),
      enabled: selection.count == 1 && archives.count == 1))
    submenu.addItem(.separator())
    submenu.addItem(menuItem("压缩成 ZIP", action: #selector(compressZip(_:))))
    submenu.addItem(menuItem("压缩", action: #selector(compress(_:))))

    let root = NSMenu(title: "")
    let item = NSMenuItem(title: "Jucier", action: nil, keyEquivalent: "")
    item.submenu = submenu
    root.addItem(item)
    return root
  }

  @objc private func extractHere(_ sender: Any?) {
    dispatch(.extractHere)
  }

  @objc private func extractTo(_ sender: Any?) {
    dispatch(.extractTo)
  }

  @objc private func compressZip(_ sender: Any?) {
    dispatch(.compressZip)
  }

  @objc private func compress(_ sender: Any?) {
    dispatch(.compress)
  }

  private func menuItem(
    _ title: String,
    action: Selector,
    enabled: Bool = true
  ) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    item.isEnabled = enabled
    return item
  }

  private func selectedURLs() -> [URL] {
    FIFinderSyncController.default().selectedItemURLs() ?? []
  }

  private func isArchive(_ url: URL) -> Bool {
    archiveExtensions.contains(url.pathExtension.lowercased())
  }

  private func dispatch(_ action: Action) {
    let urls = selectedURLs()
    guard !urls.isEmpty, let appURL = containingApplicationURL() else { return }

    var components = URLComponents()
    components.scheme = "jucier"
    components.host = "finder-action"
    components.queryItems = [URLQueryItem(name: "action", value: action.rawValue)]
      + urls.map { URLQueryItem(name: "path", value: $0.path) }
    guard let actionURL = components.url else { return }

    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    NSWorkspace.shared.open(
      [actionURL],
      withApplicationAt: appURL,
      configuration: configuration
    )
  }

  private func containingApplicationURL() -> URL? {
    let url = Bundle.main.bundleURL
      .deletingLastPathComponent() // PlugIns
      .deletingLastPathComponent() // Contents
      .deletingLastPathComponent() // Jucier.app
    return url.pathExtension == "app" ? url : nil
  }
}
