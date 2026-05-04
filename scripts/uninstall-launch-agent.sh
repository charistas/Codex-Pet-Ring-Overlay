#!/usr/bin/env bash
set -euo pipefail

label="com.charistas.codex-pet-ring-overlay"
plist_path="${HOME}/Library/LaunchAgents/${label}.plist"
app_support_dir="${HOME}/Library/Application Support/Codex Pet Ring Overlay"
binary_path="${app_support_dir}/codex-pet-ring-overlay"

launchctl bootout "gui/$(id -u)/${label}" >/dev/null 2>&1 || true
rm -f "${plist_path}" "${binary_path}"
rmdir "${app_support_dir}" >/dev/null 2>&1 || true

echo "Unloaded ${label} and removed the LaunchAgent and installed binary."
