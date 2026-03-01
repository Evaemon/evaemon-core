#!/bin/bash
set -eo pipefail

# Source shared configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../shared/config.sh"
source "${SCRIPT_DIR}/../shared/functions.sh"

connect() {
    echo "Post-Quantum SSH Connection Tool"
    echo "--------------------------------"

    read -rp "Enter the server IP address: " server_host
    validate_ip "$server_host" || exit 1

    read -rp "Enter the username: " username
    validate_username "$username" || exit 1

    read -rp "Enter the SSH port [22]: " port
    port=${port:-22}
    validate_port "$port" || exit 1

    echo -e "\nSelect connection mode:"
    echo "1. Post-quantum only"
    echo "2. Hybrid (post-quantum + classical)"
    read -rp "Mode (1-2) [1]: " conn_mode
    conn_mode="${conn_mode:-1}"

    echo -e "\nSelect the post-quantum algorithm:"
    list_algorithms
    read -rp "Enter algorithm number: " choice
    validate_algorithm_choice "$choice" "${#ALGORITHMS[@]}" || exit 1

    algorithm="${ALGORITHMS[$((choice-1))]}"
    key_path="${SSH_DIR}/id_${algorithm}"
    validate_file_exists "$key_path" || log_fatal "Key file not found: ${key_path}. Generate a key first."

    case "$conn_mode" in
        1)
            log_info "Connecting to ${username}@${server_host} using ${algorithm}..."
            SSH_AUTH_SOCK="" "${BIN_DIR}/ssh" \
                -o "KexAlgorithms=${PQ_KEX_LIST}" \
                -o "HostKeyAlgorithms=${algorithm}" \
                -o "PubkeyAcceptedKeyTypes=${algorithm}" \
                -i "${key_path}" \
                -p "${port}" \
                "${username}@${server_host}"
            ;;
        2)
            # In hybrid mode, KexAlgorithms and HostKeyAlgorithms include both
            # PQ and classical algorithms so the client interoperates with hybrid
            # servers.  User authentication still uses the PQ key.
            hybrid_algos="${algorithm},${CLASSICAL_HOST_ALGOS}"
            hybrid_kex="${PQ_KEX_LIST},${CLASSICAL_KEX_ALGORITHMS}"
            log_info "Connecting to ${username}@${server_host} using hybrid mode (${algorithm} + classical)..."
            SSH_AUTH_SOCK="" "${BIN_DIR}/ssh" \
                -o "KexAlgorithms=${hybrid_kex}" \
                -o "HostKeyAlgorithms=${hybrid_algos}" \
                -o "PubkeyAcceptedKeyTypes=${hybrid_algos}" \
                -i "${key_path}" \
                -p "${port}" \
                "${username}@${server_host}"
            ;;
        *)
            log_fatal "Invalid mode selection."
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    connect
fi