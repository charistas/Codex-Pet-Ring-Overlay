import CodexPetRingOverlayCore
import Darwin
import Foundation

final class RateLimitReader {
    private let codexBinaryURL: URL
    private let codexHome: URL
    private let limitID: String
    private var refreshInFlight = false

    init(codexBinaryURL: URL, codexHome: URL, limitID: String) {
        self.codexBinaryURL = codexBinaryURL
        self.codexHome = codexHome
        self.limitID = limitID
    }

    func refresh(completion: @escaping (Result<UsageRings, Error>) -> Void) {
        guard !refreshInFlight else { return }
        refreshInFlight = true

        DispatchQueue.global(qos: .utility).async {
            let result: Result<UsageRings, Error>
            do {
                result = .success(try self.readRateLimits())
            } catch {
                result = .failure(error)
            }

            DispatchQueue.main.async {
                self.refreshInFlight = false
                completion(result)
            }
        }
    }

    private func readRateLimits() throws -> UsageRings {
        let process = Process()
        process.executableURL = codexBinaryURL
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.environment = ProcessInfo.processInfo.environment.merging(["CODEX_HOME": codexHome.path]) { _, new in new }

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()

        let input = inputPipe.fileHandleForWriting
        let output = outputPipe.fileHandleForReading
        let errorOutput = errorPipe.fileHandleForReading
        let errorCollector = PipeOutputCollector()
        var buffer = Data()
        var initialized = false
        var recentLines: [String] = []
        let deadline = Date().addingTimeInterval(15)

        errorOutput.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
            } else {
                errorCollector.append(chunk)
            }
        }

        let timeoutWorkItem = DispatchWorkItem {
            Self.stopProcess(process)
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 15.5, execute: timeoutWorkItem)

        defer {
            timeoutWorkItem.cancel()
            errorOutput.readabilityHandler = nil
            try? input.close()
            Self.stopProcess(process)
            try? output.close()
            try? errorOutput.close()
        }

        try writeJSON([
            "id": 1,
            "method": "initialize",
            "params": [
                "clientInfo": [
                    "name": "codex-pet-ring-overlay",
                    "title": "Codex Pet Ring Overlay",
                    "version": appVersion,
                ],
                "capabilities": [
                    "experimentalApi": true,
                ],
            ],
        ], to: input)

        while Date() < deadline {
            let chunk = output.availableData
            if chunk.isEmpty {
                break
            }
            buffer.append(chunk)

            while let newlineRange = buffer.firstRange(of: Data([0x0A])) {
                let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                buffer.removeSubrange(buffer.startIndex..<newlineRange.upperBound)

                guard let line = String(data: lineData, encoding: .utf8), !line.isEmpty else {
                    continue
                }
                recentLines.append(line)
                recentLines = Array(recentLines.suffix(6))

                guard let message = JSONLineMessageParser.parseObject(from: lineData), let id = message["id"] as? Int else {
                    continue
                }

                if id == 1 {
                    if let error = message["error"] {
                        throw OverlayError.appServer("Codex app-server initialization error: \(error)")
                    }
                    initialized = true
                    try writeJSON(["id": 2, "method": "account/rateLimits/read"], to: input)
                    continue
                }

                if id == 2 {
                    if let error = message["error"] {
                        throw OverlayError.appServer("Codex app-server error: \(error)")
                    }
                    guard let result = message["result"] as? [String: Any] else {
                        throw OverlayError.appServer("Codex app-server returned a malformed rate-limit result.")
                    }
                    do {
                        return try RateLimitSnapshotParser.parseUsageRings(from: result, limitID: limitID)
                    } catch {
                        throw OverlayError.appServer(
                            "\(error) Response shape: \(Self.rateLimitResponseShapeDescription(result, limitID: limitID))"
                        )
                    }
                }
            }
        }

        let phase = initialized ? "account/rateLimits/read" : "Codex app-server initialization"
        let stderr = errorCollector.singleLineText
        let stderrSummary = stderr.isEmpty ? "" : " Stderr: \(stderr)"
        throw OverlayError.appServer("Timed out waiting for \(phase). Recent output: \(recentLines.joined(separator: " | "))\(stderrSummary)")
    }

    private static func stopProcess(_ process: Process) {
        guard process.isRunning else { return }

        process.terminate()
        if waitForExit(process, timeout: 1.5) {
            return
        }

        kill(process.processIdentifier, SIGKILL)
        _ = waitForExit(process, timeout: 1.0)
    }

    private static func waitForExit(_ process: Process, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        return !process.isRunning
    }

    private func writeJSON(_ object: [String: Any], to handle: FileHandle) throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        handle.write(data)
        handle.write(Data([0x0A]))
    }

    private static func rateLimitResponseShapeDescription(_ result: [String: Any], limitID: String) -> String {
        let topLevelKeys = result.keys.sorted().joined(separator: ",")
        let rateLimitsKeys = dictionaryKeys(result["rateLimits"])
        let selectedLimitKeys: String
        let primaryKeys: String
        let secondaryKeys: String

        if
            let byLimitID = result["rateLimitsByLimitId"] as? [String: Any],
            let selectedLimit = byLimitID[limitID] as? [String: Any]
        {
            selectedLimitKeys = selectedLimit.keys.sorted().joined(separator: ",")
            primaryKeys = dictionaryKeys(selectedLimit["primary"])
            secondaryKeys = dictionaryKeys(selectedLimit["secondary"])
        } else {
            selectedLimitKeys = ""
            primaryKeys = dictionaryKeys((result["rateLimits"] as? [String: Any])?["primary"])
            secondaryKeys = dictionaryKeys((result["rateLimits"] as? [String: Any])?["secondary"])
        }

        return "topLevel=[\(topLevelKeys)] rateLimits=[\(rateLimitsKeys)] selectedLimit=[\(selectedLimitKeys)] primary=[\(primaryKeys)] secondary=[\(secondaryKeys)]"
    }

    private static func dictionaryKeys(_ value: Any?) -> String {
        guard let dictionary = value as? [String: Any] else {
            return ""
        }
        return dictionary.keys.sorted().joined(separator: ",")
    }
}
