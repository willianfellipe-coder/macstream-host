// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

public final class DefaultManagedEngineManager: ManagedEngineManaging {
    private let sunshineManager: SunshineManaging
    private let audioDeviceManager: AudioDeviceManaging
    private let networkDiagnosticsManager: NetworkDiagnosticsManaging

    public init(
        sunshineManager: SunshineManaging,
        audioDeviceManager: AudioDeviceManaging,
        networkDiagnosticsManager: NetworkDiagnosticsManaging
    ) {
        self.sunshineManager = sunshineManager
        self.audioDeviceManager = audioDeviceManager
        self.networkDiagnosticsManager = networkDiagnosticsManager
    }

    public func status() async -> ManagedEngineStatus {
        let video = await sunshineManager.status()
        let audio = await audioDeviceManager.validateAudioRoute()
        let network = await networkDiagnosticsManager.runDiagnostics()

        return ManagedEngineStatus(components: [
            ManagedEngineComponentStatus(
                id: .video,
                status: video.state.checkStatus,
                detail: videoDetail(for: video)
            ),
            ManagedEngineComponentStatus(
                id: .audio,
                status: audio,
                detail: audioDetail(for: audio)
            ),
            ManagedEngineComponentStatus(
                id: .network,
                status: network.aggregateStatus,
                detail: network.localAddresses.first.map { "Endereco principal: \($0)." } ?? "Nenhum IP local detectado."
            )
        ])
    }

    private func videoDetail(for status: SunshineStatus) -> String {
        switch status.state {
        case .running:
            return status.ownedProcessID == nil
                ? "Engine de video externa detectada; MacStream nao controla este processo."
                : "Engine de video gerenciada esta ativa."
        case .stopped:
            return "Engine de video gerenciada esta parada."
        case .notInstalled:
            return "Engine de video ainda nao instalada pelo MacStream."
        case .failed:
            return "Engine de video reportou falha; verifique diagnosticos."
        case .degraded:
            return "Engine de video ativa com degradacao."
        case .starting:
            return "Engine de video iniciando."
        case .unknown:
            return "Status da engine de video desconhecido."
        }
    }

    private func audioDetail(for status: CheckStatus) -> String {
        switch status {
        case .pass:
            return "Rota de audio do MacStream validada."
        case .warning:
            return "Audio precisa de validacao pratica no cliente."
        case .fail:
            return "Nenhuma rota de audio utilizavel foi detectada."
        case .unknown:
            return "Status da rota de audio desconhecido."
        }
    }
}
