import Carbon
import AppKit

final class GlobalHotkeyManager {
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var registeredShortcuts: [UInt32: ShortcutConfiguration] = [:]
    private var lastInvocation: (UUID, Date)?
    var onShortcut: ((ShortcutConfiguration) -> Void)?
    var onWorkspace: ((Int) -> Void)?

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            if (1001...1009).contains(id.id) {
                DispatchQueue.main.async { manager.onWorkspace?(Int(id.id - 1000)) }
                return noErr
            }
            guard let shortcut = manager.registeredShortcuts[id.id] else { return noErr }
            DispatchQueue.main.async { manager.invoke(shortcut) }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        if status != noErr { NSLog("Waycode could not install the global hotkey handler (OSStatus %d)", status) }
    }

    deinit { clear(); if let handler { RemoveEventHandler(handler) } }

    func register(_ shortcuts: [ShortcutConfiguration]) {
        clear()
        var combinations = Set<String>()
        // Workspace navigation is intentionally fixed and global, matching the
        // desktop labels in the bar. Carbon hotkeys need no Accessibility or
        // Input Monitoring permission and continue working behind other apps.
        for (number, code) in [18, 19, 20, 21, 23, 22, 26, 28, 25].enumerated() {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(1001 + number))
            if RegisterEventHotKey(UInt32(code), UInt32(optionKey), id, GetApplicationEventTarget(), 0, &ref) == noErr, let ref { refs.append(ref) }
            combinations.insert("\(code)-\(UInt32(optionKey))")
        }
        for (index, shortcut) in shortcuts.enumerated() {
            guard shortcut.option || shortcut.command || shortcut.control || shortcut.shift,
                  let code = Self.keyCodes[shortcut.key.lowercased()] else { continue }
            var modifiers: UInt32 = 0
            if shortcut.option { modifiers |= UInt32(optionKey) }
            if shortcut.command { modifiers |= UInt32(cmdKey) }
            if shortcut.control { modifiers |= UInt32(controlKey) }
            if shortcut.shift { modifiers |= UInt32(shiftKey) }
            let combination = "\(code)-\(modifiers)"
            guard combinations.insert(combination).inserted else { continue }
            var ref: EventHotKeyRef?
            let hotkeyID = UInt32(index + 1)
            let id = EventHotKeyID(signature: Self.signature, id: hotkeyID)
            let status = RegisterEventHotKey(UInt32(code), modifiers, id, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { refs.append(ref); registeredShortcuts[hotkeyID] = shortcut }
            else { NSLog("Waycode could not register global shortcut %@ (OSStatus %d)", shortcut.display, status) }
        }
    }

    private func invoke(_ shortcut: ShortcutConfiguration) {
        if let lastInvocation, lastInvocation.0 == shortcut.id, Date().timeIntervalSince(lastInvocation.1) < 0.18 { return }
        lastInvocation = (shortcut.id, Date()); onShortcut?(shortcut)
    }

    private func clear() { refs.forEach { UnregisterEventHotKey($0) }; refs.removeAll(); registeredShortcuts.removeAll() }
    private static let signature: OSType = 0x57415943
    static let keyCodes: [String: Int] = [
        "a":0,"s":1,"d":2,"f":3,"h":4,"g":5,"z":6,"x":7,"c":8,"v":9,"b":11,"q":12,"w":13,"e":14,"r":15,"y":16,"t":17,
        "1":18,"2":19,"3":20,"4":21,"6":22,"5":23,"=":24,"9":25,"7":26,"-":27,"8":28,"0":29,"o":31,"u":32,"i":34,"p":35,"l":37,"j":38,"k":40,"n":45,"m":46
    ]
}

extension Collection {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}
