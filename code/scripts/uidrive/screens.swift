import AppKit
print("main:", NSScreen.main.map { "\($0.visibleFrame)" } ?? "nil")
for s in NSScreen.screens { print("screen:", s.frame, "visible:", s.visibleFrame) }
