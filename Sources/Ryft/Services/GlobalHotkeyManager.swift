import Carbon
import AppKit

final class GlobalHotkeyManager {
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var registeredShortcuts: [UInt32: ShortcutConfiguration] = [:]
    private var systemShortcuts: [UInt32: ShortcutConfiguration] = [:]
    private var lastInvocation: (String, Date)?
    private var lastWorkspaceInvocation: (Int, Date)?
    private var polledShortcuts: [ShortcutConfiguration] = []
    private var keysDown = Set<Int>()
    private var pollingTimer: DispatchSourceTimer?
    private var globalMonitor: Any?
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var lastEventTapAttempt = Date.distantPast
    var onShortcut: ((ShortcutConfiguration) -> Void)?
    var onWorkspace: ((Int) -> Void)?

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            if (1001...1009).contains(id.id) {
                DispatchQueue.main.async { manager.invokeWorkspace(Int(id.id - 1000)) }
                return noErr
            }
            guard let shortcut = manager.systemShortcuts[id.id] ?? manager.registeredShortcuts[id.id] else { return noErr }
            DispatchQueue.main.async { manager.invoke(shortcut) }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        if status != noErr { NSLog("Ryft could not install the global hotkey handler (OSStatus %d)", status) }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .milliseconds(100), repeating: .milliseconds(30), leeway: .milliseconds(5))
        timer.setEventHandler { [weak self] in self?.pollKeyboard() }
        timer.resume(); pollingTimer = timer
        // Passive fallback for systems where another utility interferes with
        // Carbon delivery. This does not request or open a permission prompt.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in self?.handleMonitoredKey(event) }
        installEventTap()
    }

    deinit {
        pollingTimer?.cancel(); if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let eventTapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes) }
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        clear(); if let handler { RemoveEventHandler(handler) }
    }

    func register(_ shortcuts: [ShortcutConfiguration], termaticaEnabled: Bool = false) {
        clear()
        let screenAnswerShortcut = ShortcutConfiguration(action: .screenAnswer, key: "m", option: false, command: true)
        let termaticaShortcut = ShortcutConfiguration(action: .termatica, key: "return", option: false, command: true)
        polledShortcuts = [screenAnswerShortcut] + (termaticaEnabled && TermaticaIntegrationService.isInstalled ? [termaticaShortcut] : []) + shortcuts.filter {
            !(Self.keyCodes[$0.key.lowercased()] == 46 && $0.command && !$0.option && !$0.control && !$0.shift)
        }
        var combinations = Set<String>()
        // The secret answer shortcut is registered directly with the macOS
        // dispatcher and does not depend on app focus or editable keybinds.
        var fixed: [(UInt32, ShortcutConfiguration, Int, UInt32)] = [
            (2004, screenAnswerShortcut, 46, UInt32(cmdKey))
        ]
        if termaticaEnabled && TermaticaIntegrationService.isInstalled {
            fixed.append((2005, termaticaShortcut, kVK_Return, UInt32(cmdKey)))
        }
        for (idValue, shortcut, code, modifiers) in fixed {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: idValue)
            let status = RegisterEventHotKey(UInt32(code), modifiers, id, GetEventDispatcherTarget(), 0, &ref)
            if status == noErr, let ref { refs.append(ref); systemShortcuts[idValue] = shortcut; NSLog("Ryft registered system-wide shortcut %@", shortcut.display) }
            else { NSLog("Ryft could not register system-wide shortcut %@ (OSStatus %d)", shortcut.display, status) }
            combinations.insert("\(code)-\(modifiers)")
        }
        // Workspace navigation is intentionally fixed and global, matching the
        // desktop labels in the bar. Carbon hotkeys need no Accessibility or
        // Input Monitoring permission and continue working behind other apps.
        for (number, code) in [18, 19, 20, 21, 23, 22, 26, 28, 25].enumerated() {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(1001 + number))
            if RegisterEventHotKey(UInt32(code), UInt32(optionKey), id, GetEventDispatcherTarget(), 0, &ref) == noErr, let ref { refs.append(ref) }
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
            let status = RegisterEventHotKey(UInt32(code), modifiers, id, GetEventDispatcherTarget(), 0, &ref)
            if status == noErr, let ref { refs.append(ref); registeredShortcuts[hotkeyID] = shortcut; NSLog("Ryft registered global shortcut %@ for %@", shortcut.display, shortcut.action.rawValue) }
            else { NSLog("Ryft could not register global shortcut %@ (OSStatus %d)", shortcut.display, status) }
        }
    }

    private func installEventTap() {
        guard eventTap == nil else { return }
        lastEventTapAttempt = Date()
        let mask = CGEventMask(1) << CGEventType.keyDown.rawValue
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = manager.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            guard type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return Unmanaged.passUnretained(event) }
            let code = Int(event.getIntegerValueField(.keyboardEventKeycode)); let flags = event.flags
            DispatchQueue.main.async { manager.handleGlobalKey(code: code, option: flags.contains(.maskAlternate), command: flags.contains(.maskCommand), control: flags.contains(.maskControl), shift: flags.contains(.maskShift)) }
            return Unmanaged.passUnretained(event)
        }
        eventTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: mask, callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque())
        // Never prompt during launch. The first-run Permissions page lets the
        // user request Input Monitoring explicitly and explains why it is used.
        guard let eventTap else { NSLog("Ryft global event tap is unavailable; enable Input Monitoring for Ryft") ; return }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0); eventTapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes); CGEvent.tapEnable(tap: eventTap, enable: true)
        NSLog("Ryft global event tap enabled")
    }

    private func handleGlobalKey(code: Int, option: Bool, command: Bool, control: Bool, shift: Bool) {
        if option && !command && !control && !shift {
            if let index = [18, 19, 20, 21, 23, 22, 26, 28, 25].firstIndex(of: code) { invokeWorkspace(index + 1); return }
        }
        if let shortcut = polledShortcuts.first(where: { Self.keyCodes[$0.key.lowercased()] == code && $0.option == option && $0.command == command && $0.control == control && $0.shift == shift }) { invoke(shortcut) }
    }

    private func handleMonitoredKey(_ event: NSEvent) {
        guard !event.isARepeat else { return }
        let flags = event.modifierFlags.intersection([.option, .command, .control, .shift])
        if flags == [.option], let index = [18, 19, 20, 21, 23, 22, 26, 28, 25].firstIndex(of: Int(event.keyCode)) { invokeWorkspace(index + 1); return }
        if let shortcut = polledShortcuts.first(where: { shortcut in
            guard Self.keyCodes[shortcut.key.lowercased()] == Int(event.keyCode) else { return false }
            var expected: NSEvent.ModifierFlags = []
            if shortcut.option { expected.insert(.option) }; if shortcut.command { expected.insert(.command) }; if shortcut.control { expected.insert(.control) }; if shortcut.shift { expected.insert(.shift) }
            return flags == expected
        }) { invoke(shortcut) }
    }

    private func pollKeyboard() {
        if eventTap == nil, CGPreflightListenEventAccess(), Date().timeIntervalSince(lastEventTapAttempt) > 2 { installEventTap() }
        let state: CGEventSourceStateID = .combinedSessionState
        let flags = CGEventSource.flagsState(state)
        let relevantCodes = Set(polledShortcuts.compactMap { Self.keyCodes[$0.key.lowercased()] } + [18, 19, 20, 21, 23, 22, 26, 28, 25])
        let downNow = Set(relevantCodes.filter { CGEventSource.keyState(state, key: CGKeyCode($0)) })
        let newlyDown = downNow.subtracting(keysDown); keysDown = downNow
        guard !newlyDown.isEmpty else { return }
        let option = flags.contains(.maskAlternate), command = flags.contains(.maskCommand), control = flags.contains(.maskControl), shift = flags.contains(.maskShift)
        for code in newlyDown {
            if option && !command && !control && !shift, let index = [18, 19, 20, 21, 23, 22, 26, 28, 25].firstIndex(of: code) { invokeWorkspace(index + 1); continue }
            if let shortcut = polledShortcuts.first(where: { Self.keyCodes[$0.key.lowercased()] == code && $0.option == option && $0.command == command && $0.control == control && $0.shift == shift }) { invoke(shortcut) }
        }
    }

    private func invokeWorkspace(_ number: Int) {
        if let lastWorkspaceInvocation, lastWorkspaceInvocation.0 == number, Date().timeIntervalSince(lastWorkspaceInvocation.1) < 0.18 { return }
        lastWorkspaceInvocation = (number, Date()); onWorkspace?(number)
    }

    private func invoke(_ shortcut: ShortcutConfiguration) {
        let invocationKey = shortcut.action.rawValue + "|" + shortcut.display
        let duplicateWindow = shortcut.action == .leftSidebar || shortcut.action == .rightSidebar ? 0.4 : 0.18
        if let lastInvocation, lastInvocation.0 == invocationKey, Date().timeIntervalSince(lastInvocation.1) < duplicateWindow { return }
        lastInvocation = (invocationKey, Date()); NSLog("Ryft received global shortcut %@", shortcut.display); onShortcut?(shortcut)
    }

    private func clear() { refs.forEach { UnregisterEventHotKey($0) }; refs.removeAll(); registeredShortcuts.removeAll(); systemShortcuts.removeAll() }
    private static let signature: OSType = 0x57415943
    static let keyCodes: [String: Int] = [
        "a":0,"s":1,"d":2,"f":3,"h":4,"g":5,"z":6,"x":7,"c":8,"v":9,"b":11,"q":12,"w":13,"e":14,"r":15,"y":16,"t":17,
        "1":18,"2":19,"3":20,"4":21,"6":22,"5":23,"=":24,"9":25,"7":26,"-":27,"8":28,"0":29,"o":31,"u":32,"i":34,"p":35,"l":37,"j":38,"k":40,"n":45,"m":46,"return":36
    ]
}

extension Collection {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}
