import AppKit

// zWGestures is a menu-bar-only agent app (LSUIElement=true), so it is started
// explicitly here instead of through a main nib / storyboard.
let application = NSApplication.shared
let delegate = AppDelegate()

application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
