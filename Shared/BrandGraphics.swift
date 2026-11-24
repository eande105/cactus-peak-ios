import SwiftUI

// Cactus Peak brand graphics: the gym objects and their compositions, the same as the marketing site and the web app.
// Source of truth: marketing-site/components/brand/graphics (rules in VISUAL-IDENTITY.md and brand-graphics/README.md).
// The images live in Shared/BrandGraphics.xcassets, which tools/import-brand-graphics.py writes from the exported
// SVGs, with a light and a dark appearance and preserved vector data. Three groups:
//   objects-<id>                 one gym object, brand colours on a clear ground
//   category-<id>[-cut]          a class category's object in its colour, bare or in the 60° cut tile
//   crop-class-<id>-<ratio>      a class category's object, large and cut by the frame, on the category tint
//                                (ObjectCrop on the site's and the web app's class cards); 16x9 heroes, 2x1 cards
// Graphics are images, not interface icons. Interface icons stay on SF Symbols.

/// The club spaces. Raw values are the shared space ids (`spaceObjects` in objects.ts).
enum SpaceGraphicID: String, CaseIterable, Sendable, Hashable {
    case strengthFloor = "strength-floor", machines, cardio, studio, cycleStudio = "cycle-studio", courts
    case lapPool = "lap-pool", warmPool = "warm-pool", splashPad = "splash-pad", recovery, kidsClub = "kids-club"
    case lockers, deck, turf, lounge

    /// The space's lead object (`spaceObjects[id].lead`).
    var lead: String {
        switch self {
        case .strengthFloor: "squat-rack"
        case .machines: "bench"
        case .cardio: "treadmill"
        case .studio: "mat"
        case .cycleStudio: "spin-bike"
        case .courts: "paddle"
        case .lapPool: "pool"
        case .warmPool, .splashPad: "wave"
        case .recovery: "spa-stones"
        case .kidsClub: "playground"
        case .lockers: "key"
        case .deck: "sun"
        case .turf: "sneaker"
        case .lounge: "shaker"
        }
    }
}

extension ClassCategory {
    /// The shared category id.
    var graphicID: String { self == .mindBody ? "mind-body" : rawValue }

    /// The category's object (`categoryObject` in objects.ts).
    var objectID: String {
        switch self {
        case .strength: "kettlebell"
        case .cycle: "spin-bike"
        case .conditioning: "jump-rope"
        case .mindBody: "mat"
        case .aqua: "wave"
        case .court: "paddle"
        case .recovery: "spa-stones"
        case .youth: "cone"
        }
    }
}

/// Image names in BrandGraphics.xcassets.
enum BrandImage {
    /// `wide` is the 16:9 crop (heroes), `card` the 2:1 crop (card bands), `square` the category's cut tile
    /// (tiles, widgets). The crops are the same picture as the class cards on the site and in the web app.
    enum ClassVariant { case wide, card, square }
    /// Both show the space's lead object. `square` stays for call sites that size the object larger.
    enum SpaceVariant { case square, tile }

    /// Each coach's discipline object (`coachObjects` in objects.ts). Other coaches show their category's object.
    static let coachObjects: [String: String] = [
        "marisol-vega": "spin-bike", "tomas-reyes": "barbell", "aisha-brooks": "mat", "kenji-ito": "jump-rope",
        "dana-whitfield": "wave", "luis-ortega": "pool", "hannah-cole": "cone", "ruth-nakamura": "spa-stones",
        "devon-hart": "barbell", "jamal-carter": "spin-bike", "elise-moreno": "mat", "owen-kim": "medicine-ball",
        "lena-ortiz": "spin-bike", "gabe-santos": "pool", "hector-vance": "wave", "tessa-lund": "kettlebell",
        "sam-okafor": "whistle", "elena-duarte": "barbell", "marcus-hale": "pool", "rosa-lindgren": "resistance-band",
        "jake-whitcomb": "cone", "imani-brooks": "mat", "tess-nakamura": "spin-bike", "ray-delgado": "paddle",
        "nadia-kowalski": "spa-stones",
    ]

