import Foundation
import Security

/// The running process's own code-signing identity. The app shows this so you
/// can see *which* identity holds the TCC (Screen Recording / Accessibility)
/// grant — the whole reason for shipping a signed bundle (issue Part 2/3): a
/// stable cdhash means the grant survives rebuilds.
public struct CodeIdentity: Sendable {
    /// Designated requirement identifier (the signing identifier, usually the
    /// bundle id), or nil if unsigned.
    public let identifier: String?
    /// The canonical cdhash, hex-encoded, or nil if unsigned/ad-hoc without one.
    public let cdhash: String?
    /// True if the signature is ad-hoc (cdhash changes every rebuild → TCC
    /// re-prompts every build).
    public let isAdHoc: Bool

    /// Inspect the current process.
    public static func current() -> CodeIdentity {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else {
            return CodeIdentity(identifier: nil, cdhash: nil, isAdHoc: true)
        }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
            let staticCode
        else {
            return CodeIdentity(identifier: nil, cdhash: nil, isAdHoc: true)
        }

        var infoCF: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSInternalInformation | kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &infoCF) == errSecSuccess,
            let info = infoCF as? [String: Any]
        else {
            return CodeIdentity(identifier: nil, cdhash: nil, isAdHoc: true)
        }

        let identifier = info[kSecCodeInfoIdentifier as String] as? String
        let cdhashData = info[kSecCodeInfoUnique as String] as? Data
        let cdhash = cdhashData?.map { String(format: "%02x", $0) }.joined()

        // The signer flags tell us ad-hoc: a real identity yields a certificate
        // chain; ad-hoc has none.
        let certs = info[kSecCodeInfoCertificates as String] as? [Any]
        let isAdHoc = (certs?.isEmpty ?? true)

        return CodeIdentity(identifier: identifier, cdhash: cdhash, isAdHoc: isAdHoc)
    }
}
