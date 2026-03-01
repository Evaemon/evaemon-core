#!/bin/bash
set -eo pipefail

# Resolve the project root from the wizard's own location so the script works
# regardless of the current working directory (M3 fix).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "This wizard must be run as root (sudo)."
    exit 1
fi

# Ensure scripts have execution permissions
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
        if [ -f "$script" ]; then
            chmod +x "$script"
        else
            echo "Error: $script not found"
            exit 1
        fi
    done
}

print_header() {
    clear
    echo "================================================"
    echo "              Evaemon Wizard"
    echo "================================================"
    echo
}

show_mode_selection() {
    echo "Is this machine a server or client?"
    echo "1. Server"
    echo "2. Client"
    echo "3. Exit"
    echo
}

show_server_menu() {
    echo "Server Configuration Options:"
    echo "1. Build and install OQS-OpenSSH"
    echo "2. Configure Server"
    echo "3. Monitor sshd"
    echo "4. Update / Rebuild"
    echo "5. Diagnostics"
    echo "6. Back to mode selection"
    echo "7. Exit"
    echo
}

show_client_menu() {
    echo "Client Configuration Options:"
    echo "1. Build and install OQS-OpenSSH"
    echo "2. Generate Keys"
    echo "3. Copy Key to Server"
    echo "4. Connect to Server"
    echo "5. Backup / Restore Keys"
    echo "6. Health Check"
    echo "7. Rotate Keys"
    echo "8. Debug Tools"
    echo "9. Performance Benchmark"
    echo "10. Back to mode selection"
    echo "11. Exit"
    echo
}

handle_build() {
    echo "Starting OQS-OpenSSH build process..."
    if bash "${SCRIPT_DIR}/build_oqs_openssh.sh"; then
        echo "Build completed successfully!"
    else
        echo "Build process failed. Please check the logs."
        exit 1
    fi
}

handle_server() {
    echo "Starting server configuration..."
    bash "${SCRIPT_DIR}/server/server.sh"
}

handle_monitoring() {
    echo "Starting sshd monitor..."
    bash "${SCRIPT_DIR}/server/monitoring.sh"
}

handle_update() {
    echo "Starting update process..."
    bash "${SCRIPT_DIR}/server/update.sh"
}

handle_diagnostics() {
    echo "Starting diagnostics..."
    bash "${SCRIPT_DIR}/server/tools/diagnostics.sh"
}

handle_keygen() {
    echo "Starting key generation..."
    bash "${SCRIPT_DIR}/client/keygen.sh"
}

handle_copy_key() {
    echo "Starting key copy process..."
    bash "${SCRIPT_DIR}/client/copy_key_to_server.sh"
}

handle_connect() {
    echo "Starting SSH connection..."
    bash "${SCRIPT_DIR}/client/connect.sh"
}

handle_backup() {
    echo "Starting backup/restore tool..."
    bash "${SCRIPT_DIR}/client/backup.sh"
}

handle_health_check() {
    echo "Starting health check..."
    bash "${SCRIPT_DIR}/client/health_check.sh"
}

handle_key_rotation() {
    echo "Starting key rotation..."
    bash "${SCRIPT_DIR}/client/key_rotation.sh"
}

handle_debug() {
    echo "Starting debug tool..."
    bash "${SCRIPT_DIR}/client/tools/debug.sh"
}

handle_performance_test() {
    echo "Starting performance benchmark..."
    bash "${SCRIPT_DIR}/client/tools/performance_test.sh"
}

handle_server_menu() {
    while true; do
        print_header
        show_server_menu
        read -rp "Enter your choice: " choice
        echo

        case $choice in
            1)
                handle_build
                read -rp "Press Enter to continue..."
                ;;
            2)
                handle_server
                read -rp "Press Enter to continue..."
                ;;
            3)
                handle_monitoring
                read -rp "Press Enter to continue..."
                ;;
            4)
                handle_update
                read -rp "Press Enter to continue..."
                ;;
            5)
                handle_diagnostics
                read -rp "Press Enter to continue..."
                ;;
            6)
                return
                ;;
            7)
                echo "Thank you for using Evaemon!"
                exit 0
                ;;
            *)
                echo "Invalid choice. Please try again."
                read -rp "Press Enter to continue..."
                ;;
        esac
    done
}

handle_client_menu() {
    while true; do
        print_header
        show_client_menu
        read -rp "Enter your choice: " choice
        echo

        case $choice in
            1)
                handle_build
                read -rp "Press Enter to continue..."
                ;;
            2)
                handle_keygen
                read -rp "Press Enter to continue..."
                ;;
            3)
                handle_copy_key
                read -rp "Press Enter to continue..."
                ;;
            4)
                handle_connect
                read -rp "Press Enter to continue..."
                ;;
            5)
                handle_backup
                read -rp "Press Enter to continue..."
                ;;
            6)
                handle_health_check
                read -rp "Press Enter to continue..."
                ;;
            7)
                handle_key_rotation
                read -rp "Press Enter to continue..."
                ;;
            8)
                handle_debug
                read -rp "Press Enter to continue..."
                ;;
            9)
                handle_performance_test
                read -rp "Press Enter to continue..."
                ;;
            10)
                return
                ;;
            11)
                echo "Thank you for using Evaemon!"
                exit 0
                ;;
            *)
                echo "Invalid choice. Please try again."
                read -rp "Press Enter to continue..."
                ;;
        esac
    done
}

main() {
    # Check and set permissions at startup
    ensure_permissions

    while true; do
        print_header
        show_mode_selection
        read -rp "Enter your choice (1-3): " mode_choice
        echo

        case $mode_choice in
            1)
                handle_server_menu
                ;;
            2)
                handle_client_menu
                ;;
            3)
                echo "Thank you for using Evaemon!"
                exit 0
                ;;
            *)
                echo "Invalid choice. Please try again."
                read -rp "Press Enter to continue..."
                ;;
        esac
    done
}

main
