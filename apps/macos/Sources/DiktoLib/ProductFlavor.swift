import Foundation

/// Compile-time product variant. `Dikto Pro RU` is selected by passing
/// `-D DIKTO_PRO_RU` to the Swift compiler (handled in `Package.swift` when
/// the `DIKTO_FLAVOR=pro_ru` env var is set). All Pro RU specifics — display
/// name, bundle ID, forced UI language, license gating, support URLs — live
/// here so the rest of the code reads them through one enum.
public enum ProductFlavor {
    case free
    case proRU

    public static let current: ProductFlavor = {
        #if DIKTO_PRO_RU
        return .proRU
        #else
        return .free
        #endif
    }()

    /// Display name used in menu bar, alerts, About dialog.
    public var displayName: String {
        switch self {
        case .free: return "Dikto"
        case .proRU: return "Dikto Pro"
        }
    }

    /// Bundle identifier. Must match `Info.plist` in the corresponding DMG
    /// build script, otherwise TCC permissions break.
    public var bundleId: String {
        switch self {
        case .free: return "co.itbeaver.dikto"
        case .proRU: return "ru.diktopro"
        }
    }

    /// If non-nil, UI ignores `config.language` and uses this value.
    /// Pro RU is Russian-only by design.
    public var forcedLanguage: String? {
        switch self {
        case .free: return nil
        case .proRU: return "ru"
        }
    }

    public var requiresLicense: Bool {
        switch self {
        case .free: return false
        case .proRU: return true
        }
    }

    public var trialDays: Int { 14 }

    /// Website shown to users who want to buy. Resolves to the production
    /// landing page; overridable via `DIKTO_BUY_URL` build env var for staging.
    public var buyURL: URL {
        if case .proRU = self,
           let override = Bundle.main.object(forInfoDictionaryKey: "DIKTOBuyURL") as? String,
           let url = URL(string: override) {
            return url
        }
        return URL(string: "https://dikto.itbeaver.co/buy")!
    }

    public var supportURL: URL {
        switch self {
        case .free: return URL(string: "https://github.com/misteral/dikto/issues")!
        case .proRU: return URL(string: "https://dikto.itbeaver.co/support")!
        }
    }

    /// Base URL of the activation server. Set via `Info.plist` key `DIKTOLicenseServer`
    /// during release builds so we can flip between staging and prod without
    /// recompiling Swift.
    public var licenseServerURL: URL {
        if let override = Bundle.main.object(forInfoDictionaryKey: "DIKTOLicenseServer") as? String,
           let url = URL(string: override) {
            return url
        }
        return URL(string: "https://api.dikto.itbeaver.co")!
    }
}
