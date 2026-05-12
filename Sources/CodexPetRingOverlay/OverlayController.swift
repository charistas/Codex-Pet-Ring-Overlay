import AppKit
import CodexPetRingOverlayCore
import CoreGraphics

final class OverlayController {
    private enum WindowAlignmentMode: Equatable {
        case mascotBounds
        case wholeWindowNoMascot
        case wholeWindowUncorrelatedMascot
    }

    private enum UsageRefreshPolicy {
        static let visibleInterval: TimeInterval = 60
        static let hiddenInterval: TimeInterval = 5 * 60
        static let maximumFailureBackoff: TimeInterval = 5 * 60
        static let staleUsageInterval: TimeInterval = 2 * visibleInterval
    }

    private enum TrackingPolicy {
        static let visibleMovingInterval: TimeInterval = 0.05
        static let visibleStableInterval: TimeInterval = 0.25
        static let hiddenInterval: TimeInterval = 1.0
        static let stablePollThreshold = 5
    }

    private let stateReader: CodexStateReader
    private let rateLimitReader: RateLimitReader
    private let ringView: RingView
    private let window: NSWindow
    private var trackingTimer: Timer?
    private var usageRefreshTimer: Timer?
    private var usageRefreshInFlight = false
    private var isPetVisible = false
    private var failureBackoffInterval: TimeInterval = 0
    private var lastWindowFrame: CGRect?
    private var stablePositionPolls = 0
    private var lastSuccessfulUsage: UsageRings?
    private var lastMascotBounds: MascotBounds?
    private var lastAlignmentMode: WindowAlignmentMode?
    private var accessibilityDisplayOptionsObserver: NSObjectProtocol?

