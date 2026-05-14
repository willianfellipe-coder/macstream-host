// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

public final class DefaultMoonlightPairingGuide: MoonlightPairingGuiding {
    public init() {}

    public func pairingSteps() -> [PairingStep] {
        [
            PairingStep(id: 1, title: "Abra o painel do motor", detail: "Use o botão do app para abrir https://localhost:47990 e mantenha o motor rodando."),
            PairingStep(id: 2, title: "Abra Moonlight", detail: "Use o cliente Moonlight no iPad, iPhone, Apple TV, macOS, Windows ou outro dispositivo compatível."),
            PairingStep(id: 3, title: "Encontre ou adicione o Mac", detail: "Na mesma rede, selecione o host detectado. Em VPN mesh, adicione manualmente o IP mostrado na aba Network."),
            PairingStep(id: 4, title: "Confirme o PIN", detail: "Digite no painel do motor o PIN exibido pelo Moonlight."),
            PairingStep(id: 5, title: "Abra Desktop", detail: "Depois do pareamento, escolha Desktop no Moonlight e valide vídeo, áudio e entrada.")
        ]
    }
}
