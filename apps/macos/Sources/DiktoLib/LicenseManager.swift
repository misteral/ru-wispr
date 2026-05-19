import Foundation
import Security

/// State of the Pro RU license. Free flavor always returns `.notRequired`.
public enum LicenseStatus: Equatable {
    /// Free flavor — licensing not applicable. Hotkey always works.
    case notRequired

    /// Trial running. `daysLeft` is integer-rounded, never negative; 0 means
    /// the trial ends today.
    case trial(daysLeft: Int)

    /// Activated license is valid and inside its server-issued window.
    case active(expiresAt: Date?)

    /// Trial ran out and no valid license is installed. Hotkey is blocked,
    /// activation window is forced.
    case trialExpired

    /// A license was installed but server validation rejected it (refund,
    /// device-limit exceeded, etc). Hotkey is blocked, activation window
    /// shows the reason and lets the user enter a new key.
    case invalid(reason: String)

    public var allowsRecording: Bool {
        switch self {
        case .notRequired, .trial, .active: return true
        case .trialExpired, .invalid: return false
        }
    }
}

/// On-disk schema of the trial / activation state file. Stored in
/// `~/Library/Application Support/Dikto/license.json`. We keep this minimal —
/// the license token itself goes in Keychain, the file only stores the trial
/// seed and last-seen wall-clock time for clock-rollback defence.
struct LicenseFile: Codable {
    var trialStart: Date
    var lastSeen: Date
    var deviceId: String

    init(now: Date) {
        self.trialStart = now
        self.lastSeen = now
        self.deviceId = UUID().uuidString
    }
}

/// In-Keychain record of an activated license. We re-validate against the
/// server on a schedule; until then this is treated as the source of truth.
public struct LicenseRecord: Codable, Equatable {
    public var licenseKey: String
    public var token: String
    public var plan: String
    public var expiresAt: Date?
    public var lastValidatedAt: Date

    public init(licenseKey: String, token: String, plan: String, expiresAt: Date?, lastValidatedAt: Date) {
        self.licenseKey = licenseKey
        self.token = token
        self.plan = plan
        self.expiresAt = expiresAt
        self.lastValidatedAt = lastValidatedAt
    }
}

/// Coordinates trial countdown and activated-license storage. Single-instance
/// (`shared`); read `status` whenever the UI needs to know what to display.
public final class LicenseManager {
    public static let shared = LicenseManager()

    /// Re-validate the activated license at most once per this interval. Keeps
    /// us off the network when the user is offline for a few days but ensures
    /// refunds/revocations get picked up eventually.
    public static let revalidateInterval: TimeInterval = 7 * 24 * 3600

    private let queue = DispatchQueue(label: "co.itbeaver.dikto.license", qos: .utility)
    private let keychainService = "co.itbeaver.dikto.license"
    private let keychainAccount = "current"

    private var cachedFile: LicenseFile?
    private var cachedRecord: LicenseRecord?

    private init() {}

    // MARK: - Public API

    public var status: LicenseStatus {
        if !ProductFlavor.current.requiresLicense { return .notRequired }
        return queue.sync { computeStatusLocked() }
    }

    /// Persistent, anonymous machine identifier used as the activation
    /// fingerprint. Stable across launches, not tied to user identity, opaque
    /// to the server.
    public var deviceId: String {
        queue.sync {
            let file = ensureFileLocked()
            return file.deviceId
        }
    }

    /// Persist a freshly issued license. Called from `LicenseClient` after a
    /// successful `POST /v1/activate`.
    public func install(record: LicenseRecord) throws {
        try queue.sync {
            try writeKeychainLocked(record: record)
            cachedRecord = record
        }
    }

    /// Drop the activated license. Used when server returns 401/403 on
    /// validation, or when the user manually deactivates.
    public func clear() {
        queue.sync {
            deleteKeychainLocked()
            cachedRecord = nil
        }
    }

    /// Update the "last seen" timestamp. Call this on every successful run so
    /// we can detect users who wind their system clock back during the trial.
    public func touch(now: Date = Date()) {
        queue.sync {
            var file = ensureFileLocked()
            if now > file.lastSeen {
                file.lastSeen = now
                try? writeFileLocked(file)
                cachedFile = file
            }
        }
    }

    /// True when a server re-check is due. UI code uses this to decide
    /// whether to fire `LicenseClient.validate` on launch.
    public var needsRevalidation: Bool {
        queue.sync {
            guard let record = loadKeychainLocked() else { return false }
            return Date().timeIntervalSince(record.lastValidatedAt) >= LicenseManager.revalidateInterval
        }
    }

    public var currentRecord: LicenseRecord? {
        queue.sync { loadKeychainLocked() }
    }

