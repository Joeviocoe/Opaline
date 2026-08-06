import UIKit

// MARK: - Category definition (data-driven)

/// All attributes of a single SponsorBlock category.
/// Adding a category = adding one entry to
/// `SBCategory.catalog`.
private struct SBCategoryDefinition {
    let seekBarColor: UIColor
    let defaultSkipBehavior: SBSkipBehavior
    /// Whether auto-skip is valid for this category.
    let canAutoSkip: Bool
    /// Whether a manual skip button makes sense.
    let canShowButton: Bool

    init(
        _ hex: String,
        behavior: SBSkipBehavior = .disabled,
        canAutoSkip: Bool = true,
        canShowButton: Bool = true
    ) {
        seekBarColor        = UIColor(sbHex: hex)
        defaultSkipBehavior = behavior
        self.canAutoSkip    = canAutoSkip
        self.canShowButton  = canShowButton
    }
}

// MARK: - Category

enum SBCategory: String, CaseIterable {
    case sponsor = "sponsor"
    case selfpromo = "selfpromo"
    case exclusiveAccess = "exclusive_access"
    case interaction = "interaction"
    case highlight = "highlight"
    case intro = "intro"
    case outro = "outro"
    case preview = "preview"
    case filler = "filler"
    case musicOfftopic = "music_offtopic"
    case chapter = "chapter"

    // MARK: Catalog

    private static let catalog: [SBCategory: SBCategoryDefinition] = {
        typealias Def = SBCategoryDefinition
        return [
            .sponsor: Def("#00d400", behavior: .autoSkip),
            .selfpromo: Def("#ffff00"),
            .exclusiveAccess: Def(
                "#008000", canAutoSkip: false, canShowButton: false
            ),
            .interaction: Def("#cc00ff"),
            .highlight: Def("#ff1684"),
            .intro: Def("#00ffff"),
            .outro: Def("#0202ed"),
            .preview: Def("#008fd6"),
            .filler: Def("#7300ab"),
            .musicOfftopic: Def("#ff9900"),
            .chapter: Def(
                "#feff01", canAutoSkip: false, canShowButton: false
            )
        ]
    }()

    // MARK: Derived properties

    private var info: SBCategoryDefinition {
        guard let definition = Self.catalog[self] else {
            fatalError("Missing catalog entry for \(self)")
        }
        return definition
    }

    /// Name/description come from Localizable.strings, keyed by rawValue —
    /// the catalog only carries non-translatable attributes.
    var displayName: String {
        "sponsorblock.category.\(rawValue).name".localized
    }
    var categoryDescription: String {
        "sponsorblock.category.\(rawValue).description".localized
    }
    var seekBarColor: UIColor { info.seekBarColor }
    var defaultSkipBehavior: SBSkipBehavior { info.defaultSkipBehavior }
    var canAutoSkip: Bool { info.canAutoSkip }
    var canShowButton: Bool { info.canShowButton }
}

// MARK: - Skip behavior

enum SBSkipBehavior: String {
    case autoSkip   = "auto_skip"
    case showButton = "show_button"
    case disabled   = "disabled"

    var displayName: String {
        switch self {
        case .autoSkip:
            return "sponsorblock.behavior.autoSkip".localized
        case .showButton:
            return "sponsorblock.behavior.showButton".localized
        case .disabled:
            return "sponsorblock.behavior.disabled".localized
        }
    }

    static func options(
        for category: SBCategory
    ) -> [SBSkipBehavior] {
        if category.canAutoSkip {
            return [.autoSkip, .showButton, .disabled]
        }
        if category.canShowButton {
            return [.showButton, .disabled]
        }
        return [.disabled]
    }
}

// MARK: - UIColor hex helper

extension UIColor {
    /// Initialise from a CSS hex string, e.g. "#00d400".
    convenience init(sbHex: String) {
        var hex = sbHex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex = String(hex.dropFirst()) }
        var rgb: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgb)
        let red = CGFloat((rgb >> 16) & 0xFF) / 255
        let green = CGFloat((rgb >> 8) & 0xFF) / 255
        let blue = CGFloat(rgb & 0xFF) / 255
        self.init(red: red, green: green, blue: blue, alpha: 1)
    }
}
