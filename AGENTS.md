# AGENTS.md

## Project Scope

This repository contains a native macOS companion overlay for the Codex Desktop pet overlay. It must stay separate from the Codex app bundle.

## Safety And Compliance

- Do not patch, unpack, repack, modify, inject into, or redistribute Codex Desktop or any OpenAI-owned application bundle.
- Do not reverse engineer OpenAI services or ship code derived from OpenAI application bundles.
- Do not bypass, hide, reset, or circumvent OpenAI usage limits. The overlay is display-only.
- Treat the Codex local app-server rate-limit method as an undocumented integration point. Keep failures graceful and visible.
- Keep the project clearly marked as unofficial and unaffiliated with OpenAI.
- Do not use OpenAI logos or imply endorsement.

## Engineering Defaults

- Prefer small, reviewable changes.
- Keep the app native macOS Swift/AppKit unless a supported public API makes another target possible.
- Do not add dependencies without a short maintenance, security, license, and adoption check.
- Run `swift build` before handoff for source changes.
- When changing behavior, update `README.md`.

## UX Defaults

- The overlay must be mouse-transparent so it does not interfere with dragging or clicking the Codex pet.
- The overlay must hide itself when the Codex avatar overlay window is not visible.
- Avoid visual clutter. The pet should remain the primary visual object.

## Release Checklist

- Use the public name "Codex Pet Ring Overlay" and repository slug `codex-pet-ring-overlay`.
- Keep repository language concise: "unofficial companion for Codex Desktop", "not affiliated with OpenAI", "does not modify Codex Desktop", and "does not bypass or circumvent rate limits".
- Mention that the app is built around the documented Codex Pets feature without implying OpenAI endorsement or integration.
- Add or refresh a screenshot or short GIF in `README.md` when preparing a release.
