import CoreGraphics
import Foundation
import XCTest
@testable import CodexPetRingOverlayCore

final class OverlayCoreTests: XCTestCase {
    func testParseUsageRingsRejectsMissingUsedPercent() {
        let response: [String: Any] = [
            "rateLimits": [
                "primary": [
                    "windowDurationMins": 300,
                ],
                "secondary": [
                    "windowDurationMins": 10_080,
                    "usedPercent": 42,
                ],
            ],
        ]

        XCTAssertThrowsError(try RateLimitSnapshotParser.parseUsageRings(from: response, limitID: "codex")) { error in
            XCTAssertTrue(String(describing: error).contains("primary.usedPercent"))
        }
    }

    func testParseUsageRingsAcceptsLimitSpecificSnapshotAndSortsWindows() throws {
        let updatedAt = Date(timeIntervalSince1970: 1_800)
        let response: [String: Any] = [
            "rateLimitsByLimitId": [
                "codex": [
                    "primary": [
                        "windowDurationMins": 10_080,
                        "usedPercent": "82.5",
                    ],
                    "secondary": [
                        "windowDurationMins": 300,
                        "usedPercent": 12,
                    ],
                ],
            ],
        ]

        let usage = try RateLimitSnapshotParser.parseUsageRings(from: response, limitID: "codex", updatedAt: updatedAt)

        XCTAssertEqual(usage.updatedAt, updatedAt)
        XCTAssertEqual(usage.shortWindow.windowDurationMinutes, 300)
        XCTAssertEqual(usage.shortWindow.usedPercent, 12)
        XCTAssertEqual(usage.shortWindow.usageLevel, .normal)
        XCTAssertEqual(usage.longWindow.windowDurationMinutes, 10_080)
        XCTAssertEqual(usage.longWindow.usedPercent, 82.5)
        XCTAssertEqual(usage.longWindow.usageLevel, .high)
    }

    func testParseUsageRingsRejectsMissingRequestedLimitID() {
        let response: [String: Any] = [
            "rateLimitsByLimitId": [
                "other": [
                    "primary": [
                        "windowDurationMins": 300,
                        "usedPercent": 12,
                    ],
                    "secondary": [
                        "windowDurationMins": 10_080,
                        "usedPercent": 42,
                    ],
                ],
            ],
            "rateLimits": [
                "primary": [
                    "windowDurationMins": 300,
                    "usedPercent": 88,
                ],
                "secondary": [
                    "windowDurationMins": 10_080,
                    "usedPercent": 91,
                ],
            ],
        ]

        XCTAssertThrowsError(try RateLimitSnapshotParser.parseUsageRings(from: response, limitID: "codex")) { error in
            XCTAssertTrue(String(describing: error).contains("codex"))
        }
    }

    func testParseUsageRingsRejectsNonPositiveDuration() {
        let response: [String: Any] = [
            "rateLimits": [
                "primary": [
                    "windowDurationMins": 0,
                    "usedPercent": 12,
                ],
                "secondary": [
                    "windowDurationMins": 10_080,
                    "usedPercent": 42,
                ],
            ],
        ]

        XCTAssertThrowsError(try RateLimitSnapshotParser.parseUsageRings(from: response, limitID: "codex")) { error in
            XCTAssertTrue(String(describing: error).contains("primary.windowDurationMins"))
        }
    }

    func testParseUsageRingsRejectsBooleanNumericFields() throws {
        let data = """
        {
          "rateLimits": {
            "primary": {
              "windowDurationMins": 300,
              "usedPercent": true
            },
            "secondary": {
              "windowDurationMins": 10080,
              "usedPercent": 42
            }
          }
        }
        """.data(using: .utf8)!
        let response = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertThrowsError(try RateLimitSnapshotParser.parseUsageRings(from: response, limitID: "codex")) { error in
            XCTAssertTrue(String(describing: error).contains("primary.usedPercent"))
        }
    }

    func testParseMascotBoundsFromCodexState() throws {
        let data = """
        {
          "electron-avatar-overlay-bounds": {
            "mascot": {
              "left": 18,
              "top": 24,
              "width": 96,
              "height": 88
            }
          }
        }
        """.data(using: .utf8)!

        let mascot = try CodexStateParser.parseMascotBounds(from: data)

        XCTAssertEqual(mascot, MascotBounds(left: 18, top: 24, width: 96, height: 88))
    }

