import AppKit

// Plain AppKit entry instead of a SwiftUI App: the popover is the whole
// UI, and even an empty SwiftUI Settings scene would open as a stray
// "Promptu Settings" window on ⌘, outside the popover.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
