import SwiftUI
import UIKit
import CoreText

// The app's type system. Every font in the app and the widgets comes from this file.
// `tools/check-type.py` runs on every build and fails on a font call that skips these roles.
//
// Rules (brand guidelines §5, iOS):
// T1  Archivo is only for brand roles: headlines, big numerals and eyebrows. Use `.brandFont(_:)`.
//     Archivo is set expanded (wdth 112) and heavy (700–800), sentence case. Never type the logo.
// T2  Body and UI text use the system font (SF Pro) through SwiftUI text styles: `.body`, `.headline`,
//     `.subheadline`, `.callout`, `.footnote`, `.caption`, `.caption2`, with any weight.
//     The display styles (`.largeTitle`, `.title`, `.title2`, `.title3`) are not used for text: those sizes are
//     brand headlines. An SF Symbol takes a display size through `.symbolFont(_:)`.
// T3  SF Mono is only for codes a person reads out or types: the member number, a booking code. Use `.codeFont(_:)`.
// T4  SF Rounded is only for small live counts in badges, pills and chips (`.countFont(_:)`) and for the initials
//     in an avatar (`.monogramFont(diameter:)`), as in Contacts.
// T5  No fixed point sizes for text. Every role scales with Dynamic Type. Times, counts and prices use tabular figures.

/// The Archivo roles. Each maps to a text style, so it scales with Dynamic Type like the system style it replaces.
enum BrandType: Hashable, Sendable {
    /// 34 pt, ExtraBold, expanded. The one hero line on a screen: welcome, onboarding, a club's hero.
    case display
    /// 28 pt, ExtraBold, expanded. A detail page's title in its intro, or the name on a hero card (a plan).
    case title
    /// 22 pt, Bold, expanded. A name that heads a card or a sheet: a club, a plan, a member on the pass.
    case title2
    /// 20 pt, Bold, expanded. A section header, or the title of a card inside a list.
    case section
    /// A big number or a one-word reading ("Light", "82"), ExtraBold, expanded, tabular figures.
    case numeral(NumeralSize)
    /// 12 pt, SemiBold, expanded, uppercase, tracked +0.24 em. A short label over a heading. Pass the text in
    /// sentence case; the role sets the case.
    case eyebrow
}

enum NumeralSize: Hashable, Sendable {
    /// 20 pt, relative to `.title3`. A number in a tight shape: the day in a date strip.
    case small
    /// 22 pt, relative to `.title2`. A number inside a row or a small card.
    case medium
    /// 30 pt, relative to `.title`. The value of a stat card.
    case large
    /// 40 pt, relative to `.largeTitle`. The one number a screen is about.
    case hero
}

extension View {
    /// Sets an Archivo role (T1). Ensures: the font scales with the environment's Dynamic Type size, numerals use
    /// tabular figures, and an eyebrow is uppercase and tracked.
    func brandFont(_ role: BrandType) -> some View {
        modifier(BrandFontModifier(role: role))
    }

    /// SF Mono for a code a person reads out or types (T3). Tabular by design.
    func codeFont(_ style: Font.TextStyle = .body, weight: Font.Weight = .medium) -> some View {
        font(.system(style, design: .monospaced, weight: weight))
    }

    /// SF Rounded with tabular figures for a small live count in a badge, a pill or a chip (T4).
    func countFont(_ style: Font.TextStyle = .subheadline, weight: Font.Weight = .semibold) -> some View {
        font(.system(style, design: .rounded, weight: weight).monospacedDigit())
    }

    /// SF Rounded initials sized to an avatar circle (T4). The size follows the circle, not Dynamic Type.
    func monogramFont(diameter: CGFloat) -> some View {
        font(.system(size: diameter * 0.38, weight: .semibold, design: .rounded))
    }

    /// A size for an SF Symbol (T2). Text never uses this; the check cannot see the difference, so name what it
    /// sizes in the call site's own view.
    func symbolFont(_ font: Font) -> some View {
        self.font(font)
    }
}

