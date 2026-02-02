@preconcurrency import MarkdownUI
import SwiftUI

// MARK: - Pi Island Markdown Theme

extension Theme {
    /// Dark theme optimized for Pi Island's notch panel UI
    @MainActor static let piIsland = Theme()
        .text {
            ForegroundColor(.white.opacity(0.9))
            FontSize(13) // Increased from 11
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(11) // Increased from 10
            ForegroundColor(.cyan.opacity(0.9))
        }
        .strong {
            FontWeight(.semibold)
        }
        .link {
            ForegroundColor(.blue.opacity(0.8))
        }
        .heading1 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(15) // Increased from 14
                    ForegroundColor(.white)
                }
                .padding(.bottom, 6) // Increased padding
        }
        .heading2 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(14) // Increased from 13
                    ForegroundColor(.white.opacity(0.95))
                }
                .padding(.bottom, 4)
        }
        .heading3 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.medium)
                    FontSize(13) // Increased from 12
                    ForegroundColor(.white.opacity(0.9))
                }
                .padding(.bottom, 3)
        }
        .paragraph { configuration in
            configuration.label
                .padding(.vertical, 2)
        }
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: 2, bottom: 2)
        }
        .codeBlock { configuration in
            PiCodeBlockView(configuration: configuration)
        }
        .blockquote { configuration in
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 3)
                configuration.label
                    .markdownTextStyle {
                        ForegroundColor(.white.opacity(0.7))
                        FontSize(10)
                    }
                    .padding(.leading, 8)
            }
            .padding(.vertical, 4)
        }
}

// MARK: - Code Block View with Syntax Highlighting

