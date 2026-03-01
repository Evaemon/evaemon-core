#!/bin/bash

# Source config file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/logging.sh"
source "${SCRIPT_DIR}/validation.sh"

# retry_with_backoff MAX_ATTEMPTS INITIAL_DELAY_S COMMAND [ARGS...]
# Runs COMMAND up to MAX_ATTEMPTS times with exponential backoff between tries.
# Prints a warning on each failure and an error if all attempts are exhausted.
# Returns 0 on first success, 1 if every attempt fails.
retry_with_backoff() {
    local max_attempts="$1"
    local delay="$2"
    shift 2
    local attempt=1
    while (( attempt <= max_attempts )); do
        if "$@"; then
            return 0
        fi
        if (( attempt < max_attempts )); then
            log_warn "Attempt ${attempt}/${max_attempts} failed — retrying in ${delay}s..."
            sleep "$delay"
            delay=$(( delay * 2 ))
        fi
        (( attempt++ )) || true
    done
    log_error "All ${max_attempts} attempt(s) failed: $*"
    return 1
}

# _sshd_pid — return the PID of the running evaemon sshd, or empty if not running.
# Checks the PID file first, then falls back to pgrep.
_sshd_pid() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid="$(cat "$PID_FILE" 2>/dev/null || true)"
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            echo "$pid"
            return
        fi
    fi
    pgrep -f "${SBIN_DIR}/sshd" 2>/dev/null | head -1 || true
}

# _configured_port — read the sshd port from CONFIG_FILE, defaulting to 22.
_configured_port() {
    local port="22"
    if [[ -f "$CONFIG_FILE" ]]; then
        local cfg_port
        cfg_port="$(grep -i "^Port " "$CONFIG_FILE" 2>/dev/null | awk '{print $2}' | head -1)"
        [[ -n "$cfg_port" ]] && port="$cfg_port"
    fi
    echo "$port"
}

# Shared functions
list_algorithms() {
    echo "Available algorithms:"
    for i in "${!ALGORITHMS[@]}"; do
        echo "$((i+1)). ${ALGORITHMS[$i]}"
        case ${ALGORITHMS[$i]} in
            "ssh-falcon1024")
                echo "   ↳ Recommended: Fast lattice-based signing, NIST Level 5 security"
                ;;
            "ssh-mldsa66")
                echo "   ↳ Modified LDS scheme, higher security variant"
                ;;
            "ssh-mldsa44")
                echo "   ↳ Modified LDS scheme, balanced security/performance"
                ;;
            "ssh-dilithium5")
                echo "   ↳ NIST PQC winner, lattice-based with strong security guarantees"
                ;;
            "ssh-sphincsharaka192frobust")
                echo "   ↳ Hash-based signature scheme, quantum-resistant with minimal assumptions"
                ;;
            "ssh-sphincssha256128frobust")
                echo "   ↳ SPHINCS+ variant using SHA-256, faster but lower security level"
                ;;
            "ssh-sphincssha256192frobust")
                echo "   ↳ SPHINCS+ SHA-256 variant with NIST Level 3-4 security"
                ;;
            "ssh-falcon512")
                echo "   ↳ Faster Falcon variant, NIST Level 1 security, suitable for constrained devices"
                ;;
            "ssh-dilithium2")
                echo "   ↳ Lighter Dilithium variant, NIST Level 2 security"
                ;;
            "ssh-dilithium3")
                echo "   ↳ Medium Dilithium variant, NIST Level 3 security"
                ;;
        esac
    done
}