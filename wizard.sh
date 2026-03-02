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

# Get terminal dimensions with fallback
TERM_H=$(tput lines 2>/dev/null || echo 24)
TERM_W=$(tput cols 2>/dev/null || echo 80)
BOX_H=$((TERM_H - 4))
BOX_W=$((TERM_W - 10))

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

# Run a sub-script in a clean terminal view, then wait for user before returning
run_sub() {
    local title="$1"
    local script="$2"
    shift 2
    clear
    echo "=== ${title} ==="
    echo
    if bash "$script" "$@"; then
        echo
        echo "Done. Press Enter to return to the menu..."
    else
        echo
        echo "An error occurred. Press Enter to return to the menu..."
    fi
    read -r
}

handle_build() {
    local mode="${1:-client}"
    if oqs_is_built; then
        if ! whiptail --title "Evaemon v${VERSION}" \
            --yesno "OQS-OpenSSH is already built.\n\nRebuild anyway?" 9 52; then
            return 0
        fi
    fi
    clear
    echo "=== Building OQS-OpenSSH (${mode} mode) ==="
    echo
    if bash "${SCRIPT_DIR}/build_oqs_openssh.sh" "${mode}"; then
        echo
        echo "Build successful! Press Enter to continue..."
    else
        echo
        echo "Build failed. Please check the output above. Press Enter to continue..."
    fi
    read -r
}

handle_server_menu() {
    while true; do
        local choice
        choice=$(whiptail --title "Evaemon v${VERSION} - Server" \
            --menu "Server Configuration Options:" "$BOX_H" "$BOX_W" 7 \
            "1" "Build and install OQS-OpenSSH" \
            "2" "Configure Server" \
            "3" "Monitor sshd" \
            "4" "Update / Rebuild" \
            "5" "Diagnostics" \
            "6" "Back" \
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
        local choice
        choice=$(whiptail --title "Evaemon v${VERSION} - Client" \
            --menu "Client Configuration Options:" "$BOX_H" "$BOX_W" 11 \
            "1"  "Build and install OQS-OpenSSH" \
            "2"  "Generate Keys" \
            "3"  "Copy Key to Server" \
            "4"  "Connect to Server" \
            "5"  "Backup / Restore Keys" \
            "6"  "Health Check" \
            "7"  "Rotate Keys" \
            "8"  "Debug Tools" \
            "9"  "Performance Benchmark" \
            "10" "Back" \
            "11" "Exit" \
            3>&1 1>&2 2>&3) || return 0

        case "$choice" in
            1)  handle_build client ;;
            2)  run_sub "Key Generation"       "${SCRIPT_DIR}/client/keygen.sh" ;;
            3)  run_sub "Copy Key to Server"   "${SCRIPT_DIR}/client/copy_key_to_server.sh" ;;
            4)  run_sub "SSH Connection"       "${SCRIPT_DIR}/client/connect.sh" ;;
            5)  run_sub "Backup / Restore"     "${SCRIPT_DIR}/client/backup.sh" ;;
            6)  run_sub "Health Check"         "${SCRIPT_DIR}/client/health_check.sh" ;;
            7)  run_sub "Key Rotation"         "${SCRIPT_DIR}/client/key_rotation.sh" ;;
            8)  run_sub "Debug Tools"          "${SCRIPT_DIR}/client/tools/debug.sh" ;;
            9)  run_sub "Performance Benchmark" "${SCRIPT_DIR}/client/tools/performance_test.sh" ;;
            10) return 0 ;;
            11) exit 0 ;;
        esac
    done
}

main() {
    ensure_permissions

    while true; do
        local choice
        choice=$(whiptail --title "Evaemon v${VERSION}" \
            --menu "Is this machine a server or client?" "$BOX_H" "$BOX_W" 3 \
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
