#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
SOURCE_DIR="${SCRIPT_DIR}/hover-helper"
APP_NAME="Codex Hover Translator"
EXECUTABLE_NAME="CodexHoverTranslator"
BUNDLED_APP="${SCRIPT_DIR}/bundled/macos/${APP_NAME}.app"
INSTALL_ROOT="${HOME}/Applications"
APP_BUNDLE="${INSTALL_ROOT}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
LAUNCH_AGENT="${HOME}/Library/LaunchAgents/local.codex.bilingual-hover.plist"
STATE_FILE="/tmp/codex-hover-translator-state.json"

build_and_install() {
  if [[ -d "${BUNDLED_APP}" ]]; then
    mkdir -p "${INSTALL_ROOT}"
    ditto "${BUNDLED_APP}" "${APP_BUNDLE}"
    echo "Installed bundled app: ${APP_BUNDLE}"
    return
  fi

  xcrun swift build -c release --package-path "${SOURCE_DIR}"
  local binary
  binary="$(xcrun swift build -c release --package-path "${SOURCE_DIR}" --show-bin-path)/${EXECUTABLE_NAME}"

  mkdir -p "${CONTENTS_DIR}/MacOS"
  cp "${binary}" "${CONTENTS_DIR}/MacOS/${EXECUTABLE_NAME}"
  cp "${SOURCE_DIR}/Info.plist" "${CONTENTS_DIR}/Info.plist"
  chmod 755 "${CONTENTS_DIR}/MacOS/${EXECUTABLE_NAME}"
  codesign --force --deep --sign - "${APP_BUNDLE}" >/dev/null
  echo "Installed: ${APP_BUNDLE}"
}

start_app() {
  open "${APP_BUNDLE}"
  sleep 1
  if pgrep -x "${EXECUTABLE_NAME}" >/dev/null; then
    echo "Running: ${APP_BUNDLE}"
  else
    echo "Failed to start: ${APP_BUNDLE}" >&2
    exit 1
  fi
}

stop_app() {
  if pgrep -x "${EXECUTABLE_NAME}" >/dev/null; then
    pkill -x "${EXECUTABLE_NAME}"
    echo "Stopped: ${APP_NAME}"
  else
    echo "Already stopped: ${APP_NAME}"
  fi
}

write_launch_agent() {
  mkdir -p "${HOME}/Library/LaunchAgents"
  /usr/libexec/PlistBuddy -c 'Clear dict' "${LAUNCH_AGENT}" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c 'Add :Label string local.codex.bilingual-hover' "${LAUNCH_AGENT}"
  /usr/libexec/PlistBuddy -c 'Add :ProgramArguments array' "${LAUNCH_AGENT}"
  /usr/libexec/PlistBuddy -c "Add :ProgramArguments:0 string ${CONTENTS_DIR}/MacOS/${EXECUTABLE_NAME}" "${LAUNCH_AGENT}"
  /usr/libexec/PlistBuddy -c 'Add :RunAtLoad bool true' "${LAUNCH_AGENT}"
  /usr/libexec/PlistBuddy -c 'Add :KeepAlive bool false' "${LAUNCH_AGENT}"
  launchctl bootout "gui/${UID}" "${LAUNCH_AGENT}" 2>/dev/null || true
  launchctl bootstrap "gui/${UID}" "${LAUNCH_AGENT}"
  echo "Launch at login enabled."
}

case "${1:-}" in
  install)
    build_and_install
    ;;
  start)
    [[ -x "${CONTENTS_DIR}/MacOS/${EXECUTABLE_NAME}" ]] || build_and_install
    start_app
    ;;
  stop)
    stop_app
    ;;
  restart)
    stop_app
    start_app
    ;;
  status)
    if pgrep -x "${EXECUTABLE_NAME}" >/dev/null; then
      echo "running"
    else
      echo "stopped"
    fi
    [[ -x "${CONTENTS_DIR}/MacOS/${EXECUTABLE_NAME}" ]] && echo "installed: ${APP_BUNDLE}" || echo "not installed"
    if pgrep -x "${EXECUTABLE_NAME}" >/dev/null && [[ -f "${STATE_FILE}" ]]; then
      echo "accessibility: $(plutil -extract accessibility raw "${STATE_FILE}" 2>/dev/null || echo unknown)"
      echo "screen-capture: $(plutil -extract screenCapture raw "${STATE_FILE}" 2>/dev/null || echo unknown)"
    elif [[ -x "${CONTENTS_DIR}/MacOS/${EXECUTABLE_NAME}" ]]; then
      echo "accessibility: not checked (helper is stopped)"
    fi
    [[ -f "${LAUNCH_AGENT}" ]] && echo "autostart: enabled" || echo "autostart: disabled"
    ;;
  permission-settings)
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    ;;
  screen-recording-settings)
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    ;;
  enable-autostart)
    [[ -x "${CONTENTS_DIR}/MacOS/${EXECUTABLE_NAME}" ]] || build_and_install
    write_launch_agent
    ;;
  disable-autostart)
    launchctl bootout "gui/${UID}" "${LAUNCH_AGENT}" 2>/dev/null || true
    rm -f "${LAUNCH_AGENT}"
    echo "Launch at login disabled."
    ;;
  uninstall)
    stop_app
    launchctl bootout "gui/${UID}" "${LAUNCH_AGENT}" 2>/dev/null || true
    rm -f "${LAUNCH_AGENT}"
    rm -rf "${APP_BUNDLE}"
    echo "Uninstalled: ${APP_BUNDLE}"
    ;;
  *)
    echo "Usage: $0 {install|start|stop|restart|status|permission-settings|screen-recording-settings|enable-autostart|disable-autostart|uninstall}" >&2
    exit 2
    ;;
esac
