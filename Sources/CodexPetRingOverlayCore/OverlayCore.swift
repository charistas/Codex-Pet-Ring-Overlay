import CoreGraphics
import Foundation

public struct MascotBounds: Decodable, Equatable {
    public let left: Double
    public let top: Double
    public let width: Double
    public let height: Double

    public init(left: Double, top: Double, width: Double, height: Double) {
        self.left = left
        self.top = top
        self.width = width
        self.height = height
    }

    public var hasFinitePositiveSize: Bool {
        [left, top, width, height].allSatisfy(\.isFinite) && width > 0 && height > 0
    }
}

public enum UsageLevel: Equatable {
    case normal
    case high
    case critical
}

public struct RingWindow: Equatable {
    public let usedPercent: Double
    public let windowDurationMinutes: Double

    public init(usedPercent: Double, windowDurationMinutes: Double) {
        self.usedPercent = usedPercent
        self.windowDurationMinutes = windowDurationMinutes
    }

    public var ringPercent: Double {
        max(0, min(100, usedPercent))
    }

    public var usageLevel: UsageLevel {
        if usedPercent >= 95 {
            return .critical
        }
        if usedPercent >= 80 {
            return .high
        }
        return .normal
    }

    public var isShortWindow: Bool {
        windowDurationMinutes < 24 * 60
    }
}

public struct UsageRings: Equatable {
    public let shortWindow: RingWindow
    public let longWindow: RingWindow
    public let updatedAt: Date

    public init(shortWindow: RingWindow, longWindow: RingWindow, updatedAt: Date) {
        self.shortWindow = shortWindow
        self.longWindow = longWindow
        self.updatedAt = updatedAt
    }
}

public enum UsageDisplayState: Equatable {
    case loading
    case current(UsageRings)
    case stale(UsageRings)

    public var usage: UsageRings? {
        switch self {
        case .loading:
            return nil
        case .current(let usage), .stale(let usage):
            return usage
        }
    }

    public var isStale: Bool {
        if case .stale = self {
            return true
        }
        return false
    }
}

public enum UsageFreshnessPolicy {
    public static func displayState(for usage: UsageRings?, now: Date = Date(), staleInterval: TimeInterval) -> UsageDisplayState {
        guard let usage else {
            return .loading
        }

        return now.timeIntervalSince(usage.updatedAt) >= staleInterval ? .stale(usage) : .current(usage)
    }
}

public enum RateLimitParseError: Error, CustomStringConvertible, Equatable {
    case malformed(String)

    public var description: String {
        switch self {
        case .malformed(let message):
            return message
        }
    }
}

public enum NumericValueParser {
    public static func optionalDouble(_ value: Any?) -> Double? {
        let number: Double?
        switch value {
        case let value as NSNumber where CFGetTypeID(value) == CFBooleanGetTypeID():
            number = nil
        case let value as NSNumber:
            number = value.doubleValue
        case let value as Double:
            number = value
        case let value as Int:
            number = Double(value)
        case is Bool:
            number = nil
        case let value as String:
            number = Double(value)
        default:
            number = nil
        }

        guard let number, number.isFinite else { return nil }
        return number
    }

    public static func requiredDouble(_ value: Any?, field: String) throws -> Double {
        guard let number = optionalDouble(value) else {
            throw RateLimitParseError.malformed("Rate-limit response field '\(field)' was missing or not numeric.")
        }
        return number
    }
}

public enum JSONLineMessageParser {
    public static func parseObject(from lineData: Data) -> [String: Any]? {
        guard
            let object = try? JSONSerialization.jsonObject(with: lineData),
            let message = object as? [String: Any]
        else {
            return nil
        }

        return message
    }
}

public enum RateLimitSnapshotParser {
    public static func parseUsageRings(from response: [String: Any], limitID: String, updatedAt: Date = Date()) throws -> UsageRings {
        var snapshot: [String: Any]?
        if let byLimitID = response["rateLimitsByLimitId"] as? [String: Any] {
            guard let limitSnapshot = byLimitID[limitID] as? [String: Any] else {
                throw RateLimitParseError.malformed("Rate-limit response did not include limit id '\(limitID)'.")
            }
            snapshot = limitSnapshot
        } else {
            snapshot = response["rateLimits"] as? [String: Any]
        }

        guard let snapshot else {
            throw RateLimitParseError.malformed("Rate-limit response did not include a usable snapshot.")
        }

        guard let primary = snapshot["primary"] as? [String: Any] else {
            throw RateLimitParseError.malformed("Rate-limit response did not include a primary window.")
        }
        guard let secondary = snapshot["secondary"] as? [String: Any] else {
            throw RateLimitParseError.malformed("Rate-limit response did not include a secondary window.")
        }

        let windows = try [
            parseWindow(primary, name: "primary"),
            parseWindow(secondary, name: "secondary"),
        ].sorted { $0.windowDurationMinutes < $1.windowDurationMinutes }

        return UsageRings(shortWindow: windows[0], longWindow: windows[windows.count - 1], updatedAt: updatedAt)
    }

