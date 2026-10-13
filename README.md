# IpWidget

A small macOS menu-bar app with a desktop widget that shows your local IP address.
The medium and large widgets also show a map of where you are.

- The widget updates within seconds when your network changes, while the app is running
  (it lives in the menu bar; there's an "Open at login" toggle).
- When the widget is dimmed (not highlighted), it switches to a high-contrast map and
  cuts the IP out of its box, so both stay readable.

## Build

1. Open `IpWidget.xcodeproj` in Xcode (macOS 27 SDK).
2. For both targets (IpWidget and IpWidgetWidget), go to **Signing & Capabilities**
   and pick your **Team**.
3. Change the bundle identifiers from `com.example.IpWidget` and
   `com.example.IpWidget.Widget` to your own (the widget's must start with the app's).
4. Run. Allow location access when asked, then add the widget:
   right-click the desktop → **Edit Widgets** → **IpWidget**.

The app and widget share data through the App Group `<Team ID>.ipwidget.shared`,
which is filled in automatically from your team (see `Config/*.entitlements`).

## Files

- `IpWidget/` – the menu-bar app (UI, location, network monitoring) and its icon
  (`AppIcon.icon`, editable in Icon Composer)
- `IpWidgetWidget/` – the widget (timeline, map snapshots, views)
- `Shared/` – code used by both (local IP lookup, shared storage)
- `Config/` – entitlements and the widget's Info.plist

## License

[PolyForm Noncommercial 1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0) –
free to use, change and share for any noncommercial purpose. Commercial use is not
allowed. See `LICENSE.md` for the full terms.
