# Codex Pet Ring Overlay

Codex Pet Ring Overlay is an unofficial native macOS companion for Codex Desktop. It draws two live usage rings around the floating Codex pet overlay without modifying Codex Desktop.

It depends on undocumented local Codex state and rate-limit behavior, so it may break when Codex changes. If OpenAI publishes guidance that disallows this integration pattern, this project should be changed or removed.

- Outer ring: short Codex usage window, typically 5 hours
- Inner ring: long Codex usage window, typically weekly
- Blue/green: normal usage
- Yellow: high usage
- Red: near or at limit
- Usage changes, loading pulses, and critical pulses animate smoothly unless macOS Reduce Motion is enabled
- Subtle halo strokes and loading pulses keep the rings readable on varied desktop backgrounds
- Stale usage data dims after repeated refresh failures instead of continuing to look current
- Extra ring padding and a thinner inner ring leave room for Codex's own pet badges

![Codex Pet Ring Overlay screenshot](assets/screenshot.png)

The screenshot uses Danny, a custom Codex pet based on my dog. You can install Danny from [Petdex](https://petdex.crafter.run/pets/danny). The overlay works with any floating Codex pet.

## Platform

This project is macOS-only because it depends on macOS APIs such as AppKit windows and CoreGraphics window metadata.

## Compatibility And Boundaries

OpenAI's Codex app settings documentation describes [Codex pets](https://developers.openai.com/codex/app/settings#codex-pets) as optional animated companions for the Codex app, including a floating overlay that can be toggled from the app.

This project is built around that visible Codex pet overlay. It adds a separate, external, display-only macOS window around the pet. It is not built by, affiliated with, or endorsed by OpenAI.

The overlay:

- Does not modify Codex Desktop, Codex pets, or any OpenAI-owned app bundle.
- Does not unpack, patch, repack, redistribute, or inject code into Codex Desktop.
- Does not bypass, reset, hide, or circumvent rate limits.
- Does not use OpenAI logos or artwork.
- Uses macOS window metadata exposed by the operating system.

## How It Works

The app runs as a separate transparent, borderless, mouse-pass-through macOS window. It:

1. Finds the visible Codex avatar overlay window using public macOS window metadata.
2. Reads Codex's persisted avatar overlay bounds from `~/.codex/.codex-global-state.json`.
3. Aligns its own transparent window around the pet's mascot rectangle, falling back to the visible overlay window during brief local state-file gaps or stale bounds that no longer fit the visible Codex window.
4. Asks the local Codex CLI/app-server for rate-limit status on an adaptive schedule.
5. Draws the 5-hour and weekly rings from the returned usage percentages, with animated changes, contrast halos, severity thickness, and critical pulses.
6. Hides itself when the Codex avatar overlay window is not visible.

## Privacy

The overlay itself does not send telemetry, read chat transcripts, or make direct third-party network requests. It reads local Codex avatar-position state and asks the local Codex CLI/app-server for rate-limit status. That Codex-owned process may communicate with OpenAI according to Codex's normal behavior. Overlay logs stay on the local machine, and rate-limit protocol diagnostics summarize response keys instead of logging raw app-server stdout.

## Build

Requirements:

- macOS 13 or later
- Xcode command line tools
- Codex Desktop with the floating Codex pet overlay enabled
- Codex Desktop installed at `/Applications/Codex.app`, or a `codex` binary available on `PATH`

Build locally:

```bash
swift build -c release
```

Run from the repository:

```bash
swift run codex-pet-ring-overlay
```

## Install As A User LaunchAgent

The install script builds the release binary, copies it under `~/Library/Application Support/Codex Pet Ring Overlay`, resolves the Codex CLI binary, warns if Codex local state is not present yet, and loads a per-user LaunchAgent. `CODEX_HOME` is only used to tell the overlay where to read Codex's local state.

```bash
./scripts/install-launch-agent.sh
```

If Codex is not installed at `/Applications/Codex.app` and `codex` is not on your current shell `PATH`, pass the CLI path during install:

```bash
CODEX_BIN=/path/to/codex ./scripts/install-launch-agent.sh
```

If you use a non-default Codex home, pass it during install:

```bash
CODEX_HOME=/path/to/codex-home ./scripts/install-launch-agent.sh
```

Stop and unload:

```bash
./scripts/uninstall-launch-agent.sh
```

Logs:

```text
~/Library/Application Support/Codex Pet Ring Overlay/overlay.log
~/Library/Application Support/Codex Pet Ring Overlay/overlay.err.log
```

The uninstall script unloads the LaunchAgent and removes the plist, installed binary, and app logs. If the Application Support directory contains unrelated files, the directory itself is left in place.

## Options

```bash
codex-pet-ring-overlay --help
```

Supported options:

- `--codex-home PATH`: Codex home directory. Defaults to `~/.codex` or `CODEX_HOME`.
- `--codex-bin PATH`: Codex CLI binary. Defaults to `/Applications/Codex.app/Contents/Resources/codex`.

## Troubleshooting

- No rings appear: confirm Codex Desktop is running and the floating pet overlay is visible. In Codex settings, go to Appearance > Pets, or use `/pet` in the composer.
- `Codex binary not found or not executable`: install Codex Desktop in `/Applications`, put `codex` on `PATH`, or run with `--codex-bin PATH`.
- Rings are misplaced: Codex's local avatar bounds format or macOS display geometry may have changed, or the app may be using the temporary whole-window fallback while bounds are unavailable or stale. Check the logs listed above.
- Usage does not update: the undocumented local rate-limit method may have changed. The overlay refreshes immediately when the pet appears, about every 60 seconds while visible and healthy, and backs off while hidden or after failures. Last-known usage dims once it is stale. Check `overlay.err.log`.
- LaunchAgent status: run `launchctl print gui/$(id -u)/com.charistas.codex-pet-ring-overlay`.

## Limitations

- The overlay is visually external, even though it is aligned to look integrated.
- It depends on Codex Desktop keeping the floating avatar as a separate small window.
- It depends on Codex continuing to persist avatar overlay bounds in `~/.codex/.codex-global-state.json`.
- It refreshes rate limits adaptively: about every 60 seconds while the pet is visible and healthy, every 5 minutes while hidden, with exponential backoff after failures.
- The local rate-limit method is undocumented and may change.

## Credits

Concept credit: [Peter Gostev (@petergostev)](https://x.com/petergostev/status/2051076960911077796), whose X/Twitter post surfaced the usage-ring idea around the Codex pet.

This implementation is independent and unofficial. It does not copy code, assets, or app-bundle files from Codex Desktop or from the referenced post.
