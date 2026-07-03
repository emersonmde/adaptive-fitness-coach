import Foundation

/// Whether this build may touch `PrivateCloudComputeLanguageModel` at all.
///
/// PCC access is a **gated capability** (Small Business Program eligibility + an entitlement
/// Apple assigns to the account) — and the framework does not degrade: instantiating the PCC
/// model in a process without `com.apple.developer.private-cloud-compute` is a **fatal error**,
/// not an `.unavailable` (observed on device, iOS 27.0: "Process is missing required
/// entitlement", SIGTRAP). Discovered by the P4 LookupLab spike; it would equally have crashed
/// the P3 coach on first device use.
///
/// Detection: the embedded provisioning profile lists the app's granted entitlements in
/// plaintext inside its CMS envelope. Debug and TestFlight builds carry
/// `embedded.mobileprovision`; App Store builds don't — there we conservatively answer
/// *false* (revisit when the account actually holds the grant; on-device Apple Intelligence
/// remains the engine either way).
enum PCCEntitlement {

    static let isGranted: Bool = {
        guard let profileURL = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: profileURL) else {
            return false
        }
        // The profile is DER/CMS-wrapped XML; the entitlement key appears verbatim when granted.
        guard let text = String(data: data, encoding: .isoLatin1) else { return false }
        guard let keyRange = text.range(of: "com.apple.developer.private-cloud-compute") else {
            return false
        }
        // `<key>…</key><true/>` — confirm the value is true, not an explicit false.
        let tail = text[keyRange.upperBound...].prefix(64)
        return tail.contains("<true/>")
    }()
}