    // MARK: - Status computation (queue-private)

    private func computeStatusLocked() -> LicenseStatus {
        // 1. Activated license takes precedence over the trial.
        if let record = loadKeychainLocked() {
            if let expiry = record.expiresAt, expiry < Date() {
                return .invalid(reason: "expired")
            }
            return .active(expiresAt: record.expiresAt)
        }

        // 2. Fall back to trial. We compute daysLeft from the maximum of
        //    `trialStart + trialDays` and `lastSeen`: this way, winding the
        //    clock back only freezes the trial, it never extends it.
        let file = ensureFileLocked()
        let now = Date()
        let effectiveNow = max(now, file.lastSeen)
        let trialDays = TimeInterval(ProductFlavor.current.trialDays)
        let trialEnd = file.trialStart.addingTimeInterval(trialDays * 24 * 3600)
        if effectiveNow >= trialEnd { return .trialExpired }
        let secondsLeft = trialEnd.timeIntervalSince(effectiveNow)
        let daysLeft = Int(ceil(secondsLeft / (24 * 3600)))
        return .trial(daysLeft: max(0, daysLeft))
    }

    // MARK: - File storage (queue-private)

    private static var fileURL: URL {
        Config.dataDir.appendingPathComponent("license.json")
    }

    private func ensureFileLocked() -> LicenseFile {
        if let cached = cachedFile { return cached }
        if let loaded = try? loadFileLocked() {
            cachedFile = loaded
            return loaded
        }
        let fresh = LicenseFile(now: Date())
        try? writeFileLocked(fresh)
        cachedFile = fresh
        return fresh
    }

    private func loadFileLocked() throws -> LicenseFile {
        let data = try Data(contentsOf: LicenseManager.fileURL)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try dec.decode(LicenseFile.self, from: data)
    }

    private func writeFileLocked(_ file: LicenseFile) throws {
        try FileManager.default.createDirectory(at: Config.dataDir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = .prettyPrinted
        enc.dateEncodingStrategy = .iso8601
        let data = try enc.encode(file)
        try data.write(to: LicenseManager.fileURL, options: .atomic)
    }

    // MARK: - Keychain storage (queue-private)

    private func keychainQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
    }

    private func loadKeychainLocked() -> LicenseRecord? {
        if let cached = cachedRecord { return cached }
        var query = keychainQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let result = SecItemCopyMatching(query as CFDictionary, &item)
        guard result == errSecSuccess, let data = item as? Data else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let record = try? dec.decode(LicenseRecord.self, from: data) else { return nil }
        cachedRecord = record
        return record
    }

    private func writeKeychainLocked(record: LicenseRecord) throws {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        let data = try enc.encode(record)

        // Update if exists, add if not.
        var updateQuery = keychainQuery()
        let updateAttrs: [String: Any] = [kSecValueData as String: data]
        let updateResult = SecItemUpdate(updateQuery as CFDictionary, updateAttrs as CFDictionary)
        if updateResult == errSecItemNotFound {
            updateQuery[kSecValueData as String] = data
            updateQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addResult = SecItemAdd(updateQuery as CFDictionary, nil)
            if addResult != errSecSuccess {
                throw LicenseError.keychainWriteFailed(addResult)
            }
        } else if updateResult != errSecSuccess {
            throw LicenseError.keychainWriteFailed(updateResult)
        }
    }

    private func deleteKeychainLocked() {
        SecItemDelete(keychainQuery() as CFDictionary)
    }
}

public enum LicenseError: Error, LocalizedError {
    case keychainWriteFailed(OSStatus)
    case network(String)
    case invalidKey
    case deviceLimitReached
    case server(code: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .keychainWriteFailed(let s):
            return "Keychain write failed: \(s)"
        case .network(let msg):
            return msg
        case .invalidKey:
            return L10n.licenseInvalidKey
        case .deviceLimitReached:
            return L10n.licenseDeviceLimit
        case .server(_, let msg):
            return msg
        }
    }
}

// MARK: - Testing hooks

#if DEBUG
extension LicenseManager {
    /// Reset state for tests. Not used in shipping code.
    public func _resetForTests() {
        queue.sync {
            cachedFile = nil
            cachedRecord = nil
            try? FileManager.default.removeItem(at: LicenseManager.fileURL)
            deleteKeychainLocked()
        }
    }

    public func _seedTrial(start: Date, lastSeen: Date) {
        queue.sync {
            var file = LicenseFile(now: start)
            file.trialStart = start
            file.lastSeen = lastSeen
            try? writeFileLocked(file)
            cachedFile = file
        }
    }

    public func _statusForTesting() -> LicenseStatus {
        queue.sync { computeStatusLocked() }
    }
}
#endif