struct PiCodeBlockView: View {
    let configuration: CodeBlockConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Language header
            if let language = configuration.language, !language.isEmpty {
                HStack {
                    Text(language)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    Button(action: copyCode) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.08))
            }

            // Code content with line numbers
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    // Line numbers
                    VStack(alignment: .trailing, spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, _ in
                            Text("\(index + 1)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.25))
                                .frame(height: lineHeight)
                        }
                    }
                    .padding(.trailing, 8)
                    .padding(.leading, 8)

                    Divider()
                        .frame(width: 1)
                        .background(Color.white.opacity(0.1))

                    // Code lines with syntax highlighting
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            highlightedLine(line)
                                .frame(height: lineHeight, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .padding(.vertical, 6)
            }
        }
        .background(Color.black.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private var lines: [String] {
        configuration.content.components(separatedBy: "\n")
    }

    private var lineHeight: CGFloat { 15 }

    private var language: String {
        configuration.language ?? ""
    }

    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(configuration.content, forType: .string)
    }

    // MARK: - Syntax Highlighting

    @ViewBuilder
    private func highlightedLine(_ line: String) -> some View {
        Text(attributedLine(line))
            .font(.system(size: 11, design: .monospaced)) // Explicit system mono font, size 11
    }

    private func attributedLine(_ line: String) -> AttributedString {
        var result = AttributedString(line)
        result.foregroundColor = .white.opacity(0.85)

        // Apply syntax highlighting based on language
        applyHighlighting(to: &result, line: line)

        return result
    }

    private func applyHighlighting(to result: inout AttributedString, line: String) {
        let lang = language.lowercased()

        // Keywords by language family
        let keywords: [String]
        let typeKeywords: [String]

        switch lang {
        case "swift":
            keywords = ["func", "var", "let", "if", "else", "guard", "return", "import", "struct", "class", "enum", "protocol", "extension", "private", "public", "internal", "fileprivate", "static", "override", "mutating", "throws", "async", "await", "try", "catch", "for", "while", "switch", "case", "default", "break", "continue", "where", "in", "self", "Self", "nil", "true", "false", "@State", "@Binding", "@Observable", "@MainActor", "some", "any", "init", "deinit"]
            typeKeywords = ["String", "Int", "Bool", "Double", "Float", "Array", "Dictionary", "Set", "Optional", "Result", "View", "Text", "VStack", "HStack", "ZStack", "Button", "Image", "Color"]
        case "python", "py":
            keywords = ["def", "class", "if", "elif", "else", "for", "while", "return", "import", "from", "as", "try", "except", "finally", "with", "lambda", "yield", "raise", "pass", "break", "continue", "and", "or", "not", "in", "is", "None", "True", "False", "self", "async", "await"]
            typeKeywords = ["str", "int", "float", "bool", "list", "dict", "set", "tuple", "type"]
        case "javascript", "js", "typescript", "ts":
            keywords = ["function", "const", "let", "var", "if", "else", "return", "import", "export", "from", "class", "extends", "new", "this", "try", "catch", "finally", "throw", "async", "await", "for", "while", "switch", "case", "default", "break", "continue", "typeof", "instanceof", "null", "undefined", "true", "false"]
            typeKeywords = ["string", "number", "boolean", "object", "Array", "Promise", "void", "any", "never"]
        case "rust", "rs":
            keywords = ["fn", "let", "mut", "const", "if", "else", "match", "loop", "while", "for", "in", "return", "break", "continue", "struct", "enum", "impl", "trait", "pub", "use", "mod", "self", "Self", "true", "false", "async", "await", "move", "ref", "where"]
            typeKeywords = ["String", "str", "i32", "i64", "u32", "u64", "f32", "f64", "bool", "Vec", "Option", "Result", "Box", "Rc", "Arc"]
        case "go":
            keywords = ["func", "var", "const", "if", "else", "for", "range", "return", "switch", "case", "default", "break", "continue", "type", "struct", "interface", "map", "chan", "go", "defer", "select", "package", "import", "nil", "true", "false"]
            typeKeywords = ["string", "int", "int32", "int64", "float32", "float64", "bool", "byte", "rune", "error"]
        case "bash", "sh", "zsh", "shell":
            keywords = ["if", "then", "else", "elif", "fi", "for", "do", "done", "while", "case", "esac", "function", "return", "exit", "export", "local", "readonly", "declare", "source", "alias", "echo", "cd", "ls", "rm", "cp", "mv", "mkdir", "cat", "grep", "sed", "awk", "find", "xargs"]
            typeKeywords = []
        default:
            // Generic highlighting
            keywords = ["if", "else", "for", "while", "return", "function", "class", "import", "export", "true", "false", "null", "nil"]
            typeKeywords = []
        }

        // Apply keyword highlighting
        for keyword in keywords {
            highlightPattern(in: &result, line: line, pattern: "\\b\(keyword)\\b", color: .pink.opacity(0.9))
        }

        // Apply type highlighting
        for type in typeKeywords {
            highlightPattern(in: &result, line: line, pattern: "\\b\(type)\\b", color: .cyan.opacity(0.9))
        }

        // Strings (double and single quoted)
        highlightPattern(in: &result, line: line, pattern: "\"[^\"]*\"", color: .green.opacity(0.9))
        highlightPattern(in: &result, line: line, pattern: "'[^']*'", color: .green.opacity(0.9))

        // Numbers
        highlightPattern(in: &result, line: line, pattern: "\\b\\d+(\\.\\d+)?\\b", color: .orange.opacity(0.9))

        // Comments (single line)
        highlightPattern(in: &result, line: line, pattern: "//.*$", color: .white.opacity(0.4))
        highlightPattern(in: &result, line: line, pattern: "#.*$", color: .white.opacity(0.4))
    }

    private func highlightPattern(in result: inout AttributedString, line: String, pattern: String, color: Color) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        let range = NSRange(line.startIndex..., in: line)
        let matches = regex.matches(in: line, options: [], range: range)

        for match in matches {
            guard let swiftRange = Range(match.range, in: line) else { continue }
            let startOffset = line.distance(from: line.startIndex, to: swiftRange.lowerBound)
            let endOffset = line.distance(from: line.startIndex, to: swiftRange.upperBound)

            let attrStart = result.index(result.startIndex, offsetByCharacters: startOffset)
            let attrEnd = result.index(result.startIndex, offsetByCharacters: endOffset)

            if attrStart < attrEnd {
                result[attrStart..<attrEnd].foregroundColor = color
            }
        }
    }
}
