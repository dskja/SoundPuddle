import Foundation
import Network

/// Primes the Local Network permission dialog (critical inside LiveContainer).
final class LocalNetworkPrimer {
    private var browser: NWBrowser?

    func prime() {
        let params = NWParameters()
        params.includePeerToPeer = true
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_soundpuddle._tcp", domain: nil)
        let browser = NWBrowser(for: descriptor, using: params)
        browser.stateUpdateHandler = { _, _ in }
        browser.browseResultsChangedHandler = { _, _ in }
        browser.start(queue: .main)
        self.browser = browser
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.browser?.cancel()
            self?.browser = nil
        }
    }
}
