import Foundation
import Network

/// Primes the Local Network permission dialog (critical inside LiveContainer).
final class LocalNetworkPrimer {
    private var browser: NWBrowser?

    func prime() {
        let params = NWParameters()
        params.includePeerToPeer = true

        let serviceType = "_soundpuddle._tcp"
        let serviceDomain: String? = nil
        let descriptor = NWBrowser.Descriptor.bonjour(type: serviceType, domain: serviceDomain)

        let browser = NWBrowser(for: descriptor, using: params)
        let stateHandler: (NWBrowser.State) -> Void = { _ in }
        let resultsHandler: (Set<NWBrowser.Result>, Set<NWBrowser.Result.Change>) -> Void = { _, _ in }
        browser.stateUpdateHandler = stateHandler
        browser.browseResultsChangedHandler = resultsHandler
        browser.start(queue: DispatchQueue.main)
        self.browser = browser

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.browser?.cancel()
            self?.browser = nil
        }
    }
}
