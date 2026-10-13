import Foundation
import CoreLocation
import Security

/// App Group shared between the app and the widget extension.
/// The group is "<Team ID>.ipwidget.shared" (see Config/*.entitlements). Team-prefixed
/// groups work on macOS without registering them in the developer portal. The name is
/// read from the signed entitlements, so no Team ID needs to be written in the code.
enum SharedStore {
    nonisolated static let appGroup: String? = {
        guard let task = SecTaskCreateFromSelf(nil),
              let groups = SecTaskCopyValueForEntitlement(
                  task, "com.apple.security.application-groups" as CFString, nil) as? [String]
        else { return nil }
        return groups.first
    }()
    nonisolated static let widgetKind = "IpWidget"

    nonisolated private static var defaults: UserDefaults? { appGroup.flatMap { UserDefaults(suiteName: $0) } }

    nonisolated static func saveLocation(_ coordinate: CLLocationCoordinate2D) {
        defaults?.set(coordinate.latitude, forKey: "lat")
        defaults?.set(coordinate.longitude, forKey: "lon")
        defaults?.set(Date(), forKey: "locationDate")
    }

    nonisolated static func lastLocation() -> CLLocationCoordinate2D? {
        guard let defaults, defaults.object(forKey: "lat") != nil else { return nil }
        return CLLocationCoordinate2D(latitude: defaults.double(forKey: "lat"),
                                      longitude: defaults.double(forKey: "lon"))
    }
}

enum NetworkInfo {
    /// Returns the primary local IPv4 address (Wi‑Fi/Ethernet), if any.
    nonisolated static func localIPv4() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var candidates: [(name: String, ip: String)] = []
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let iface = ptr.pointee
            let flags = Int32(iface.ifa_flags)
            guard let addr = iface.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0
            else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            candidates.append((String(cString: iface.ifa_name), String(cString: host)))
        }
        // Prefer physical interfaces (en0, en1, …) over VPN/bridge interfaces.
        return candidates.first { $0.name.hasPrefix("en") }?.ip ?? candidates.first?.ip
    }
}
