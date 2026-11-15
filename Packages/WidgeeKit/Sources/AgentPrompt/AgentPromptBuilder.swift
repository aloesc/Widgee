import Foundation
import WidgeeCore

/// Builds the prompt for an AI agent from the bundled template.
public enum AgentPromptBuilder {
    /// Shown instead of the description when the user typed nothing.
    public static let emptyRequestHint = "(The user has not described the widget yet. Ask the user what the widget should show before writing any files.)"

    public static var template: String { resource("AGENT_PROMPT", "md") }
    static var sdkTypes: String { resource("sdk-index.d", "ts") }
    static var components: String { resource("COMPONENTS", "md") }

    static func resource(_ name: String, _ ext: String) -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Resources")
                ?? Bundle.module.url(forResource: name, withExtension: ext),
              let s = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return s
    }

    /// Single-pass substitution: substituted text is never scanned again, so `{{...}}` in the
    /// user's text stays literal.
    public static func build(request: String, widgetsDirectory: String,
                             sdkVersion: String = WidgeeCore.sdkVersion) -> String {
        let trimmed = request.trimmingCharacters(in: .whitespacesAndNewlines)
        let values: [String: String] = [
            "WIDGETS_DIR": widgetsDirectory.replacingOccurrences(of: "\"", with: "\\\""),
            "USER_REQUEST": trimmed.isEmpty ? emptyRequestHint : trimmed.replacingOccurrences(of: "<", with: "&lt;"),
            "SDK_VERSION": sdkVersion,
            "SDK_TYPES": sdkTypes.trimmingCharacters(in: .newlines),
            "COMPONENTS": components.trimmingCharacters(in: .newlines),
        ]
        return substitute(template, values)
    }

    static func substitute(_ template: String, _ values: [String: String]) -> String {
        var out = ""
        var rest = Substring(template)
        while let open = rest.range(of: "{{") {
            out += rest[rest.startIndex..<open.lowerBound]
            let after = rest[open.upperBound...]
            if let close = after.range(of: "}}"), let v = values[String(after[after.startIndex..<close.lowerBound])] {
                out += v
                rest = after[close.upperBound...]
            } else {
                out += "{{"
                rest = after
            }
        }
        return out + rest
    }
}
