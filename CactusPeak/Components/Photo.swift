import SwiftUI

// Club header and member avatar. Classes, spaces and coaches use the brand graphics in Shared/BrandGraphics.swift.
// Clubs show their Set beside the name, never a picture.

extension Color {
    /// Flat blend used for tonal fills (no gradient).
    func mix(with other: Color, _ amount: Double) -> Color {
        Color(self.resolve(in: EnvironmentValues()).mixed(other, amount))
    }
}
private extension Color.Resolved {
    func mixed(_ other: Color, _ t: Double) -> Color.Resolved {
        let o = other.resolve(in: EnvironmentValues())
        return Color.Resolved(red: red + (o.red - red) * Float(t), green: green + (o.green - green) * Float(t),
                              blue: blue + (o.blue - blue) * Float(t), opacity: 1)
    }
}

/// A club's header: its Set, the name, the city and the facts, on the page. The app shows no picture for a club.
struct ClubHero: View {
    let club: Club

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ClubSet(slug: club.slug, size: 32).padding(.bottom, 6)
            Text(club.fullName).brandFont(.display).foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
            // The name is the cross streets, so the city has its own line.
            Text("\(club.city), AZ").font(.subheadline.weight(.semibold)).foregroundStyle(Color.secondary)
            Text(club.factLine).font(.subheadline).foregroundStyle(Color.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal).padding(.top, 8).padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Monogram avatar for members and family. Coaches use `CoachImage` (initials on Night with an object badge).
struct Avatar: View {
    var initials: String
    var category: ClassCategory?
    var size: CGFloat = 32
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1
    var body: some View {
        let s = size * min(scale, 1.6)
        ZStack {
            Circle().fill((category?.color ?? Color.secondary).opacity(0.16))
            Text(initials).monogramFont(diameter: s)
                .foregroundStyle(category?.textColor ?? Color.primary)
        }
        .frame(width: s, height: s)
        .accessibilityHidden(true)
    }
}
