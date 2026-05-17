// SPDX-License-Identifier: GPL-3.0-or-later

import CoreAudio
import Foundation

/// Watches CoreAudio's device list and emits an event every time devices are
/// added or removed (BlackHole installation, USB DAC plugged in, AirPods
/// connected, etc).
///
/// The dashboard subscribes to this so the "Roteamento de áudio" card flips
/// from `Não encontrado` to `Instalado` the moment the BlackHole HAL plug-in
/// becomes visible — no app restart required and no polling burning CPU
/// while waiting for the user to type their admin password.
public final class AudioDeviceMonitor {
    private let address: AudioObjectPropertyAddress
    private var listener: AudioObjectPropertyListenerBlock?
    private var continuation: AsyncStream<Void>.Continuation?
    private(set) public var events: AsyncStream<Void>

    public init() {
        self.address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var local: AsyncStream<Void>.Continuation!
        self.events = AsyncStream { local = $0 }
        self.continuation = local
    }

    /// Registers the property listener. Safe to call multiple times — only
    /// the first call attaches the underlying CoreAudio block.
    public func start() {
        guard listener == nil else { return }
        let continuation = self.continuation
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            continuation?.yield(())
        }
        listener = block
        var address = self.address
        _ = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.global(qos: .utility),
            block
        )
    }

    public func stop() {
        guard let block = listener else { return }
        var address = self.address
        _ = AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.global(qos: .utility),
            block
        )
        listener = nil
        continuation?.finish()
        continuation = nil
    }

    deinit {
        stop()
    }
}