    public static func parseWindow(_ object: [String: Any], name: String) throws -> RingWindow {
        let duration = try NumericValueParser.requiredDouble(object["windowDurationMins"], field: "\(name).windowDurationMins")
        guard duration > 0 else {
            throw RateLimitParseError.malformed("Rate-limit response field '\(name).windowDurationMins' must be positive.")
        }

        let used = try NumericValueParser.requiredDouble(object["usedPercent"], field: "\(name).usedPercent")
        return RingWindow(
            usedPercent: max(0, min(100, used)),
            windowDurationMinutes: duration
        )
    }
}

private struct AvatarOverlayBounds: Decodable {
    let mascot: MascotBounds?
}

public enum CodexStateParser {
    public static func parseMascotBounds(from data: Data) throws -> MascotBounds? {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let boundsObject = object?["electron-avatar-overlay-bounds"] else {
            return nil
        }
        let boundsData = try JSONSerialization.data(withJSONObject: boundsObject)
        let bounds = try JSONDecoder().decode(AvatarOverlayBounds.self, from: boundsData)
        guard let mascot = bounds.mascot else { return nil }
        return mascot.hasFinitePositiveSize ? mascot : nil
    }
}

public struct WindowSnapshot: Equatable {
    public let ownerName: String?
    public let layer: Int?
    public let isOnscreen: Bool
    public let bounds: CGRect

    public init(ownerName: String?, layer: Int?, isOnscreen: Bool, bounds: CGRect) {
        self.ownerName = ownerName
        self.layer = layer
        self.isOnscreen = isOnscreen
        self.bounds = bounds
    }
}

public enum CodexWindowSelector {
    public static func selectAvatarWindow(from windows: [WindowSnapshot], mascot: MascotBounds?) -> CGRect? {
        let candidates = windows.filter(isCodexAvatarCandidate)
        let correlatedCandidates = candidates.filter { candidate in
            guard let mascot, mascot.hasFinitePositiveSize else { return true }
            return candidateCanContain(mascot: mascot, in: candidate.bounds)
        }

        return correlatedCandidates
            .min { candidateScore($0.bounds, mascot: mascot) < candidateScore($1.bounds, mascot: mascot) }?
            .bounds
    }

    private static func isCodexAvatarCandidate(_ window: WindowSnapshot) -> Bool {
        guard
            window.ownerName == "Codex",
            window.layer == 3,
            window.isOnscreen
        else {
            return false
        }

        return window.bounds.width >= 80
            && window.bounds.width <= 700
            && window.bounds.height >= 80
            && window.bounds.height <= 700
    }

    private static func candidateCanContain(mascot: MascotBounds, in bounds: CGRect) -> Bool {
        let tolerance = 2.0
        return mascot.left >= -tolerance
            && mascot.top >= -tolerance
            && mascot.left + mascot.width <= Double(bounds.width) + tolerance
            && mascot.top + mascot.height <= Double(bounds.height) + tolerance
    }

    private static func candidateScore(_ bounds: CGRect, mascot: MascotBounds?) -> CGFloat {
        guard let mascot, mascot.hasFinitePositiveSize else {
            return bounds.width * bounds.height
        }

        let requiredWidth = CGFloat(max(mascot.width, mascot.left + mascot.width))
        let requiredHeight = CGFloat(max(mascot.height, mascot.top + mascot.height))
        let excessWidth = max(0, bounds.width - requiredWidth)
        let excessHeight = max(0, bounds.height - requiredHeight)
        return excessWidth * excessWidth + excessHeight * excessHeight
    }
}

public struct ScreenSnapshot: Equatable {
    public let frame: CGRect
    public let displayBounds: CGRect

    public init(frame: CGRect, displayBounds: CGRect) {
        self.frame = frame
        self.displayBounds = displayBounds
    }
}

public enum WindowGeometryConverter {
    public static func convertCGWindowRectToAppKitFrame(_ rect: CGRect, screens: [ScreenSnapshot]) -> CGRect? {
        let center = CGPoint(x: rect.midX, y: rect.midY)

        if let containingScreen = screens.first(where: { $0.displayBounds.contains(center) }) {
            return convert(rect, on: containingScreen)
        }

        return screens
            .compactMap { screen -> (screen: ScreenSnapshot, area: CGFloat)? in
                let intersection = screen.displayBounds.intersection(rect)
                guard !intersection.isNull, !intersection.isEmpty else { return nil }
                return (screen, intersection.width * intersection.height)
            }
            .max { $0.area < $1.area }
            .map { convert(rect, on: $0.screen) }
    }

    private static func convert(_ rect: CGRect, on screen: ScreenSnapshot) -> CGRect {
        let localX = rect.minX - screen.displayBounds.minX
        let localYFromTop = rect.minY - screen.displayBounds.minY
        return CGRect(
            x: screen.frame.minX + localX,
            y: screen.frame.maxY - localYFromTop - rect.height,
            width: rect.width,
            height: rect.height
        )
    }
}
