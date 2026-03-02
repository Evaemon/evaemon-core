#!/bin/bash
set -eo pipefail

# Resolve the project root from the wizard's own location so the script works
# regardless of the current working directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

VERSION="1.0.0"

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

# Get terminal dimensions with fallback and minimum values so whiptail
# menus are never smaller than their content.
TERM_H=$(tput lines 2>/dev/null || echo 24)
TERM_W=$(tput cols 2>/dev/null || echo 80)
BOX_H=$(( TERM_H > 24 ? TERM_H - 4 : 20 ))
BOX_W=$(( TERM_W > 60 ? TERM_W - 10 : 60 ))

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

# Return a short human-readable OQS build status string.
_oqs_status_label() {
    if oqs_is_built; then
        echo "INSTALLED"
    else
        echo "NOT BUILT"
    fi
}

# Run a sub-script in a clean terminal view, then show a whiptail result box
# before returning to the menu.
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
            --msgbox "Completed successfully.\n\nPress OK to return to the menu." \
            8 52 2>/dev/null \
            || { echo "Done. Press Enter to return..."; read -r; }
    else
        whiptail --title "${title}" \
            --msgbox "An error occurred (exit code: ${exit_code}).\n\nScroll up to review the output above,\nthen press OK to return to the menu." \
            10 56 2>/dev/null \
            || { echo "Error occurred. Press Enter to return..."; read -r; }
    fi
}

handle_build() {
    local mode="${1:-client}"
    if oqs_is_built; then
        if ! whiptail --title "Evaemon v${VERSION}" \
            --yesno "OQS-OpenSSH is already built.\n\nRebuild from scratch?" 9 52; then
            return 0
        fi
    fi
    clear
    echo "=== Building OQS-OpenSSH (${mode} mode) ==="
    echo
    if bash "${SCRIPT_DIR}/build_oqs_openssh.sh" "${mode}"; then
        echo
        whiptail --title "Build OQS-OpenSSH" \
            --msgbox "Build successful!\n\nPress OK to return to the menu." \
            8 48 2>/dev/null \
            || { echo "Build successful! Press Enter to continue..."; read -r; }
    else
        whiptail --title "Build OQS-OpenSSH" \
            --msgbox "Build FAILED.\n\nScroll up to check the compiler output,\nthen press OK to return to the menu." \
            10 56 2>/dev/null \
            || { echo "Build failed. Press Enter to continue..."; read -r; }
    fi
}

handle_server_menu() {
    while true; do
        # Recompute build label on every iteration so it reflects the current state.
        local build_label
        if oqs_is_built; then
            build_label="Build / Rebuild OQS-OpenSSH  [INSTALLED]"
        else
            build_label="Build OQS-OpenSSH             [NOT BUILT - START HERE]"
        fi

        local choice
        choice=$(whiptail --title "Evaemon v${VERSION} - Server" \
            --menu "Server Configuration Options:" "$BOX_H" "$BOX_W" 7 \
            "1" "${build_label}" \
            "2" "Configure Server" \
            "3" "Monitor sshd" \
            "4" "Update / Rebuild" \
            "5" "Diagnostics" \
            "6" "Back to Main Menu" \
            "7" "Exit" \
            3>&1 1>&2 2>&3) || return 0

        case "$choice" in
            1) handle_build server ;;
            2) run_sub "Server Configuration" "${SCRIPT_DIR}/server/server.sh" ;;
            3) run_sub "sshd Monitor"          "${SCRIPT_DIR}/server/monitoring.sh" ;;
            4) run_sub "Update / Rebuild"      "${SCRIPT_DIR}/server/update.sh" ;;
            5) run_sub "Diagnostics"           "${SCRIPT_DIR}/server/tools/diagnostics.sh" ;;
            6) return 0 ;;
            7) exit 0 ;;
        esac
    done
}

handle_client_menu() {
    while true; do
        # Recompute build label on every iteration so it reflects the current state.
        local build_label
        if oqs_is_built; then
            build_label="Build / Rebuild OQS-OpenSSH  [INSTALLED]"
        else
            build_label="Build OQS-OpenSSH             [NOT BUILT - START HERE]"
        fi

        local choice
        choice=$(whiptail --title "Evaemon v${VERSION} - Client" \
            --menu "Client Configuration Options:" "$BOX_H" "$BOX_W" 11 \
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

main() {
    ensure_permissions

    while true; do
        # Show OQS build status in the menu description so the user immediately
        # knows whether to run Build first.
        local oqs_status menu_text
        oqs_status="$(_oqs_status_label)"
        if oqs_is_built; then
            menu_text="OQS-OpenSSH: ${oqs_status}\n\nIs this machine a server or a client?"
        else
            menu_text="OQS-OpenSSH: ${oqs_status}\nRun 'Build OQS-OpenSSH' first!\n\nIs this machine a server or a client?"
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
