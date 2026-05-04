import Foundation

final class PipeOutputCollector {
    private let lock = NSLock()
    private let maximumBytes: Int
    private var data = Data()

    init(maximumBytes: Int = 16_384) {
        self.maximumBytes = maximumBytes
    }

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }

        lock.lock()
        defer { lock.unlock() }

        data.append(chunk)
        if data.count > maximumBytes {
            data.removeSubrange(data.startIndex..<data.index(data.endIndex, offsetBy: -maximumBytes))
        }
    }

    var singleLineText: String {
        lock.lock()
        defer { lock.unlock() }

        return (String(data: data, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " | ")
    }
}
