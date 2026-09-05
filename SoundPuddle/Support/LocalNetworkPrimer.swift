import Foundation
import Network

/// Triggers the Local Network permission prompt and warms Bonjour.
/// In LiveContainer the host allowlist does not include `_soundpuddle._tcp`, so we warm
/// with `_mqtt._tcp` (allowlisted) to avoid NSNetServicesErrorDomain -72008 during priming.
@MainActor
final class LocalNetworkPrimer {
    private var browser: NWBrowser?
    private var listener: NWListener?
    private var continuation: CheckedContinuation<Void, Never>?
    private var finished = false

    private var bonjourType: String {
        LiveContainerRuntime.isActive ? LANBonjourMeshTransport.bonjourType : "_soundpuddle._tcp"
    }

    func prime() {
        Task { await primeAndWait(timeoutSeconds: 1.2) }
    }

    func primeAndWait(timeoutSeconds: TimeInterval = 2.5) async {
        cancel()
        finished = false

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.continuation = cont

            let params = NWParameters.udp
            params.includePeerToPeer = true
            let type = self.bonjourType

            let browser = NWBrowser(for: .bonjour(type: type, domain: nil), using: params)
            browser.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready, .waiting, .failed:
                        self?.finish()
                    default:
                        break
                    }
                }
            }
            browser.browseResultsChangedHandler = { _, _ in }
            self.browser = browser
            browser.start(queue: .main)

            do {
                let listener = try NWListener(using: params)
                listener.service = NWListener.Service(name: "SoundPuddlePrime", type: type)
                listener.stateUpdateHandler = { [weak self] state in
                    Task { @MainActor in
                        switch state {
                        case .ready, .waiting, .failed:
                            self?.finish()
                        default:
                            break
                        }
                    }
                }
                self.listener = listener
                listener.start(queue: .main)
            } catch {
                // Browser alone still surfaces the Local Network prompt.
            }

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                self.finish()
            }
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        cancel()
        continuation?.resume()
        continuation = nil
    }

    private func cancel() {
        browser?.cancel()
        browser = nil
        listener?.cancel()
        listener = nil
    }
}
