// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// SwiftUI panel rendered on each non-streamed display when the host is
/// in `.secureOverlay` mode. Offers Touch ID / macOS password (when the
/// policy allows + LocalAuth is available) and the mandatory MacStream
/// fallback password when it is set.
///
/// Decoupled from `AppState` so it can be hosted by the per-display
/// NSWindow without dragging in EnvironmentObjects. All state crosses
/// through callbacks the controller wires up.
struct SecureLockOverlayContent: View {
    let allowMacOSAuthentication: Bool
    let allowAppPassword: Bool
    let macOSAuthAvailable: Bool
    let isAppPasswordSet: Bool
    let lockoutUntil: Date?
    let onBiometric: () -> Void
    let onAppPassword: (String) -> Void

    @State private var passwordCandidate: String = ""
    @State private var showingMismatchError: Bool = false
    @FocusState private var passwordFocused: Bool
    @State private var countdownTick: Date = Date()

    private var showPasswordField: Bool {
        allowAppPassword && isAppPasswordSet
    }

    private var showBiometricButton: Bool {
        allowMacOSAuthentication && macOSAuthAvailable
    }

    private var lockoutSecondsRemaining: Int? {
        guard let until = lockoutUntil, until > countdownTick else { return nil }
        return Int(until.timeIntervalSince(countdownTick).rounded(.up))
    }

    var body: some View {
        ZStack {
            // Solid black background — covers the entire display.
            Color.black
                .ignoresSafeArea()

            // Centered card with the unlock controls. Bordered subtle
            // outline so it reads as a control surface, not free-floating
            // text on the black field.
            VStack(spacing: 18) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(.white)

                Text("Host bloqueado")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(.white)

                Text("Só você (no Mac) vê esta janela. O cliente remoto continua acessando o desktop normalmente.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 380)

                if let remaining = lockoutSecondsRemaining {
                    VStack(spacing: 6) {
                        Label("Tentativas excedidas", systemImage: "exclamationmark.triangle.fill")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.orange)
                        Text("Aguarde \(remaining) segundos antes de tentar novamente.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.top, 6)
                } else {
                    if showBiometricButton {
                        Button(action: onBiometric) {
                            Label("Touch ID / Senha do Mac", systemImage: "touchid")
                                .font(.headline)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(.white.opacity(0.95))
                        .foregroundStyle(.black)
                    }

                    if showPasswordField {
                        VStack(spacing: 8) {
                            SecureField("Senha do MacStream", text: $passwordCandidate)
                                .textFieldStyle(.roundedBorder)
                                .focused($passwordFocused)
                                .frame(maxWidth: 280)
                                .onSubmit(attemptPasswordUnlock)

                            if showingMismatchError {
                                Label("Senha incorreta", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }

                            Button(action: attemptPasswordUnlock) {
                                Label("Desbloquear", systemImage: "lock.open.fill")
                                    .font(.headline)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .keyboardShortcut(.defaultAction)
                            .disabled(passwordCandidate.isEmpty)
                        }
                    }

                    if !showBiometricButton && !showPasswordField {
                        Text("Nenhum método de desbloqueio disponível. Configure uma senha do MacStream ou ative Touch ID / senha do macOS.")
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 380)
                    }
                }
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(.black.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            )
            .padding(40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if showPasswordField, lockoutSecondsRemaining == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    passwordFocused = true
                }
            }
        }
        // 1Hz timer drives the lockout countdown without leaking into
        // app-wide refresh cycles. Stops naturally when the view goes away.
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { tick in
            countdownTick = tick
        }
    }

    private func attemptPasswordUnlock() {
        let candidate = passwordCandidate
        guard !candidate.isEmpty else { return }
        onAppPassword(candidate)
        // Clear the field so a wrong password doesn't linger; the
        // controller will surface mismatch by updating `showingMismatchError`.
        passwordCandidate = ""
        showingMismatchError = true
        passwordFocused = true
    }
}
