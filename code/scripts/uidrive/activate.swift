import AppKit
let pid = pid_t(CommandLine.arguments[1])!
guard let app = NSRunningApplication(processIdentifier: pid) else { print("no such pid"); exit(1) }
app.activate(options: [.activateAllWindows])
usleep(600_000)
print("frontmost now:", NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")
