import AppKit
import Foundation

do {
    let options = try parseArguments()
    let app = NSApplication.shared
    let controller = OverlayController(
        codexHome: options.codexHome,
        codexBinaryURL: options.codexBinary,
        limitID: "codex"
    )
    controller.start()
    app.run()
} catch {
    fputs("codex-pet-ring-overlay: \(error)\n", stderr)
    Foundation.exit(1)
}