    static func object(_ id: String) -> String { "objects-\(id)" }
    static func classGraphic(_ c: ClassCategory, _ v: ClassVariant = .wide) -> String {
        switch v {
        case .wide: "crop-class-\(c.graphicID)-16x9"
        case .card: "crop-class-\(c.graphicID)-2x1"
        case .square: "category-\(c.graphicID)-cut"
        }
    }
    static func space(_ id: SpaceGraphicID, _ v: SpaceVariant = .square) -> String { object(id.lead) }
    /// Each club's Set: three objects taken from what is real there (`clubObjects` in objects.ts).
    static let clubObjects: [String: [String]] = [
        "dobson-southern": ["pool", "paddle", "spa-stones"],
        "power-mckellips": ["stopwatch", "tennis-ball", "sneaker"],
        "main-center": ["dumbbell", "spin-bike", "water-bottle"],
        "val-vista-warner": ["pool", "basketball", "playground"],
        "gilbert-page": ["barbell", "squat-rack", "mat"],
    ]

    /// "Marisol Vega" → "marisol-vega", the slug the coach objects use.
    static func personSlug(_ name: String) -> String {
        name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "en_US")).lowercased()
            .split(separator: " ").joined(separator: "-")
    }
    static func coachObject(name: String, category: ClassCategory) -> String {
        object(coachObjects[personSlug(name)] ?? category.objectID)
    }
}

/// A brand graphic that fills its frame. A Rack is composed for the ratio of its variant;
/// `scaledToFill` crops the edges a little if the frame differs, and never stretches.
struct BrandGraphicImage: View {
    var name: String
    var body: some View {
        Color.clear
            .overlay { Image(name).resizable().scaledToFill() }
            .clipped()
            .accessibilityHidden(true)
    }
}

/// One gym object, whole and centred in its frame. Bare objects are for lists and small tiles (16–48 pt).
struct ObjectImage: View {
    var name: String
    var body: some View {
        Image(name).resizable().scaledToFit().accessibilityHidden(true)
    }
}

/// Class graphic for a category: the category crop for heroes and cards, the cut tile for tiles.
struct ClassGraphic: View {
    var category: ClassCategory
    var variant: BrandImage.ClassVariant = .wide
    var body: some View {
        switch variant {
        case .wide, .card: BrandGraphicImage(name: BrandImage.classGraphic(category, variant))
        case .square: ObjectImage(name: BrandImage.classGraphic(category, .square))
        }
    }
}

/// A space or amenity: its lead object.
struct SpaceGraphic: View {
    var id: SpaceGraphicID
    var variant: BrandImage.SpaceVariant = .tile
    var body: some View { ObjectImage(name: BrandImage.space(id, variant)) }
}

/// A club's Set (VISUAL-IDENTITY.md, section 4): its three objects in a row. Always show the club's name beside it.
/// The app shows no Rack for a club: the name and the facts carry the club, and the Set marks it.
struct ClubSet: View {
    var slug: String
    var size: CGFloat = 24
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1
    var body: some View {
        let s = size * min(scale, 1.4)
        HStack(spacing: s * 0.25) {
            ForEach(BrandImage.clubObjects[slug] ?? [], id: \.self) { id in
                ObjectImage(name: BrandImage.object(id)).frame(width: s, height: s)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A coach: initials on Night with the coach's discipline object as a badge (VISUAL-IDENTITY.md, section 8), as on
/// the marketing site and the web app. The badge shows from 40 pt; below that the initials alone stay readable.
/// A real headshot replaces this when one exists.
struct CoachImage: View {
    var name: String
    var category: ClassCategory
    var size: CGFloat? = 32
    var circle = true
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    private var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    var body: some View {
        let s = (size ?? 32) * min(scale, 1.6)
        let shape = circle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        ZStack {
            shape.fill(Color.nightSurface)
            Text(initials).monogramFont(diameter: s).foregroundStyle(Color.nightOnSurface)
        }
        .frame(width: s, height: s)
        .overlay(alignment: .bottomTrailing) {
            if s >= 40 {
                ObjectImage(name: BrandImage.coachObject(name: name, category: category))
                    .padding(s * 0.07)
                    .frame(width: s * 0.45, height: s * 0.45)
                    .background(Color.surface, in: Circle())
                    .overlay(Circle().strokeBorder(Color.appBackground, lineWidth: 2))
                    .offset(x: 4, y: 4)
            }
        }
        .accessibilityHidden(true)
    }
}
