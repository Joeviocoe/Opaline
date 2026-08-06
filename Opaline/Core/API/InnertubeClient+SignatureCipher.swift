import Foundation

// MARK: - signatureCipher unwrapping (mweb)
//
// Some videos (kids content in particular) arrive with every format's URL
// wrapped in a `signatureCipher` — `s=<challenge>&sp=<param>&url=<escaped>` —
// instead of a direct `url`. Unwrapping moves the URL into `url` (so format
// selection works unchanged) and stashes the challenge under synthetic keys
// that `makeDashInfo` copies into `DashFormatInfo.sigChallenge`/`sigParam`;
// the playback source must solve the challenge (same EJS solver as `n`) and
// append `<sp>=<solved>` before the URL is playable.

extension InnertubeClient {
    static let sigChallengeKey = "ytliteSigChallenge"
    static let sigParamKey = "ytliteSigParam"

    static func unwrappingSignatureCiphers(
        _ json: [String: Any]
    ) -> [String: Any] {
        guard var sd = json["streamingData"] as? [String: Any] else {
            return json
        }
        for key in ["formats", "adaptiveFormats"] {
            if let formats = sd[key] as? [[String: Any]] {
                sd[key] = formats.map(unwrapSignatureCipher)
            }
        }
        var out = json
        out["streamingData"] = sd
        return out
    }

    private static func unwrapSignatureCipher(
        _ fmt: [String: Any]
    ) -> [String: Any] {
        guard fmt["url"] == nil,
              let cipher = fmt["signatureCipher"] as? String else {
            return fmt
        }
        var components = URLComponents()
        components.percentEncodedQuery = cipher
        let items = components.queryItems ?? []
        guard let url = cipherValue(items, "url"),
              let challenge = cipherValue(items, "s") else {
            return fmt
        }
        var out = fmt
        out["url"] = url
        out[sigChallengeKey] = challenge
        out[sigParamKey] = cipherValue(items, "sp") ?? "signature"
        return out
    }

    private static func cipherValue(
        _ items: [URLQueryItem], _ name: String
    ) -> String? {
        items.first { $0.name == name }?.value
    }
}
