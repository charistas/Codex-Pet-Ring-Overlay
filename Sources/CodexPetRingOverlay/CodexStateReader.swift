import CodexPetRingOverlayCore
import Foundation

final class CodexStateReader {
    private let stateURL: URL
    private var lastModificationDate: Date?
    private var cachedMascot: MascotBounds?

    init(codexHome: URL) {
        stateURL = codexHome.appendingPathComponent(".codex-global-state.json")
    }

    func mascotBounds() -> MascotBounds? {
        let modificationDate = (try? FileManager.default.attributesOfItem(atPath: stateURL.path)[.modificationDate]) as? Date
        if modificationDate == lastModificationDate {
            return cachedMascot
        }

        lastModificationDate = modificationDate
        guard let data = try? Data(contentsOf: stateURL) else {
            cachedMascot = nil
            return nil
        }

        do {
            cachedMascot = try CodexStateParser.parseMascotBounds(from: data)
        } catch {
            cachedMascot = nil
            NSLog("Codex Pet Ring Overlay could not parse Codex avatar bounds: \(error)")
        }

        return cachedMascot
    }
}
