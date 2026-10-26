// 全局快捷键（Carbon RegisterEventHotKey）：不需要辅助功能权限。用于老板键与呼出面板。
import Carbon.HIToolbox
import Foundation

final class HotKey {
    private var ref: EventHotKeyRef?
    private let id: UInt32
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var installed = false
    private static var nextId: UInt32 = 1

    /// keyCode 见 Carbon kVK_*，modifiers 用 cmdKey / optionKey / controlKey / shiftKey。
    init?(keyCode: Int, modifiers: Int, handler: @escaping () -> Void) {
        Self.installIfNeeded()
        id = Self.nextId
        Self.nextId += 1
        let hotKeyID = EventHotKeyID(signature: OSType(0x434C_4E44), id: id) // 'CLND'
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else { return nil }
        Self.handlers[id] = handler
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        Self.handlers[id] = nil
    }

    private static func installIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            DispatchQueue.main.async { HotKey.handlers[hk.id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
