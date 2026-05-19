import Foundation
import CommonCrypto
#if canImport(IOKit)
import IOKit
#endif

/// Thin HTTPS client for the Pro RU activation server. The server contract is
/// documented in `docs/SERVER_API.md` — change both together.
public final class LicenseClient {
    public static let shared = LicenseClient()

    private let session: URLSession
    private let timeout: TimeInterval

    public init(session: URLSession = .shared, timeout: TimeInterval = 15) {
        self.session = session
        self.timeout = timeout
    }

    // MARK: - Public API

    /// Send the user-entered license key to the server and persist the
    /// returned record on success. Throws `LicenseError` on any failure.
    @discardableResult
    public func activate(licenseKey: String) async throws -> LicenseRecord {
        let trimmed = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LicenseError.invalidKey }

        let body = ActivateRequest(
            licenseKey: trimmed,
            fingerprint: Self.machineFingerprint(),
            deviceId: LicenseManager.shared.deviceId,
            appVersion: Dikto.version,
            os: Self.osVersion()
        )

        let response: ActivateResponse = try await post(path: "/v1/activate", body: body)
        let record = LicenseRecord(
            licenseKey: trimmed,
            token: response.token,
            plan: response.plan,
            expiresAt: response.expiresAt,
            lastValidatedAt: Date()
        )
        try LicenseManager.shared.install(record: record)
        return record
    }

    /// Refresh the cached record from the server. Called on a 7-day cadence
    /// from `LicenseManager.needsRevalidation`. Silent on network errors —
    /// we don't want a flaky Wi-Fi to lock paying users out.
    public func validateIfPossible() async {
        guard let record = LicenseManager.shared.currentRecord else { return }
        do {
            let response: ValidateResponse = try await get(
                path: "/v1/validate",
                token: record.token,
                query: ["deviceId": LicenseManager.shared.deviceId]
            )
            if response.valid {
                let updated = LicenseRecord(
                    licenseKey: record.licenseKey,
                    token: record.token,
                    plan: record.plan,
                    expiresAt: response.expiresAt ?? record.expiresAt,
                    lastValidatedAt: Date()
                )
                try? LicenseManager.shared.install(record: updated)
            } else {
                // Server explicitly invalidated the license (refund, revoke).
                LicenseManager.shared.clear()
            }
        } catch {
            // Network failure — keep last known good state. Caller decides
            // whether to surface anything to the user.
            NSLog("[License] validation skipped: %@", error.localizedDescription)
        }
    }

    // MARK: - HTTP plumbing

    private func post<Body: Encodable, Response: Decodable>(path: String, body: Body) async throws -> Response {
        var url = ProductFlavor.current.licenseServerURL
        url.appendPathComponent(path)

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Dikto/\(Dikto.version)", forHTTPHeaderField: "User-Agent")

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        req.httpBody = try enc.encode(body)

        return try await send(req)
    }

    private func get<Response: Decodable>(path: String, token: String, query: [String: String]) async throws -> Response {
        var url = ProductFlavor.current.licenseServerURL
        url.appendPathComponent(path)
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        var req = URLRequest(url: components.url!)
        req.httpMethod = "GET"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("Dikto/\(Dikto.version)", forHTTPHeaderField: "User-Agent")
        return try await send(req)
    }

    private func send<Response: Decodable>(_ req: URLRequest) async throws -> Response {
        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await session.data(for: req)
        } catch {
            throw LicenseError.network(error.localizedDescription)
        }

        guard let http = resp as? HTTPURLResponse else {
            throw LicenseError.network("invalid response")
        }

        if http.statusCode == 402 {
            let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
            switch envelope?.error {
            case "invalid_key": throw LicenseError.invalidKey
            case "device_limit": throw LicenseError.deviceLimitReached
            default: throw LicenseError.server(code: 402, message: envelope?.message ?? "payment required")
            }
        }

        guard (200..<300).contains(http.statusCode) else {
            let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
            throw LicenseError.server(code: http.statusCode, message: envelope?.message ?? "HTTP \(http.statusCode)")
        }

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try dec.decode(Response.self, from: data)
    }

    // MARK: - Fingerprint

    /// Stable, anonymous machine fingerprint. SHA-256 of the IOPlatformUUID,
    /// hex-encoded. We deliberately hash so the raw UUID never leaves the
    /// device — the server only ever sees an opaque ID it cannot reverse.
    static func machineFingerprint() -> String {
        let raw = platformUUID() ?? FallbackFingerprint.value
        return sha256Hex(raw)
    }

    private static func platformUUID() -> String? {
        #if canImport(IOKit)
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        let key = "IOPlatformUUID" as CFString
        guard let property = IORegistryEntryCreateCFProperty(service, key, kCFAllocatorDefault, 0) else {
            return nil
        }
        return (property.takeRetainedValue() as? String)
        #else
        return nil
        #endif
    }

    private static func osVersion() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    private static func sha256Hex(_ input: String) -> String {
        var hash = [UInt8](repeating: 0, count: 32)
        let data = Array(input.utf8)
        Self.sha256(data, &hash)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    /// Lightweight SHA-256 using CommonCrypto. We avoid CryptoKit so the file
    /// keeps building on every supported toolchain without extra imports.
    private static func sha256(_ data: [UInt8], _ out: inout [UInt8]) {
        let len = CC_LONG(data.count)
        _ = data.withUnsafeBufferPointer { buf in
            CC_SHA256(buf.baseAddress, len, &out)
        }
    }
}

// MARK: - DTOs

struct ActivateRequest: Encodable {
    let licenseKey: String
    let fingerprint: String
    let deviceId: String
    let appVersion: String
    let os: String
}

struct ActivateResponse: Decodable {
    let token: String
    let plan: String
    let expiresAt: Date?
    let deviceId: String?
}

struct ValidateResponse: Decodable {
    let valid: Bool
    let expiresAt: Date?
    let reason: String?
}

struct ErrorEnvelope: Decodable {
    let error: String?
    let message: String?
}

private enum FallbackFingerprint {
    /// Used only when `IOPlatformUUID` is unavailable (extremely unusual on
    /// macOS — sandboxed test runner, etc). Stable for the lifetime of the
    /// user account so activations don't move every launch.
    static let value: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "fallback:\(home)"
    }()
}