    func testParseMascotBoundsRejectsInvalidMascotSize() throws {
        let data = """
        {
          "electron-avatar-overlay-bounds": {
            "mascot": {
              "left": 18,
              "top": 24,
              "width": 0,
              "height": 88
            }
          }
        }
        """.data(using: .utf8)!

        let mascot = try CodexStateParser.parseMascotBounds(from: data)

        XCTAssertNil(mascot)
    }

    func testSelectAvatarWindowRejectsCodexWindowThatCannotContainMascot() {
        let mascot = MascotBounds(left: 20, top: 18, width: 96, height: 96)
        let windows = [
            WindowSnapshot(
                ownerName: "Codex",
                layer: 3,
                isOnscreen: true,
                bounds: CGRect(x: 10, y: 10, width: 100, height: 100)
            ),
            WindowSnapshot(
                ownerName: "Codex",
                layer: 3,
                isOnscreen: true,
                bounds: CGRect(x: 20, y: 20, width: 160, height: 150)
            ),
        ]

        let selected = CodexWindowSelector.selectAvatarWindow(from: windows, mascot: mascot)

        XCTAssertEqual(selected, CGRect(x: 20, y: 20, width: 160, height: 150))
    }

    func testSelectAvatarWindowFallsBackToSmallestCandidateWithoutMascotBounds() {
        let windows = [
            WindowSnapshot(
                ownerName: "Other",
                layer: 3,
                isOnscreen: true,
                bounds: CGRect(x: 0, y: 0, width: 90, height: 90)
            ),
            WindowSnapshot(
                ownerName: "Codex",
                layer: 3,
                isOnscreen: true,
                bounds: CGRect(x: 10, y: 10, width: 220, height: 220)
            ),
            WindowSnapshot(
                ownerName: "Codex",
                layer: 3,
                isOnscreen: true,
                bounds: CGRect(x: 20, y: 20, width: 120, height: 120)
            ),
        ]

        let selected = CodexWindowSelector.selectAvatarWindow(from: windows, mascot: nil)

        XCTAssertEqual(selected, CGRect(x: 20, y: 20, width: 120, height: 120))
    }

    func testConvertCGWindowRectToAppKitFrame() {
        let screens = [
            ScreenSnapshot(
                frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                displayBounds: CGRect(x: 0, y: 0, width: 1440, height: 900)
            ),
        ]

        let frame = WindowGeometryConverter.convertCGWindowRectToAppKitFrame(
            CGRect(x: 10, y: 20, width: 100, height: 200),
            screens: screens
        )

        XCTAssertEqual(frame, CGRect(x: 10, y: 680, width: 100, height: 200))
    }

    func testConvertCGWindowRectPrefersScreenContainingCenter() {
        let screens = [
            ScreenSnapshot(
                frame: CGRect(x: 0, y: 0, width: 100, height: 100),
                displayBounds: CGRect(x: 0, y: 0, width: 100, height: 100)
            ),
            ScreenSnapshot(
                frame: CGRect(x: 300, y: 200, width: 100, height: 100),
                displayBounds: CGRect(x: 100, y: 0, width: 100, height: 100)
            ),
        ]

        let frame = WindowGeometryConverter.convertCGWindowRectToAppKitFrame(
            CGRect(x: 90, y: 10, width: 40, height: 20),
            screens: screens
        )

        XCTAssertEqual(frame, CGRect(x: 290, y: 270, width: 40, height: 20))
    }

    func testUsageFreshnessPolicyMarksOldUsageStale() {
        let now = Date(timeIntervalSince1970: 1_000)
        let usage = UsageRings(
            shortWindow: RingWindow(usedPercent: 10, windowDurationMinutes: 300),
            longWindow: RingWindow(usedPercent: 20, windowDurationMinutes: 10_080),
            updatedAt: Date(timeIntervalSince1970: 850)
        )

        XCTAssertEqual(
            UsageFreshnessPolicy.displayState(for: usage, now: now, staleInterval: 120),
            .stale(usage)
        )
        XCTAssertEqual(
            UsageFreshnessPolicy.displayState(for: usage, now: now, staleInterval: 180),
            .current(usage)
        )
        XCTAssertEqual(
            UsageFreshnessPolicy.displayState(for: nil, now: now, staleInterval: 120),
            .loading
        )
    }

    func testJSONLineMessageParserIgnoresNonJSONProtocolNoise() throws {
        XCTAssertNil(JSONLineMessageParser.parseObject(from: Data("Codex warning on stdout".utf8)))

        let message = try XCTUnwrap(JSONLineMessageParser.parseObject(from: Data(#"{"id":2,"result":{"ok":true}}"#.utf8)))

        XCTAssertEqual(message["id"] as? Int, 2)
    }
}
