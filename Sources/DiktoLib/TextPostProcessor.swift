import Foundation

public struct TextPostProcessor {
    private static let replacements: [(pattern: String, replacement: String)] = [
        ("\\bperiod\\b", "."),
        ("\\bfull stop\\b", "."),
        ("\\b[ck]a?r?ma\\b", ","),
        ("\\bcomma\\b", ","),
        ("\\bquestion mark\\b", "?"),
        ("\\bexclamation mark\\b", "!"),
        ("\\bexclamation point\\b", "!"),
        ("\\bcolon\\b", ":"),
        ("\\bsemicolon\\b", ";"),
        ("\\bsemi colon\\b", ";"),
        ("\\bellipsis\\b", "..."),
        ("\\bdash\\b", " —"),
        ("\\bhyphen\\b", "-"),
        ("\\bopen quote\\b", "\""),
        ("\\bclose quote\\b", "\""),
        ("\\bopen paren\\b", "("),
        ("\\bclose paren\\b", ")"),
        ("\\bnew line\\b", "\n"),
        ("\\bnewline\\b", "\n"),
        ("\\bnew paragraph\\b", "\n\n"),
    ]

    public static func process(_ text: String) -> String {
        var result = text
        for (pattern, replacement) in replacements {
            guard let regex = try? Regex(pattern).ignoresCase() else { continue }
            result = result.replacing(regex, with: replacement)
        }
        result = fixSpacingAroundPunctuation(result)
        result = ensureSpaceAfterPunctuation(result)
        return result
    }

    private static func fixSpacingAroundPunctuation(_ text: String) -> String {
        text.replacing(#/\s+([.,?!:;])/#) { match in
            String(match.1)
        }
    }

    private static func ensureSpaceAfterPunctuation(_ text: String) -> String {
        text.replacing(#/([.,?!:;])(\w)/#) { match in
            "\(match.1) \(match.2)"
        }
    }
}
