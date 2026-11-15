import Cocoa
import FlutterMacOS
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerBackupRestorePicker(with: flutterViewController)

    super.awakeFromNib()
  }

  private func registerBackupRestorePicker(with flutterViewController: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "com.ledgerpro/backup_restore",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "pickBackupFile" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let self = self else {
        result(nil)
        return
      }

      let panel = NSOpenPanel()
      panel.title = "Select Backup File"
      if #available(macOS 11.0, *) {
        panel.allowedContentTypes = [.json]
      } else {
        panel.allowedFileTypes = ["json"]
      }
      panel.allowsMultipleSelection = false
      panel.canChooseDirectories = false
      panel.canChooseFiles = true

      panel.beginSheetModal(for: self) { response in
        guard response == .OK, let url = panel.url else {
          result(nil)
          return
        }
        result(url.path)
      }
    }
  }
}
