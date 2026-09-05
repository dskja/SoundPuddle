import Foundation
import Network

/// Primes the Local Network permission dialog (critical inside LiveContainer).
final class LocalNetworkPrimer {
    private var browser: NWBrowser?

    func prime() {
        let params = NWParameters()
        params.includePeerToPeer = true
        let descriptor: NWBrowser.Descriptor = .bonjour(type: "_soundpuddle._tcp", domain: nil)
        let browser = NWBrowser(for: descriptor, using: params)
        browser.stateUpdateHandler = { (_: NWBrowser.State, _: NWBrowser.State) in }
        browser.browseResultsChangedHandler = { (_: Set<NWBrowser.Result>, _: Set<NWBrowser.Result.Change>) in }
        browser.start(queue: .main)
        self.browser = browser
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.browser?.cancel()
            self?.browser = nil
        }
    }
}
