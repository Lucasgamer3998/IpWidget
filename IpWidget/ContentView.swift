import SwiftUI
import MapKit
import WidgetKit
import ServiceManagement

struct ContentView: View {
    let network: NetworkMonitor
    let location: LocationModel
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(network.ip ?? "No network", systemImage: "network")
                .font(.title.monospacedDigit().bold())

            Map(position: .constant(.userLocation(fallback: .automatic))) {
                UserAnnotation()
            }
            .frame(width: 340, height: 200)
            .clipShape(.rect(cornerRadius: 12))

            Text(location.status)
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("Add the widget by right‑clicking the desktop → Edit Widgets → IpWidget. Keep this app running and the widget updates as soon as your network changes.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Open at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() }
                        else { try SMAppService.mainApp.unregister() }
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }

            HStack {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    network.checkIP()
                    location.refresh()
                    WidgetCenter.shared.reloadAllTimelines()
                }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding()
        .frame(width: 372)
    }
}

/// Requests location permission (which the widget piggybacks on) and
/// stores the latest fix in the shared App Group for the widget.
@Observable
final class LocationModel: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var status = "Locating…"

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func refresh() {
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .denied, .restricted:
                status = "Location access denied – enable it in System Settings → Privacy & Security → Location Services."
            case .authorized, .authorizedAlways:
                manager.requestLocation()
            default: break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        SharedStore.saveLocation(coordinate)
        Task { @MainActor in
            status = String(format: "Location: %.4f, %.4f", coordinate.latitude, coordinate.longitude)
            WidgetCenter.shared.reloadTimelines(ofKind: SharedStore.widgetKind)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in status = "Location unavailable: \(error.localizedDescription)" }
    }
}

#Preview {
    ContentView(network: NetworkMonitor(), location: LocationModel())
}
