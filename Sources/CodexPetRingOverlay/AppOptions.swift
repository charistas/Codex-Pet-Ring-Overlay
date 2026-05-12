import Foundation

let appVersion = "0.1.0"

enum OverlayError: Error, CustomStringConvertible {
    case appServer(String)
    case missingCodexBinary(String)
    case invalidArgument(String)

    var description: String {
        switch self {
        case .appServer(let message):
            return message
        case .missingCodexBinary(let path):
            return "Codex binary not found or not executable: \(path). Install Codex Desktop in /Applications, put codex on PATH, or pass --codex-bin PATH."
        case .invalidArgument(let message):
            return message
        }
    }
}

struct AppOptions {
    let codexHome: URL
    let codexBinary: URL
}

func parseArguments() throws -> AppOptions {
    var codexHome = defaultCodexHome()
    var codexBinary: URL?

    var iterator = CommandLine.arguments.dropFirst().makeIterator()
    while let arg = iterator.next() {
        switch arg {
        case "--codex-home":
            let value = try requireValue(for: arg, from: &iterator)
            codexHome = URL(fileURLWithPath: NSString(string: value).expandingTildeInPath)
        case "--codex-bin":
            let value = try requireValue(for: arg, from: &iterator)
            let url = URL(fileURLWithPath: NSString(string: value).expandingTildeInPath)
            guard FileManager.default.isExecutableFile(atPath: url.path) else {
                throw OverlayError.missingCodexBinary(url.path)
            }
            codexBinary = url
        case "--help", "-h":
            print("""
            Codex Pet Ring Overlay \(appVersion)

            Draws live Codex usage rings around the floating Codex Desktop pet.

            Options:
              --codex-home PATH       Codex home directory. Defaults to ~/.codex or CODEX_HOME.
              --codex-bin PATH        Codex CLI binary. Defaults to /Applications/Codex.app/Contents/Resources/codex.
            """)
            Foundation.exit(0)
        default:
            fputs("Unknown argument: \(arg)\n", stderr)
            Foundation.exit(2)
        }
    }

    return AppOptions(
        codexHome: codexHome,
        codexBinary: try codexBinary ?? defaultCodexBinary()
    )
}

private func defaultCodexHome() -> URL {
    if let value = ProcessInfo.processInfo.environment["CODEX_HOME"], !value.isEmpty {
        return URL(fileURLWithPath: NSString(string: value).expandingTildeInPath)
    }
    return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
}

private func defaultCodexBinary() throws -> URL {
    let appBinary = URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex")
    if FileManager.default.isExecutableFile(atPath: appBinary.path) {
        return appBinary
    }

    let pathValues = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
    for value in pathValues {
        let candidate = URL(fileURLWithPath: String(value)).appendingPathComponent("codex")
        if FileManager.default.isExecutableFile(atPath: candidate.path) {
            return candidate
        }
    }

    throw OverlayError.missingCodexBinary(appBinary.path)
}

private func requireValue<I: IteratorProtocol>(
    for option: String,
    from iterator: inout I
) throws -> String where I.Element == String {
    guard let value = iterator.next(), !value.hasPrefix("--") else {
        throw OverlayError.invalidArgument("Missing value for \(option)")
    }
    return value
}
