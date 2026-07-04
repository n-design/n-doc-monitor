import SwiftUI

/// Helpers for storing a SwiftUI `Color` in `@AppStorage`.
///
/// **Step 11 — Configurable accent color:**
///
/// `@AppStorage` works with types that conform to `RawRepresentable`
/// where `RawValue` is a supported type (`String`, `Int`, `Data`, etc.).
/// SwiftUI's `Color` doesn't conform out of the box, so we add a
/// conformance that encodes/decodes it as a hex string.
///
/// **SwiftUI concept — `@AppStorage` with custom types:**
/// By conforming `Color` to `RawRepresentable` with a `String`
/// raw value, we can use `@AppStorage("key") var color: Color`.

extension Color: @retroactive RawRepresentable {

    /// Encode the color as a hex string (e.g. "#FF8800FF").
    public init?(rawValue: String) {
        guard rawValue.hasPrefix("#"), rawValue.count == 9 else {
            return nil
        }

        let hex = String(rawValue.dropFirst())
        guard let value = UInt64(hex, radix: 16) else { return nil }

        let r = Double((value >> 24) & 0xFF) / 255.0
        let g = Double((value >> 16) & 0xFF) / 255.0
        let b = Double((value >> 8)  & 0xFF) / 255.0
        let a = Double( value        & 0xFF) / 255.0

        self.init(red: r, green: g, blue: b, opacity: a)
    }

    /// Decode the color from a hex string.
    public var rawValue: String {
        // Resolve to NSColor to extract components.
        let nsColor = NSColor(self).usingColorSpace(.sRGB)
            ?? NSColor(self)

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        nsColor.getRed(&r, green: &g, blue: &b, alpha: &a)

        let ri = Int(round(r * 255))
        let gi = Int(round(g * 255))
        let bi = Int(round(b * 255))
        let ai = Int(round(a * 255))

        return String(format: "#%02X%02X%02X%02X", ri, gi, bi, ai)
    }
}

/// The default accent color used throughout the app.
let defaultAccentColor = Color.orange
