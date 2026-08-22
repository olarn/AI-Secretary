import Carbon.HIToolbox
import Foundation

let code = UInt32(CommandLine.arguments[1])!
let mods = UInt32(CommandLine.arguments[2])!

var ref: EventHotKeyRef?
let fourCharacterCodePROB: OSType = 0x50524F42
let id = EventHotKeyID(signature: fourCharacterCodePROB, id: 99)
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
