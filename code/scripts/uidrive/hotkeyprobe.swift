import Carbon.HIToolbox
import Foundation

// Asks the system for the same combination the app claims. If the app is
// holding it, this fails; if the app released it, this succeeds. A direct read
// of who owns the key, rather than trusting the code that was supposed to
// release it. Registers and immediately unregisters, so nothing is left held.
let code = UInt32(CommandLine.arguments[1])!
let mods = UInt32(CommandLine.arguments[2])!

var ref: EventHotKeyRef?
let id = EventHotKeyID(signature: 0x50524F42, id: 99) // 'PROB'
let status = RegisterEventHotKey(code, mods, id, GetEventDispatcherTarget(), 0, &ref)

switch status {
case noErr:
    if let ref { UnregisterEventHotKey(ref) }
    print("FREE — nobody holds keycode \(code) mods \(mods)")
case OSStatus(eventHotKeyExistsErr):
    print("HELD — someone already owns keycode \(code) mods \(mods)")
default:
    print("status \(status) for keycode \(code) mods \(mods)")
}
