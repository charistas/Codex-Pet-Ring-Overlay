#!/usr/bin/env bash
set -euo pipefail

label="com.charistas.codex-pet-ring-overlay"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
launch_agents_dir="${HOME}/Library/LaunchAgents"
plist_path="${launch_agents_dir}/${label}.plist"
default_codex_binary="/Applications/Codex.app/Contents/Resources/codex"
app_support_dir="${HOME}/Library/Application Support/Codex Pet Ring Overlay"

expand_path() {
  local value="${1}"
  case "${value}" in
    "~")
      printf '%s\n' "${HOME}"
      ;;
    "~/"*)
      printf '%s/%s\n' "${HOME}" "${value#~/}"
      ;;
    *)
      printf '%s\n' "${value}"
      ;;
  esac
}

xml_escape() {
  local value="${1}"
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  printf '%s' "${value}"
}

resolve_codex_binary() {
  if [[ -n "${CODEX_BIN:-}" ]]; then
    if [[ -x "${CODEX_BIN}" ]]; then
      printf '%s\n' "${CODEX_BIN}"
      return
    fi
    echo "CODEX_BIN is set but is not executable: ${CODEX_BIN}" >&2
    return 1
  fi

  if [[ -x "${default_codex_binary}" ]]; then
    printf '%s\n' "${default_codex_binary}"
    return
  fi

  if command -v codex >/dev/null 2>&1; then
    command -v codex
    return
  fi

  echo "Codex binary not found. Install Codex Desktop in /Applications, put codex on PATH, or run with CODEX_BIN=/path/to/codex." >&2
  return 1
}

codex_home="$(expand_path "${CODEX_HOME:-${HOME}/.codex}")"
binary_path="${app_support_dir}/codex-pet-ring-overlay"
codex_binary="$(resolve_codex_binary)"
binary_path_xml="$(xml_escape "${binary_path}")"
codex_binary_xml="$(xml_escape "${codex_binary}")"
codex_home_xml="$(xml_escape "${codex_home}")"
app_support_dir_xml="$(xml_escape "${app_support_dir}")"

cd "${repo_root}"
swift build -c release

mkdir -p "${app_support_dir}" "${launch_agents_dir}"
cp ".build/release/codex-pet-ring-overlay" "${binary_path}"
chmod 755 "${binary_path}"

cat > "${plist_path}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${label}</string>

  <key>ProgramArguments</key>
  <array>
    <string>${binary_path_xml}</string>
    <string>--codex-bin</string>
    <string>${codex_binary_xml}</string>
    <string>--codex-home</string>
    <string>${codex_home_xml}</string>
  </array>

  <key>RunAtLoad</key>
  <true/>

  <key>StandardOutPath</key>
  <string>${app_support_dir_xml}/overlay.log</string>

  <key>StandardErrorPath</key>
  <string>${app_support_dir_xml}/overlay.err.log</string>
</dict>
</plist>
PLIST

plutil -lint "${plist_path}"
launchctl bootout "gui/$(id -u)/${label}" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "${plist_path}"
launchctl enable "gui/$(id -u)/${label}"
launchctl kickstart -k "gui/$(id -u)/${label}"

echo "Installed and started ${label}."
echo "Binary: ${binary_path}"
echo "Logs: ${app_support_dir}/overlay.log and ${app_support_dir}/overlay.err.log"
