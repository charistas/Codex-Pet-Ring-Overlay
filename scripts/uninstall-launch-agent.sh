#!/usr/bin/env bash
set -euo pipefail

label="com.charistas.codex-pet-ring-overlay"
plist_path="${HOME}/Library/LaunchAgents/${label}.plist"
app_support_dir="${HOME}/Library/Application Support/Codex Pet Ring Overlay"
binary_path="${app_support_dir}/codex-pet-ring-overlay"

launchctl bootout "gui/$(id -u)/${label}" >/dev/null 2>&1 || true
rm -f "${plist_path}" "${binary_path}" "${app_support_dir}/overlay.log" "${app_support_dir}/overlay.err.log"
if ! rmdir "${app_support_dir}" >/dev/null 2>&1 && [[ -d "${app_support_dir}" ]]; then
  echo "Left ${app_support_dir} in place because it contains unrelated files." >&2
fi

echo "Unloaded ${label} and removed the LaunchAgent, installed binary, and app logs."
