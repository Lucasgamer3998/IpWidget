import SwiftUI

@main
struct IpWidgetApp: App {
    @State private var network: NetworkMonitor
    @State private var location: LocationModel

    var body: some Scene {
        MenuBarExtra {
            ContentView(network: network, location: location)
        } label: {
            Image(systemName: "network")
        }
        .menuBarExtraStyle(.window)
    }

    init() {
        let network = NetworkMonitor()
        let location = LocationModel()
        // A new network may mean a new place, so refresh the map's location too.
        network.onChange = { location.refresh() }
        location.refresh()
        _network = State(initialValue: network)
        _location = State(initialValue: location)
    }
}
