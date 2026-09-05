import Foundation
import Network

/// Triggers the Local Network permission prompt and warms Bonjour — required in LiveContainer
/// before MultipeerConnectivity advertising/browsing, otherwise NSNetServicesErrorDomain -72008.
@MainActor
final class LocalNetworkPrimer {
    private var browser: NWBrowser?
    private var listener: NWListener?
    private var continuation: CheckedContinuation<Void, Never>?
    private var finished = false

    /// Best-effort fire-and-forget warm-up (app launch / navigation).
    func prime() {
        Task { await primeAndWait(timeoutSeconds: 1.2) }
    }

    /// Awaitable warm-up used right before host/join mesh start.
    func primeAndWait(timeoutSeconds: TimeInterval = 2.5) async {
        cancel()
        finished = false

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.continuation = cont

            let params = NWParameters.udp
            params.includePeerToPeer = true

            // Browse for our Multipeer service type (must match Info.plist NSBonjourServices).
            let browser = NWBrowser(
                for: .bonjour(type: "_soundpuddle._tcp", domain: nil),
                using: params
            )
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

            // Publishing a short-lived listener also forces the permission sheet on iOS 14+.
            do {
                let listener = try NWListener(using: params)
                listener.service = NWListener.Service(name: "SoundPuddlePrime", type: "_soundpuddle._tcp")
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
                // Browser alone is still enough to surface the prompt.
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
