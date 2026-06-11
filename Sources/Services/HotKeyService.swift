import Carbon.HIToolbox
import Foundation

/// Global hotkey via Carbon RegisterEventHotKey — works without accessibility
/// permissions (unlike CGEvent taps). Currently a single binding: ⌃⌥G → Go-Around.
final class HotKeyService {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let callback: () -> Void

    init(callback: @escaping () -> Void) {
        self.callback = callback
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let service = Unmanaged<HotKeyService>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { service.callback() }
            return noErr
        }, 1, &eventType, selfPtr, &handlerRef)
        let hotKeyID = EventHotKeyID(signature: OSType(0x4450_4C54), id: 1)  // 'DPLT'
        RegisterEventHotKey(UInt32(kVK_ANSI_G), UInt32(controlKey | optionKey), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
