import SwiftUI

// MARK: - Card, flow layout, small helpers

extension View {
    /// Card = secondary grouped fill, continuous corner (20 pt by default), no border, no shadow.
    /// Used only for real objects the member picks. `radius` and `fill` keep their old names.
    func cardStyle(padding: CGFloat = 16, radius: CGFloat = 20, fill: Color = Color(.secondarySystemGroupedBackground)) -> some View {
        self.padding(padding)
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
    func nightCard(padding: CGFloat = 16, radius: CGFloat = 20) -> some View {
        self.padding(padding).background(Color.nightSurface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
    func screenBackground() -> some View { self.background(Color(.systemGroupedBackground).ignoresSafeArea()) }
    func sectionHeader() -> some View { self.brandFont(.section).foregroundStyle(Color.primary).accessibilityAddTraits(.isHeader) }

    /// Toolbar items are monochrome (HIG Toolbars). The app sets `.tint(Color.brandAccent)` at the root, which would
    /// tint toolbar glyphs. Put `barItem()` on every toolbar button except the one prominent primary action.
    func barItem() -> some View { self.tint(.primary) }
}

/// Wraps children onto rows. Measure and place use the same width rule, so a row never reports a different height
/// than it draws. (The old version measured with an unbounded width when the parent proposed none, then placed with the
/// real width. That left a tall empty gap in list rows.)
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    private func rows(_ subviews: Subviews, width: CGFloat) -> (sizes: [CGSize], origins: [CGPoint], total: CGSize) {
        var sizes: [CGSize] = [], origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            var sz = s.sizeThatFits(ProposedViewSize(width: width, height: nil))
            sz.width = min(sz.width, width)
            if x > 0, x + sz.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            sizes.append(sz); origins.append(CGPoint(x: x, y: y))
            x += sz.width + spacing; rowH = max(rowH, sz.height); maxX = max(maxX, x - spacing)
        }
        return (sizes, origins, CGSize(width: maxX, height: y + rowH))
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 10_000
        return rows(subviews, width: w).total
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let r = rows(subviews, width: bounds.width)
        for (i, s) in subviews.enumerated() {
            s.place(at: CGPoint(x: bounds.minX + r.origins[i].x, y: bounds.minY + r.origins[i].y), proposal: ProposedViewSize(r.sizes[i]))
        }
    }
}

// MARK: - System button styles with the brand tint
// Primary = prominent capsule in Copper. The label is forced to BrandOnAccent: white on Arizona Copper (4.95:1)
// and Night on Dawn Copper in dark mode (6.22:1). Secondary = bordered capsule. Links = borderless with the Link colour.

extension View {
    // A frame outside a bordered button widens its hit area but not its capsule, so `full` widens the label
    // inside the style instead.
    func primaryAction(full: Bool = false) -> some View {
        self.buttonStyle(FlexibleLabel(base: .borderedProminent, full: full)).buttonBorderShape(.capsule)
            .controlSize(.large).tint(Color.brandAccent).foregroundStyle(Color.brandOnAccent)
    }
    func secondaryAction(full: Bool = false, destructive: Bool = false) -> some View {
        self.buttonStyle(FlexibleLabel(base: .bordered, full: full)).buttonBorderShape(.capsule).controlSize(.large)
            .tint(destructive ? Color.statusDanger : Color.brandSecondary)
    }
    func linkAction(danger: Bool = false) -> some View {
        self.buttonStyle(.borderless).tint(danger ? Color.statusDanger : Color.linkText).frame(minHeight: 44)
    }
}

struct StatusPill: View {
    enum Tone { case success, warning, danger, neutral, info }
    var text: String
    var symbol: String
    var tone: Tone = .neutral
    var body: some View {
        let (fg, bg): (Color, Color) = switch tone {
        case .success: (.statusSuccess, .statusSuccessSubtle)
        case .warning: (.statusWarning, .statusWarningSubtle)
        case .danger: (.statusDanger, .statusDangerSubtle)
        case .neutral: (Color.primary, Color(.tertiarySystemFill))
        case .info: (Color.primary, Color(.tertiarySystemFill))
        }
        // An HStack, not a Label: inside a list row a Label takes the row's wide icon spacing.
        HStack(spacing: 4) {
            Image(systemName: symbol).imageScale(.small).accessibilityHidden(true)
            Text(text)
        }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(fg)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(bg, in: Capsule())
    }
}

/// Inline banner: icon, sentence, optional action. Warnings always carry the triangle and a sentence.
struct Banner: View {
    enum Tone { case warning, danger, info, success }
    var tone: Tone
    var text: String
    var actionTitle: String?
    var action: (() -> Void)?
    var body: some View {
        let (fg, bg, icon): (Color, Color, String) = switch tone {
        case .warning: (.statusWarning, .statusWarningSubtle, "exclamationmark.triangle.fill")
        case .danger: (.statusDanger, .statusDangerSubtle, "xmark.octagon.fill")
        case .info: (Color.primary, Color(.tertiarySystemFill), "info.circle.fill")
        case .success: (.statusSuccess, .statusSuccessSubtle, "checkmark.circle.fill")
        }
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: icon).foregroundStyle(fg).accessibilityHidden(true)
                Text(text).font(.subheadline).foregroundStyle(Color.primary).fixedSize(horizontal: false, vertical: true)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action).linkAction().padding(.leading, 28)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(bg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct OfflineBanner: View {
    var text: String
    var body: some View {
        Label(text, systemImage: "wifi.slash")
            .font(.footnote.weight(.medium))
            .foregroundStyle(Color.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct EmptyState: View {
    var title: String
    var message: String
    var symbol: String = "square.dashed"
    var actionTitle: String?
    var action: (() -> Void)?
    var secondaryTitle: String?
    var secondary: (() -> Void)?
    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action { Button(actionTitle, action: action).primaryAction() }
            if let secondaryTitle, let secondary { Button(secondaryTitle, action: secondary).linkAction() }
        }
    }
}

/// Five hollow ribs. Used by empty states in place of an SF Symbol.
struct EmptyRibs: View {
    var body: some View { RibMeter(value: 0, tone: .neutral, size: .lg).accessibilityHidden(true) }
}

struct ToastView: View {
    var toast: ToastMessage
    var undo: () -> Void
    var view: () -> Void = {}
    var body: some View {
        HStack(spacing: 12) {
            Text(toast.text).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
            if toast.undoID != nil {
                Button("Undo", action: undo).font(.subheadline.weight(.bold)).foregroundStyle(Color.linkText).frame(minHeight: 44)
            }
            if toast.viewID != nil {
                Button("View", action: view).font(.subheadline.weight(.bold)).foregroundStyle(Color.linkText).frame(minHeight: 44)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 4)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
    }
}

/// Wraps a system button style so the label can fill the width. `primaryAction(full:)` and `secondaryAction(full:)`
/// use it; a Menu does not take a primitive style, so a full-width Menu frames its own label.
struct FlexibleLabel<Base: PrimitiveButtonStyle>: PrimitiveButtonStyle {
    var base: Base
    var full: Bool
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            configuration.label.frame(maxWidth: full ? .infinity : nil)
        }
        .buttonStyle(base)
    }
}

/// Keeps a grouped list at a readable width on a wide window (iPad, a wide split view), as Settings and Wallet do on
/// iPad. On a phone the list keeps the system margins: the modifier changes nothing below `maxWidth` plus margins.
struct ReadableWidth: ViewModifier {
    var maxWidth: CGFloat = 680
    @State private var width: CGFloat = 0
    func body(content: Content) -> some View {
        let margin = (width - maxWidth) / 2
        Group {
            if margin > 40 {
                content.contentMargins(.horizontal, margin, for: .scrollContent)
            } else {
                content
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

extension View {
    func readableWidth(_ maxWidth: CGFloat = 680) -> some View { modifier(ReadableWidth(maxWidth: maxWidth)) }
}
