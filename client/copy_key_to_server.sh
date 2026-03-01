#!/bin/bash
set -eo pipefail

# Source shared configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../shared/config.sh"
source "${SCRIPT_DIR}/../shared/functions.sh"

list_keys() {
    echo "Available public keys in ${SSH_DIR}:"
    local keys=()
    while IFS= read -r -d '' f; do
        keys+=("$f")
    done < <(find "${SSH_DIR}" -maxdepth 1 -name "*.pub" -print0 2>/dev/null | sort -z)
    if [[ ${#keys[@]} -eq 0 ]]; then
        echo "No public keys found in ${SSH_DIR}. Please generate a key first."
        exit 1
    fi
    for i in "${!keys[@]}"; do
        echo "$((i+1)). ${keys[$i]}"
    done
    echo "Select a key by number:"
}

copy_client_key() {
    local server_host="$1"
    local server_user="$2"
    local public_key_file="$3"
    local server_port="$4"
    local algorithm="$5"
    
    # Get private key path by removing .pub extension
    local private_key_file="${public_key_file%.pub}"

    validate_file_exists "${public_key_file}" || exit 1
    log_info "Copying public key to ${server_user}@${server_host}..."

    # Stream the public key file directly over SSH without loading it into a
    # shell variable (avoids exposure via /proc/<pid>/environ or 'ps' output).
    #
    # Bootstrap note: this is the first connection to the server, so we cannot
    # assume the server already presents a PQ host key.  Use a combined KEX list
    # (PQ preferred, classical as fallback) and leave HostKeyAlgorithms
    # unrestricted so the connection succeeds whether the server is running OQS
    # or standard OpenSSH.  PubkeyAcceptedKeyTypes is still set so we try the
    # PQ key first; SSH falls back to password auth if the key is not yet in
    # authorized_keys.
    "${BIN_DIR}/ssh" -i "${private_key_file}" \
                     -o "KexAlgorithms=${PQ_KEX_LIST},${CLASSICAL_KEX_ALGORITHMS}" \
                     -o "PubkeyAcceptedKeyTypes=${algorithm}" \
                     -p "${server_port}" \
                     "${server_user}@${server_host}" \
                     'mkdir -p ~/.ssh && chmod 700 ~/.ssh && \
                      touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && \
                      key=$(cat) && \
                      if grep -qF "$key" ~/.ssh/authorized_keys 2>/dev/null; then \
                          echo "Key already exists in authorized_keys."; \
                      else \
                          printf "%s\n" "$key" >> ~/.ssh/authorized_keys && \
                          echo "Key added to authorized_keys."; \
                      fi' \
                     < "${public_key_file}"
}

main() {
    echo "Copy Client Key to Server"
    read -rp "Enter the server IP address: " server_host
    validate_ip "$server_host" || exit 1

    read -rp "Enter the server username: " server_user
    validate_username "$server_user" || exit 1

    read -rp "Enter the server SSH port [22]: " server_port
    server_port=${server_port:-22}
    validate_port "$server_port" || exit 1

    echo -e "\nSelect the post-quantum algorithm:"
    list_algorithms
    read -rp "Enter algorithm number: " alg_choice
    validate_algorithm_choice "$alg_choice" "${#ALGORITHMS[@]}" || exit 1
    local algorithm="${ALGORITHMS[$((alg_choice-1))]}"
    log_info "Selected algorithm: ${algorithm}"

    echo -e "\nSelect the public key to copy:"
    list_keys
    read -rp "Select a key by number: " choice
    local keys=()
    while IFS= read -r -d '' f; do
        keys+=("$f")
    done < <(find "${SSH_DIR}" -maxdepth 1 -name "*.pub" -print0 2>/dev/null | sort -z)
    validate_algorithm_choice "$choice" "${#keys[@]}" || exit 1
    local public_key_file="${keys[$((choice-1))]}"
    log_info "Selected key: ${public_key_file}"
    
    copy_client_key "${server_host}" "${server_user}" "${public_key_file}" "${server_port}" "${algorithm}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi