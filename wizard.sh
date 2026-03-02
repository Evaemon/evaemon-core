#!/bin/bash
set -eo pipefail

# Resolve the project root from the wizard's own location so the script works
# regardless of the current working directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

VERSION="1.0.0"
BUILD_LOG="${SCRIPT_DIR}/build/oqs_build.log"

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "This wizard must be run as root (sudo)."
    exit 1
fi

# Check whiptail availability
if ! command -v whiptail &>/dev/null; then
    echo "whiptail is required but not installed."
    echo "Install it with: apt install whiptail"
    exit 1
fi

# ── Branding ──────────────────────────────────────────────────────────────────
# Dark theme with cyan accents — "Evaemon: The last infrastructure."
export NEWT_COLORS='
root=brightcyan,black
border=cyan,black
window=white,black
shadow=black,black
title=brightwhite,black
button=black,cyan
actbutton=black,brightcyan
checkbox=cyan,black
actcheckbox=black,cyan
entry=brightwhite,black
label=cyan,black
listbox=brightwhite,black
actlistbox=black,cyan
textbox=brightwhite,black
acttextbox=brightwhite,blue
helpline=black,cyan
roottext=brightcyan,black
'

# ── Terminal dimensions ───────────────────────────────────────────────────────
# Enforce minimum sizes so menus are never clipped on small terminals.
TERM_H=$(tput lines 2>/dev/null || echo 24)
TERM_W=$(tput cols  2>/dev/null || echo 80)
BOX_H=$(( TERM_H > 24 ? TERM_H - 4 : 20 ))
BOX_W=$(( TERM_W > 60 ? TERM_W - 10 : 60 ))

# ── Helpers ───────────────────────────────────────────────────────────────────

ensure_permissions() {
    local scripts=(
        "${SCRIPT_DIR}/build_oqs_openssh.sh"
        "${SCRIPT_DIR}/server/server.sh"
        "${SCRIPT_DIR}/server/monitoring.sh"
        "${SCRIPT_DIR}/server/update.sh"
        "${SCRIPT_DIR}/server/tools/diagnostics.sh"
        "${SCRIPT_DIR}/client/keygen.sh"
        "${SCRIPT_DIR}/client/copy_key_to_server.sh"
        "${SCRIPT_DIR}/client/connect.sh"
        "${SCRIPT_DIR}/client/backup.sh"
        "${SCRIPT_DIR}/client/health_check.sh"
        "${SCRIPT_DIR}/client/key_rotation.sh"
        "${SCRIPT_DIR}/client/tools/debug.sh"
        "${SCRIPT_DIR}/client/tools/performance_test.sh"
    )
    for script in "${scripts[@]}"; do
        [ -f "$script" ] && chmod +x "$script"
    done
}

oqs_is_built() {
    [ -x "${SCRIPT_DIR}/build/bin/ssh" ]
}

_oqs_status_label() {
    if oqs_is_built; then echo "INSTALLED"; else echo "NOT BUILT"; fi
}

# ── Build (runs in background with a gauge) ───────────────────────────────────

# Emit progress percentages to stdout by inspecting the build log.
# Runs in a subshell (piped to whiptail --gauge); exits when build_pid ends.
_build_gauge() {
    local pid="$1"
    local pct=0
    while kill -0 "$pid" 2>/dev/null; do
        if   grep -q "Installation Complete"   "${BUILD_LOG}" 2>/dev/null; then pct=98
        elif grep -q "Setting up shared"       "${BUILD_LOG}" 2>/dev/null; then pct=85
        elif grep -q "make install"            "${BUILD_LOG}" 2>/dev/null; then pct=78
        elif grep -q "Building OpenSSH"        "${BUILD_LOG}" 2>/dev/null; then pct=55
        elif grep -q "Cloning OpenSSH"         "${BUILD_LOG}" 2>/dev/null; then pct=42
        elif grep -q "Building liboqs"         "${BUILD_LOG}" 2>/dev/null; then pct=18
        elif grep -q "Cloning liboqs"          "${BUILD_LOG}" 2>/dev/null; then pct=8
        elif grep -q "Installing dependencies" "${BUILD_LOG}" 2>/dev/null; then pct=3
        fi
        printf '%d\n' "$pct"
        sleep 1
    done
    printf '100\n'
}

handle_build() {
    local mode="${1:-client}"

    if oqs_is_built; then
        if ! whiptail --title "Evaemon v${VERSION}" \
                --yesno "OQS-OpenSSH is already built.\n\nRebuild from scratch?" 9 52; then
            return 0
        fi
    fi

    mkdir -p "${SCRIPT_DIR}/build"

    # Launch build in background; stdin closed so the test-suite prompt is
    # automatically skipped (the script detects non-interactive stdin).
    bash "${SCRIPT_DIR}/build_oqs_openssh.sh" "${mode}" </dev/null &
    local build_pid=$!

    # Feed progress numbers to whiptail gauge until the build finishes.
    _build_gauge "$build_pid" | \
        whiptail \
            --title "Evaemon — Compiling OQS Stack" \
            --gauge \
"  Building post-quantum cryptography stack...
  This takes 5-15 minutes on first run.

  Log: ${BUILD_LOG}" \
            11 64 0 2>/dev/null || true

    # Reap the background process and capture its exit code.
    local exit_code=0
    wait "$build_pid" || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        whiptail --title "Build Complete" \
            --msgbox \
"  OQS-OpenSSH installed successfully!

  You can now configure your server or generate
  post-quantum SSH keys." \
            10 52
    else
        if whiptail --title "Build Failed" \
                --yesno \
"  Build FAILED (exit code: ${exit_code}).

  View the build log?" \
                9 50; then
            if [[ -f "${BUILD_LOG}" ]]; then
                whiptail --title "Build Log" --scrolltext \
                    --textbox "${BUILD_LOG}" "$BOX_H" "$BOX_W"
            else
                whiptail --title "Build Log" \
                    --msgbox "  Log file not found:\n  ${BUILD_LOG}" 8 60
            fi
        fi
    fi
}

# ── Sub-script runner ─────────────────────────────────────────────────────────
# Interactive sub-scripts run in full terminal mode (they use read -rp).
# After they finish, a whiptail result box brings the user back into the TUI.

run_sub() {
    local title="$1"
    local script="$2"
    shift 2
    clear
    echo "=== ${title} ==="
    echo
    local exit_code=0
    bash "$script" "$@" || exit_code=$?
    echo
    if [[ $exit_code -eq 0 ]]; then
        whiptail --title "${title}" \
            --msgbox "  Completed successfully.\n\n  Press OK to return to the menu." \
            8 50 2>/dev/null \
            || { echo "Done. Press Enter to return..."; read -r; }
    else
        whiptail --title "${title}" \
            --msgbox \
"  An error occurred (exit code: ${exit_code}).

  Scroll up to review the output,
  then press OK to return to the menu." \
            10 54 2>/dev/null \
            || { echo "Error. Press Enter to return..."; read -r; }
    fi
}

# ── Menus ─────────────────────────────────────────────────────────────────────

handle_server_menu() {
    while true; do
        local build_label
        if oqs_is_built; then
            build_label="Build / Rebuild OQS-OpenSSH  [INSTALLED]"
        else
            build_label="Build OQS-OpenSSH             [NOT BUILT - START HERE]"
        fi

        local choice
        choice=$(whiptail --title "Evaemon v${VERSION} — Server" \
            --menu "Server Configuration:" "$BOX_H" "$BOX_W" 7 \
            "1" "${build_label}" \
            "2" "Configure sshd" \
            "3" "Monitor sshd" \
            "4" "Update / Rebuild" \
            "5" "Diagnostics" \
            "6" "Back to Main Menu" \
            "7" "Exit" \
            3>&1 1>&2 2>&3) || return 0

        case "$choice" in
            1) handle_build server ;;
            2) run_sub "Server Configuration" "${SCRIPT_DIR}/server/server.sh" ;;
            3) run_sub "sshd Monitor"         "${SCRIPT_DIR}/server/monitoring.sh" ;;
            4) run_sub "Update / Rebuild"     "${SCRIPT_DIR}/server/update.sh" ;;
            5) run_sub "Diagnostics"          "${SCRIPT_DIR}/server/tools/diagnostics.sh" ;;
            6) return 0 ;;
            7) exit 0 ;;
        esac
    done
}

handle_client_menu() {
    while true; do
        local build_label
        if oqs_is_built; then
            build_label="Build / Rebuild OQS-OpenSSH  [INSTALLED]"
        else
            build_label="Build OQS-OpenSSH             [NOT BUILT - START HERE]"
        fi

        local choice
        choice=$(whiptail --title "Evaemon v${VERSION} — Client" \
            --menu "Client Configuration:" "$BOX_H" "$BOX_W" 11 \
            "1"  "${build_label}" \
            "2"  "Generate Keys" \
            "3"  "Copy Key to Server" \
            "4"  "Connect to Server" \
            "5"  "Backup / Restore Keys" \
            "6"  "Health Check" \
            "7"  "Rotate Keys" \
            "8"  "Debug Tools" \
            "9"  "Performance Benchmark" \
            "10" "Back to Main Menu" \
            "11" "Exit" \
            3>&1 1>&2 2>&3) || return 0

        case "$choice" in
            1)  handle_build client ;;
            2)  run_sub "Key Generation"        "${SCRIPT_DIR}/client/keygen.sh" ;;
            3)  run_sub "Copy Key to Server"    "${SCRIPT_DIR}/client/copy_key_to_server.sh" ;;
            4)  run_sub "SSH Connection"        "${SCRIPT_DIR}/client/connect.sh" ;;
            5)  run_sub "Backup / Restore"      "${SCRIPT_DIR}/client/backup.sh" ;;
            6)  run_sub "Health Check"          "${SCRIPT_DIR}/client/health_check.sh" ;;
            7)  run_sub "Key Rotation"          "${SCRIPT_DIR}/client/key_rotation.sh" ;;
            8)  run_sub "Debug Tools"           "${SCRIPT_DIR}/client/tools/debug.sh" ;;
            9)  run_sub "Performance Benchmark" "${SCRIPT_DIR}/client/tools/performance_test.sh" ;;
            10) return 0 ;;
            11) exit 0 ;;
        esac
    done
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
    ensure_permissions

    # Welcome screen — shown once at startup, not on every loop iteration.
    whiptail --title "Evaemon v${VERSION}" \
        --msgbox \
"          Evaemon
    The last infrastructure.

  Post-quantum SSH hardening for systems that
  cannot afford to be compromised tomorrow.

  Powered by OQS-OpenSSH with NIST-standardised
  algorithms: ML-DSA, Falcon, MAYO and more.

  Run 'Build OQS-OpenSSH' first if this is a
  new installation." \
        16 56

    while true; do
        local oqs_status menu_text
        oqs_status="$(_oqs_status_label)"
        if oqs_is_built; then
            menu_text="  OQS-OpenSSH: ${oqs_status}\n\n  Select the role of this machine:"
        else
            menu_text="  OQS-OpenSSH: ${oqs_status}\n  Run Build first after selecting a role.\n\n  Select the role of this machine:"
        fi

        local choice
        choice=$(whiptail --title "Evaemon v${VERSION}" \
            --menu "${menu_text}" "$BOX_H" "$BOX_W" 3 \
            "1" "Server" \
            "2" "Client" \
            "3" "Exit" \
            3>&1 1>&2 2>&3) || exit 0

        case "$choice" in
            1) handle_server_menu ;;
            2) handle_client_menu ;;
            3) exit 0 ;;
        esac
    done
}

main
