import Foundation
import Network
import WidgetKit

/// Watches for network changes (e.g. switching Wi‑Fi) and refreshes the widget
/// as soon as the local IP changes. Only works while the app is running.
@Observable
final class NetworkMonitor {
    private(set) var ip = NetworkInfo.localIPv4()
    /// Called after the IP changes, e.g. to refresh the location too.
    var onChange: (() -> Void)?

    private let monitor = NWPathMonitor()
    private var checkTask: Task<Void, Never>?
    private var backstop: Task<Void, Never>?

    init() {
        monitor.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor in self?.networkChanged() }
        }
        monitor.start(queue: .main)
        // Safety net for changes the path monitor doesn't report.
        backstop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                self?.checkIP()
            }
        }
    }

    /// The new IP can take a few seconds to arrive (DHCP) after the network
    /// changes, so check a few times.
    private func networkChanged() {
        checkTask?.cancel()
        checkTask = Task {
            for delay in [1, 3, 8] {
                try? await Task.sleep(for: .seconds(delay))
                if Task.isCancelled { return }
                checkIP()
            }
        }
    }

    func checkIP() {
        let current = NetworkInfo.localIPv4()
        guard current != ip else { return }
        ip = current
        WidgetCenter.shared.reloadTimelines(ofKind: SharedStore.widgetKind)
        onChange?()
    }
}
