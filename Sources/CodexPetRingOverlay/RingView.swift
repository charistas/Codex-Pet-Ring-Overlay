import AppKit
import CodexPetRingOverlayCore
import CoreGraphics
import Foundation

private struct RingPalette {
    let short: NSColor
    let long: NSColor
    let high: NSColor
    let critical: NSColor
    let track: NSColor
    let halo: NSColor

    static let standard = RingPalette(
        short: NSColor(calibratedRed: 0.35, green: 0.65, blue: 1.00, alpha: 1.0),
        long: NSColor(calibratedRed: 0.40, green: 0.82, blue: 0.62, alpha: 1.0),
        high: NSColor(calibratedRed: 0.95, green: 0.80, blue: 0.38, alpha: 1.0),
        critical: NSColor(calibratedRed: 1.00, green: 0.36, blue: 0.36, alpha: 1.0),
        track: NSColor(calibratedWhite: 1.0, alpha: 0.16),
        halo: NSColor(calibratedWhite: 0.0, alpha: 0.18)
    )

    private init(
        short: NSColor,
        long: NSColor,
        high: NSColor,
        critical: NSColor,
        track: NSColor,
        halo: NSColor
    ) {
        self.short = short
        self.long = long
        self.high = high
        self.critical = critical
        self.track = track
        self.halo = halo
    }

    func color(for window: RingWindow) -> NSColor {
        switch window.usageLevel {
        case .normal:
            return window.isShortWindow ? short : long
        case .high:
            return high
        case .critical:
            return critical
        }
    }
}

private extension NSColor {
    func settingAlpha(_ alpha: CGFloat) -> NSColor {
        let color = usingColorSpace(.deviceRGB) ?? self
        return NSColor(
            calibratedRed: color.redComponent,
            green: color.greenComponent,
            blue: color.blueComponent,
            alpha: min(1, max(0, alpha))
        )
    }

    func scalingAlpha(by multiplier: CGFloat) -> NSColor {
        let color = usingColorSpace(.deviceRGB) ?? self
        return color.settingAlpha(color.alphaComponent * multiplier)
    }

    func brightened(by amount: CGFloat) -> NSColor {
        let color = usingColorSpace(.deviceRGB) ?? self
        let clampedAmount = min(1, max(0, amount))
        return NSColor(
            calibratedRed: color.redComponent + (1 - color.redComponent) * clampedAmount,
            green: color.greenComponent + (1 - color.greenComponent) * clampedAmount,
            blue: color.blueComponent + (1 - color.blueComponent) * clampedAmount,
            alpha: color.alphaComponent
        )
    }
}

final class RingView: NSView {
    private enum Constants {
        static let animationDuration: TimeInterval = 0.35
        static let frameInterval: TimeInterval = 1.0 / 30.0
        static let baseLineWidth: CGFloat = 6
        static let highLineWidth: CGFloat = 7
        static let criticalLineWidth: CGFloat = 8
        static let radiusGap: CGFloat = 13
    }

    var animatesChanges: Bool {
        didSet {
            guard oldValue != animatesChanges else { return }
            if !animatesChanges {
                if let usage {
                    displayedShortPercent = usage.shortWindow.ringPercent
                    displayedLongPercent = usage.longWindow.ringPercent
                }
                animationStartedAt = nil
            } else if usage == nil {
                loadingStartedAt = Date()
            }
            needsDisplay = true
            updateAnimationTimer()
        }
    }
    private var animationTimer: Timer?
    private var loadingStartedAt = Date()
    private var animationStartedAt: Date?
    private var startShortPercent = 0.0
    private var startLongPercent = 0.0
    private var displayedShortPercent = 0.0
    private var displayedLongPercent = 0.0

    var isLiveDisplayEnabled = false {
        didSet {
            needsDisplay = true
            updateAnimationTimer()
        }
    }

    var displayState: UsageDisplayState = .loading {
        didSet {
            if oldValue.usage != displayState.usage {
                updateDisplayedUsage()
            }
            needsDisplay = true
            updateAnimationTimer()
        }
    }

    private var usage: UsageRings? {
        displayState.usage
    }

    init(frame frameRect: NSRect, animatesChanges: Bool) {
        self.animatesChanges = animatesChanges
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.clear(bounds)
        context.setShouldAntialias(true)
        context.saveGState()
        defer { context.restoreGState() }

        if displayState.isStale {
            context.setAlpha(0.38)
        }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let outerRadius = min(bounds.width, bounds.height) / 2 - 7
        let innerRadius = outerRadius - Constants.radiusGap
        let palette = RingPalette.standard
        let loadingOpacity = loadingTrackOpacity()

        drawTrack(
            context: context,
            center: center,
            radius: outerRadius,
            palette: palette,
            opacity: loadingOpacity,
            lineWidth: Constants.baseLineWidth
        )
        drawTrack(
            context: context,
            center: center,
            radius: innerRadius,
            palette: palette,
            opacity: loadingOpacity,
            lineWidth: Constants.baseLineWidth - 1
        )

        guard let usage else { return }
        drawRing(
            context: context,
            center: center,
            radius: outerRadius,
            percent: displayedShortPercent,
            window: usage.shortWindow,
            palette: palette,
            lineWidthAdjustment: 0
        )
        drawRing(
            context: context,
            center: center,
            radius: innerRadius,
            percent: displayedLongPercent,
            window: usage.longWindow,
            palette: palette,
            lineWidthAdjustment: -1
        )
    }

