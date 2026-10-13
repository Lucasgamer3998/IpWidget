import WidgetKit
import SwiftUI
import MapKit
import CoreLocation
import CoreImage

struct IPEntry: TimelineEntry {
    let date: Date
    let ip: String?
    let map: NSImage?
    /// High-contrast greyscale map for when macOS dims the widget (it draws by brightness only).
    var dimmedMap: NSImage? = nil
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> IPEntry {
        IPEntry(date: .now, ip: "192.168.1.10", map: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (IPEntry) -> Void) {
        Task { completion(await makeEntry(for: context)) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<IPEntry>) -> Void) {
        Task {
            let entry = await makeEntry(for: context)
            completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
        }
    }

    private func makeEntry(for context: Context) async -> IPEntry {
        let ip = NetworkInfo.localIPv4()
        guard context.family != .systemSmall, let coordinate = await currentCoordinate() else {
            return IPEntry(date: .now, ip: ip, map: nil)
        }
        async let map = mapImage(at: coordinate, size: context.displaySize, dark: false)
        async let darkMap = mapImage(at: coordinate, size: context.displaySize, dark: true)
        return IPEntry(date: .now, ip: ip, map: await map, dimmedMap: (await darkMap).flatMap(highContrastGrey))
    }

    /// Tries a fresh fix (uses the app's location permission), falling back to the last one the app saved.
    private func currentCoordinate() async -> CLLocationCoordinate2D? {
        let fresh = await withTaskGroup(of: CLLocationCoordinate2D?.self) { group in
            group.addTask {
                do {
                    for try await update in CLLocationUpdate.liveUpdates() {
                        if let location = update.location { return location.coordinate }
                    }
                } catch {}
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(5))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        if let fresh {
            SharedStore.saveLocation(fresh)
            return fresh
        }
        return CLLocationManager().location?.coordinate ?? SharedStore.lastLocation()
    }

    private func mapImage(at coordinate: CLLocationCoordinate2D, size: CGSize, dark: Bool) async -> NSImage? {
        let options = MKMapSnapshotter.Options()
        options.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        if dark { options.pointOfInterestFilter = .excludingAll } // less clutter when dimmed
        options.region = MKCoordinateRegion(center: coordinate,
                                            latitudinalMeters: 1500, longitudinalMeters: 1500)
        options.size = size
        return try? await MKMapSnapshotter(options: options).start().image
    }

    /// Turns a dark-mode map into greyscale with black ground and bright streets.
    /// When dimmed, macOS shows bright parts and lets dark parts fade into the wallpaper.
    /// In the dark map the ground is ~35% brightness and streets ~45%, so stretch
    /// that range: brightness × 4.5 − 1.5 maps ground to 0 and streets to ~0.6–0.7.
    private func highContrastGrey(_ image: NSImage) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let gain: CGFloat = 4.5, offset: CGFloat = 1.5
        let output = CIImage(cgImage: cgImage)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: gain, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: gain, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: gain, w: 0),
                "inputBiasVector": CIVector(x: -offset, y: -offset, z: -offset, w: 0),
            ])
            .applyingFilter("CIColorClamp")
        // No colour management, so the maths runs on the same brightness values measured above.
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        guard let result = context.createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: result, size: image.size)
    }
}

struct IpWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: IPEntry

    var body: some View {
        switch family {
        case .systemSmall:
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "network")
                    .font(.title2)
                    .foregroundStyle(.tint)
                Spacer()
                Text("Local IP")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ipText
                    .font(.headline.monospacedDigit())
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .containerBackground(.background, for: .widget)
        default:
            ZStack(alignment: .bottomLeading) {
                Color.clear
                if !isFullColor, let dimmedMap = entry.dimmedMap {
                    // Backgrounds are hidden when dimmed, so the map has to be part of the content.
                    Image(nsImage: dimmedMap)
                        .resizable()
                        .widgetAccentedRenderingMode(.desaturated)
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .mask {
                            // Clear a small gap in the streets around the location marker.
                            ZStack {
                                Color.white
                                Circle().fill(.black).frame(width: 34, height: 34)
                            }
                            .compositingGroup()
                            .luminanceToAlpha()
                        }
                }
                if entry.map != nil {
                    // The map is centered on the current location, so the marker goes in the middle.
                    locationMarker
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                ipLabel
                    .foregroundStyle(isFullColor ? AnyShapeStyle(.primary) : AnyShapeStyle(.clear))
                    .background { ipBox }
                    .padding(12)
            }
            .mask {
                if isFullColor {
                    Color.white
                } else {
                    // When dimmed, macOS draws text and shapes in one flat tint, so text on a
                    // box blends in. Instead, cut the IP out of everything (box and map) like a
                    // stencil, so the letters show the wallpaper. White = keep, black = cut out.
                    ZStack(alignment: .bottomLeading) {
                        Color.white
                        ipLabel.foregroundStyle(.black).padding(12)
                    }
                    .compositingGroup()
                    .luminanceToAlpha()
                }
            }
            .containerBackground(for: .widget) {
                if let map = entry.map {
                    Image(nsImage: map)
                        .resizable()
                        .widgetAccentedRenderingMode(.desaturated)
                        .scaledToFill()
                } else {
                    ContentUnavailableView("Location unavailable", systemImage: "location.slash",
                                           description: Text("Open IpWidget to grant location access."))
                }
            }
        }
    }

    private var ipText: Text { Text(entry.ip ?? "No network") }

    private var ipLabel: some View {
        Label { ipText } icon: { Image(systemName: "network") }
            .font(.headline.monospacedDigit())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
    }

    /// False when macOS dims the widget (it isn't highlighted).
    private var isFullColor: Bool { renderingMode == .fullColor }

    /// "You are here" marker in the style of Apple Maps.
    @ViewBuilder private var locationMarker: some View {
        if isFullColor {
            ZStack {
                Circle().fill(.blue.opacity(0.2)).frame(width: 46, height: 46)
                Circle().fill(.white).frame(width: 22, height: 22).shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                Circle().fill(.blue).frame(width: 15, height: 15)
            }
        } else {
            // Everything is one flat tint when dimmed, so use a ring and a dot
            // separated by gaps instead of colours.
            ZStack {
                Circle().strokeBorder(.white, lineWidth: 2.5).frame(width: 26, height: 26)
                Circle().fill(.white).frame(width: 12, height: 12)
            }
        }
    }

    /// Frosted pill in full colour; a solid pill when dimmed (the IP is cut out of it).
    @ViewBuilder private var ipBox: some View {
        if isFullColor {
            Capsule().fill(.regularMaterial)
        } else {
            Capsule().fill(.white)
        }
    }
}

@main
struct IpWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedStore.widgetKind, provider: Provider()) { entry in
            IpWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Local IP")
        .description("Shows your local IP address, plus a map of where you are on larger sizes.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