    init(codexHome: URL, codexBinaryURL: URL, limitID: String) {
        stateReader = CodexStateReader(codexHome: codexHome)
        rateLimitReader = RateLimitReader(codexBinaryURL: codexBinaryURL, codexHome: codexHome, limitID: limitID)
        ringView = RingView(
            frame: NSRect(x: 0, y: 0, width: 136, height: 136),
            animatesChanges: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 136, height: 136),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = ringView
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)) + 2)
    }

    deinit {
        if let accessibilityDisplayOptionsObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(accessibilityDisplayOptionsObserver)
        }
    }

    func start() {
        NSApp.setActivationPolicy(.accessory)
        observeAccessibilityDisplayOptions()
        updateWindowPosition()
        if !isPetVisible {
            scheduleUsageRefresh(after: UsageRefreshPolicy.hiddenInterval)
        }

        scheduleTracking()
    }

    private func observeAccessibilityDisplayOptions() {
        guard accessibilityDisplayOptionsObserver == nil else { return }

        accessibilityDisplayOptionsObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.ringView.animatesChanges = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
    }

    private func scheduleTracking() {
        trackingTimer?.invalidate()

        let timer = Timer(timeInterval: currentTrackingInterval, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.updateWindowPosition()
            self.scheduleTracking()
        }
        RunLoop.main.add(timer, forMode: .common)
        trackingTimer = timer
    }

    private var currentTrackingInterval: TimeInterval {
        guard isPetVisible else {
            return TrackingPolicy.hiddenInterval
        }

        return stablePositionPolls >= TrackingPolicy.stablePollThreshold
            ? TrackingPolicy.visibleStableInterval
            : TrackingPolicy.visibleMovingInterval
    }

    private func refreshUsage() {
        guard !usageRefreshInFlight else { return }
        usageRefreshInFlight = true
        usageRefreshTimer?.invalidate()
        usageRefreshTimer = nil

        rateLimitReader.refresh { [weak self] result in
            guard let self else { return }
            self.usageRefreshInFlight = false

            switch result {
            case .success(let usage):
                self.failureBackoffInterval = 0
                self.lastSuccessfulUsage = usage
                self.ringView.displayState = .current(usage)
                self.scheduleUsageRefreshAfterSuccess()
            case .failure(let error):
                NSLog("Codex Pet Ring Overlay rate-limit refresh failed: \(error)")
                self.refreshUsageDisplayFreshness()
                self.scheduleUsageRefreshAfterFailure()
            }
        }
    }

    private func setPetVisible(_ visible: Bool) {
        guard visible != isPetVisible else { return }
        isPetVisible = visible

        if visible {
            refreshUsageDisplayFreshness()
            refreshUsage()
        } else {
            ringView.isLiveDisplayEnabled = false
            scheduleUsageRefresh(after: UsageRefreshPolicy.hiddenInterval)
        }
    }

    private func refreshUsageDisplayFreshness() {
        ringView.displayState = UsageFreshnessPolicy.displayState(
            for: lastSuccessfulUsage,
            staleInterval: UsageRefreshPolicy.staleUsageInterval
        )
    }

    private func scheduleUsageRefreshAfterSuccess() {
        let delay = isPetVisible ? UsageRefreshPolicy.visibleInterval : UsageRefreshPolicy.hiddenInterval
        scheduleUsageRefresh(after: delay)
    }

    private func scheduleUsageRefreshAfterFailure() {
        let nextBackoff: TimeInterval
        if failureBackoffInterval > 0 {
            nextBackoff = min(failureBackoffInterval * 2, UsageRefreshPolicy.maximumFailureBackoff)
        } else {
            nextBackoff = UsageRefreshPolicy.visibleInterval
        }

        failureBackoffInterval = nextBackoff
        let visibilityDelay = isPetVisible ? nextBackoff : UsageRefreshPolicy.hiddenInterval
        scheduleUsageRefresh(after: max(nextBackoff, visibilityDelay))
    }

    private func scheduleUsageRefresh(after delay: TimeInterval) {
        usageRefreshTimer?.invalidate()

        let timer = Timer(timeInterval: max(1, delay), repeats: false) { [weak self] _ in
            self?.refreshUsage()
        }
        RunLoop.main.add(timer, forMode: .common)
        usageRefreshTimer = timer
    }

    private func updateWindowPosition() {
        let mascot = stateReader.mascotBounds()
        if let mascot {
            lastMascotBounds = mascot
        }
        let selectionMascot = mascot ?? lastMascotBounds

        guard
            let codexWindow = findCodexAvatarWindow(mascot: selectionMascot)
        else {
            setPetVisible(false)
            window.orderOut(nil)
            lastWindowFrame = nil
            stablePositionPolls = 0
            lastAlignmentMode = nil
            return
        }

        let mascotRect: CGRect
        if codexWindow.isMascotCorrelated, let mascot = selectionMascot {
            setAlignmentMode(.mascotBounds)
            mascotRect = CGRect(
                x: codexWindow.bounds.minX + mascot.left,
                y: codexWindow.bounds.minY + mascot.top,
                width: mascot.width,
                height: mascot.height
            )
        } else {
            setAlignmentMode(selectionMascot == nil ? .wholeWindowNoMascot : .wholeWindowUncorrelatedMascot)
            mascotRect = codexWindow.bounds
        }

        let diameter = max(mascotRect.width, mascotRect.height) + 64
        let ringRect = CGRect(
            x: mascotRect.midX - diameter / 2,
            y: mascotRect.midY - diameter / 2,
            width: diameter,
            height: diameter
        )

        guard let appKitFrame = convertCGWindowRectToAppKitFrame(ringRect) else {
            setPetVisible(false)
            window.orderOut(nil)
            lastWindowFrame = nil
            stablePositionPolls = 0
            return
        }

        setPetVisible(true)

        let roundedFrame = CGRect(
            x: round(appKitFrame.origin.x),
            y: round(appKitFrame.origin.y),
            width: round(appKitFrame.width),
            height: round(appKitFrame.height)
        )

        if lastWindowFrame != roundedFrame {
            ringView.frame = NSRect(origin: .zero, size: roundedFrame.size)
            window.setFrame(roundedFrame, display: true)
            lastWindowFrame = roundedFrame
            stablePositionPolls = 0
        } else {
            stablePositionPolls = min(stablePositionPolls + 1, TrackingPolicy.stablePollThreshold)
        }

        if !window.isVisible {
            ringView.isLiveDisplayEnabled = true
            window.orderFrontRegardless()
        } else {
            ringView.isLiveDisplayEnabled = true
        }
    }

    private func setAlignmentMode(_ mode: WindowAlignmentMode) {
        guard mode != lastAlignmentMode else { return }
        lastAlignmentMode = mode

        switch mode {
        case .mascotBounds:
            NSLog("Codex Pet Ring Overlay aligned to Codex avatar bounds.")
        case .wholeWindowNoMascot:
            NSLog("Codex Pet Ring Overlay could not read Codex avatar bounds; using the visible Codex overlay window until local state is available.")
        case .wholeWindowUncorrelatedMascot:
            NSLog("Codex Pet Ring Overlay ignored stale Codex avatar bounds that do not fit the visible overlay window.")
        }
    }

    private func findCodexAvatarWindow(mascot: MascotBounds?) -> AvatarWindowSelection? {
        guard
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else {
            return nil
        }

        let snapshots = windows.compactMap { window -> WindowSnapshot? in
            guard
                let bounds = window[kCGWindowBounds as String] as? [String: Any]
            else {
                return nil
            }

            guard
                let x = Self.number(bounds["X"]),
                let y = Self.number(bounds["Y"]),
                let width = Self.number(bounds["Width"]),
                let height = Self.number(bounds["Height"])
            else {
                return nil
            }

            let rect = CGRect(x: x, y: y, width: width, height: height)
            return WindowSnapshot(
                ownerName: window[kCGWindowOwnerName as String] as? String,
                layer: Self.integer(window[kCGWindowLayer as String]),
                isOnscreen: Self.integer(window[kCGWindowIsOnscreen as String]) == 1,
                bounds: rect
            )
        }

        return CodexWindowSelector.selectAvatarWindowSelection(from: snapshots, mascot: mascot)
    }

    private func convertCGWindowRectToAppKitFrame(_ rect: CGRect) -> CGRect? {
        let screens = NSScreen.screens.compactMap { screen -> ScreenSnapshot? in
            guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                return nil
            }
            return ScreenSnapshot(frame: screen.frame, displayBounds: CGDisplayBounds(displayID))
        }

        return WindowGeometryConverter.convertCGWindowRectToAppKitFrame(rect, screens: screens)
    }

    private static func number(_ value: Any?) -> CGFloat? {
        guard let number = NumericValueParser.optionalDouble(value) else {
            return nil
        }
        return CGFloat(number)
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let number = NumericValueParser.optionalDouble(value), number.rounded() == number else {
            return nil
        }
        return Int(number)
    }
}
