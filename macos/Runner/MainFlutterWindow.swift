import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var historyFolders: HistoryFolderAccess?
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    historyFolders = HistoryFolderAccess(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}

// Security-scoped bookmarks preserve user-selected folder access across launches.
private class HistoryFolderAccess {
  private let key = "previewimages.historyFolderBookmarks"
  private var activeURLs: [String: URL] = [:]
  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "previewimages/history_folders", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      var bookmarks = UserDefaults.standard.dictionary(forKey: self.key) as? [String: Data] ?? [:]
      do {
        switch call.method {
        case "rememberFolder":
          guard let path = call.arguments as? String else {
            result(FlutterError(code: "invalid_path", message: "Missing folder path", details: nil))
            return
          }
          let url = URL(fileURLWithPath: path, isDirectory: true)
          bookmarks[path] = try url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil, relativeTo: nil)
          UserDefaults.standard.set(bookmarks, forKey: self.key)
          result(nil)
        case "restoreFolderAccess":
          guard let path = call.arguments as? String, let data = bookmarks[path] else {
            result(nil)
            return
          }
          if self.activeURLs[path] != nil {
            result(nil)
            return
          }
          var stale = false
          let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope],
                            relativeTo: nil, bookmarkDataIsStale: &stale)
          guard url.startAccessingSecurityScopedResource() else {
            result(FlutterError(code: "folder_access", message: "Folder access denied", details: nil))
            return
          }
          self.activeURLs[path] = url
          if stale {
            bookmarks[path] = try url.bookmarkData(
              options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
              includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmarks, forKey: self.key)
          }
          result(nil)
        case "retainFolders":
          let paths = Set(call.arguments as? [String] ?? [])
          bookmarks = bookmarks.filter { paths.contains($0.key) }
          UserDefaults.standard.set(bookmarks, forKey: self.key)
          for path in Array(self.activeURLs.keys) where !paths.contains(path) {
            self.activeURLs.removeValue(forKey: path)?.stopAccessingSecurityScopedResource()
          }
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      } catch {
        result(FlutterError(code: "folder_access", message: error.localizedDescription, details: nil))
      }
    }
  }

  deinit {
    for url in activeURLs.values {
      url.stopAccessingSecurityScopedResource()
    }
  }
}
