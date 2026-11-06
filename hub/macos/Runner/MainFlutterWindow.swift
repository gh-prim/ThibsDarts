import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Simule l'écran 7 pouces du Pi 4 : 1024x600, taille fixe.
    let size = NSSize(width: 1024, height: 600)
    self.setContentSize(size)
    self.contentMinSize = size
    self.contentMaxSize = size
    self.title = "Dart OS (simulateur écran Pi 4)"
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