private struct BrandFontModifier: ViewModifier {
    var role: BrandType
    @Environment(\.dynamicTypeSize) private var dts

    func body(content: Content) -> some View {
        let spec = BrandFontSpec(role)
        let size = spec.scaledSize(for: dts)
        content
            .font(Font(BrandFonts.uiFont(spec, size: size)))
            .tracking(spec.tracking * size)
            .textCase(spec.uppercase ? .uppercase : nil)
    }
}

/// Builds Archivo at the brand's weight and width. The font file's named styles are all at normal width, so the
/// width comes from the variation axis.
enum BrandFonts {
    /// Any named style of Archivo-VF.ttf; the variation sets the real weight and width.
    static let baseName = "ArchivoRoman-Regular"

    /// False when Archivo-VF.ttf is not registered (UIAppFonts); the roles then fall back to the system font.
    static var isRegistered: Bool { UIFont(name: baseName, size: 12) != nil }

    nonisolated(unsafe) private static var cache: [String: UIFont] = [:]
    private static let lock = NSLock()

    static func uiFont(_ spec: BrandFontSpec, size: CGFloat) -> UIFont {
        let key = "\(spec.weight)-\(spec.width)-\(spec.tabular)-\(size)"
        lock.lock(); defer { lock.unlock() }
        if let f = cache[key] { return f }
        // 'wght' and 'wdth' as four-character axis tags.
        let axes: [UInt32: CGFloat] = [0x7767_6874: spec.weight, 0x7764_7468: spec.width]
        var attrs: [UIFontDescriptor.AttributeName: Any] = [
            .name: baseName,
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): axes,
        ]
        if spec.tabular {
            attrs[.featureSettings] = [[UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                                        UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector]]
        }
        let font = UIFont(descriptor: UIFontDescriptor(fontAttributes: attrs), size: size)
        cache[key] = font
        return font
    }

    /// Archivo for UIKit text the roles cannot reach (the navigation bar's large title), at launch Dynamic Type.
    static func uiFont(_ role: BrandType) -> UIFont {
        let spec = BrandFontSpec(role)
        return uiFont(spec, size: UIFontMetrics(forTextStyle: spec.uiTextStyle).scaledValue(for: spec.size))
    }
}

/// The numbers behind a role: size, weight, width, the text style it scales with, and its tracking.
struct BrandFontSpec: Hashable, Sendable {
    var size: CGFloat
    var weight: CGFloat
    var width: CGFloat
    var textStyle: Font.TextStyle
    /// In em.
    var tracking: CGFloat
    var uppercase: Bool
    var tabular: Bool

    init(_ role: BrandType) {
        switch role {
        case .display: self.init(34, 800, .largeTitle)
        case .title: self.init(28, 800, .title)
        case .title2: self.init(22, 700, .title2)
        case .section: self.init(20, 700, .title3)
        case .numeral(.small): self.init(20, 700, .title3, tabular: true)
        case .numeral(.medium): self.init(22, 800, .title2, tabular: true)
        case .numeral(.large): self.init(30, 800, .title, tabular: true)
        case .numeral(.hero): self.init(40, 800, .largeTitle, tabular: true)
        case .eyebrow: self.init(12, 600, .caption, tracking: 0.24, uppercase: true)
        }
    }

    /// The size at a Dynamic Type size, scaled the way the system scales `textStyle`.
    func scaledSize(for dts: DynamicTypeSize) -> CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dts))
        return UIFontMetrics(forTextStyle: uiTextStyle).scaledValue(for: size, compatibleWith: traits)
    }

    var uiTextStyle: UIFont.TextStyle {
        switch textStyle {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }

    private init(_ size: CGFloat, _ weight: CGFloat, _ style: Font.TextStyle, tracking: CGFloat = 0, uppercase: Bool = false, tabular: Bool = false) {
        self.size = size; self.weight = weight; self.width = 112; self.textStyle = style
        self.tracking = tracking; self.uppercase = uppercase; self.tabular = tabular
    }
}