    private func updateDisplayedUsage() {
        guard let usage else {
            displayedShortPercent = 0
            displayedLongPercent = 0
            animationStartedAt = nil
            loadingStartedAt = Date()
            return
        }

        startShortPercent = displayedShortPercent
        startLongPercent = displayedLongPercent

        if animatesChanges {
            animationStartedAt = Date()
        } else {
            displayedShortPercent = usage.shortWindow.ringPercent
            displayedLongPercent = usage.longWindow.ringPercent
            animationStartedAt = nil
        }
    }

    private func updateAnimationTimer() {
        guard needsLiveRedraw else {
            animationTimer?.invalidate()
            animationTimer = nil
            return
        }

        guard animationTimer == nil else { return }
        let timer = Timer(timeInterval: Constants.frameInterval, repeats: true) { [weak self] _ in
            self?.tickAnimation()
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    private var needsLiveRedraw: Bool {
        guard isLiveDisplayEnabled else { return false }
        guard animatesChanges else { return false }
        if animationStartedAt != nil {
            return true
        }
        if usage == nil {
            return true
        }
        if usageContainsCriticalWindow {
            return true
        }
        return false
    }

    private var usageContainsCriticalWindow: Bool {
        usage?.shortWindow.usageLevel == .critical || usage?.longWindow.usageLevel == .critical
    }

    private func tickAnimation() {
        if let animationStartedAt, let usage {
            let elapsed = Date().timeIntervalSince(animationStartedAt)
            let progress = min(1, elapsed / Constants.animationDuration)
            let easedProgress = 1 - pow(1 - progress, 3)

            displayedShortPercent = interpolate(from: startShortPercent, to: usage.shortWindow.ringPercent, progress: easedProgress)
            displayedLongPercent = interpolate(from: startLongPercent, to: usage.longWindow.ringPercent, progress: easedProgress)

            if progress >= 1 {
                displayedShortPercent = usage.shortWindow.ringPercent
                displayedLongPercent = usage.longWindow.ringPercent
                self.animationStartedAt = nil
            }
        }

        needsDisplay = true
        updateAnimationTimer()
    }

    private func interpolate(from start: Double, to end: Double, progress: Double) -> Double {
        start + (end - start) * progress
    }

    private func loadingTrackOpacity() -> CGFloat {
        guard usage == nil else { return 1 }
        guard animatesChanges else { return 0.78 }
        let elapsed = Date().timeIntervalSince(loadingStartedAt)
        let phase = (sin(elapsed * 2.2) + 1) / 2
        return CGFloat(0.62 + phase * 0.38)
    }

    private func drawTrack(
        context: CGContext,
        center: CGPoint,
        radius: CGFloat,
        palette: RingPalette,
        opacity: CGFloat,
        lineWidth: CGFloat
    ) {
        strokeFullCircle(
            context: context,
            center: center,
            radius: radius,
            color: palette.halo.scalingAlpha(by: opacity),
            lineWidth: lineWidth + 5
        )
        strokeFullCircle(
            context: context,
            center: center,
            radius: radius,
            color: palette.track.scalingAlpha(by: opacity),
            lineWidth: lineWidth
        )
    }

    private func drawRing(
        context: CGContext,
        center: CGPoint,
        radius: CGFloat,
        percent: Double,
        window: RingWindow,
        palette: RingPalette,
        lineWidthAdjustment: CGFloat
    ) {
        guard percent > 0 else {
            return
        }

        let color = palette.color(for: window)
        let lineWidth = max(1, lineWidth(for: window) + lineWidthAdjustment)
        let end = -.pi / 2 + .pi * 2 * CGFloat(percent / 100)

        if window.usageLevel == .critical {
            let pulse = criticalPulse()
            strokeArc(
                context: context,
                center: center,
                radius: radius,
                endAngle: end,
                color: color.settingAlpha(0.12 + 0.14 * pulse),
                lineWidth: lineWidth + 6 + 2 * pulse
            )
        }

        strokeArc(
            context: context,
            center: center,
            radius: radius,
            endAngle: end,
            color: palette.halo,
            lineWidth: lineWidth + 4
        )
        strokeArc(
            context: context,
            center: center,
            radius: radius,
            endAngle: end,
            color: strokeColor(color, for: window),
            lineWidth: lineWidth
        )
    }

    private func lineWidth(for window: RingWindow) -> CGFloat {
        switch window.usageLevel {
        case .normal:
            return Constants.baseLineWidth
        case .high:
            return Constants.highLineWidth
        case .critical:
            return Constants.criticalLineWidth
        }
    }

    private func strokeColor(_ color: NSColor, for window: RingWindow) -> NSColor {
        switch window.usageLevel {
        case .normal:
            return color
        case .high:
            return color.brightened(by: 0.10)
        case .critical:
            return color.brightened(by: 0.14)
        }
    }

    private func criticalPulse() -> CGFloat {
        guard animatesChanges else { return 0 }
        let phase = (sin(Date().timeIntervalSinceReferenceDate * 3.0) + 1) / 2
        return CGFloat(phase)
    }

    private func strokeFullCircle(
        context: CGContext,
        center: CGPoint,
        radius: CGFloat,
        color: NSColor,
        lineWidth: CGFloat
    ) {
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.addArc(center: center, radius: radius, startAngle: -.pi / 2, endAngle: .pi * 1.5, clockwise: false)
        context.strokePath()
    }

    private func strokeArc(
        context: CGContext,
        center: CGPoint,
        radius: CGFloat,
        endAngle: CGFloat,
        color: NSColor,
        lineWidth: CGFloat
    ) {
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.addArc(center: center, radius: radius, startAngle: -.pi / 2, endAngle: endAngle, clockwise: false)
        context.strokePath()
    }
}
