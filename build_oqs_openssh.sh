#!/bin/bash

###########
# Build and install OQS-OpenSSH (Open Quantum Safe OpenSSH)
###########

set -eo pipefail

# Source shared configuration (logging.sh is sourced transitively via functions.sh)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/shared/config.sh"
source "${SCRIPT_DIR}/shared/functions.sh"

# Point the centralized logger at the build log file
LOG_FILE="${BUILD_DIR}/oqs_build.log"

install_dependencies() {
    log_info "Installing dependencies..."
    if [ -f /etc/debian_version ]; then
        sudo apt-get update
        sudo apt-get install -y autoconf automake cmake gcc libtool libssl-dev make ninja-build zlib1g-dev git doxygen graphviz
    elif [ -f /etc/redhat-release ]; then
        sudo dnf install -y autoconf automake cmake gcc libtool openssl-devel make ninja-build zlib-devel git doxygen graphviz pkg-config
    else
        log_warn "Unsupported distribution. Please install dependencies manually."
        log_warn "Required: autoconf automake cmake gcc libtool libssl-dev make ninja-build zlib1g-dev git"
    fi

    # Ensure the sshd privilege-separation user and directory exist
    sudo mkdir -p -m 0755 /var/empty
    if ! getent group sshd >/dev/null; then sudo groupadd sshd; fi
    if ! getent passwd sshd >/dev/null; then sudo useradd -g sshd -c 'sshd privsep' -d /var/empty -s /bin/false sshd; fi
}

# Copy necessary shared libraries
handle_shared_libraries() {
    log_info "Setting up shared libraries..."

    mkdir -p "${INSTALL_PREFIX}/lib"

    if [ -d "${PREFIX}/lib" ]; then
        cp -R "${PREFIX}/lib/"* "${INSTALL_PREFIX}/lib/"
        log_info "Copied liboqs libraries to ${INSTALL_PREFIX}/lib/"
    else
        log_fatal "liboqs libraries not found in ${PREFIX}/lib"
    fi

    # Update ldconfig if on Linux
    if [ "$(uname)" == "Linux" ]; then
        echo "${INSTALL_PREFIX}/lib" | sudo tee /etc/ld.so.conf.d/oqs-ssh.conf
        sudo ldconfig
        log_info "Updated system library cache"
    fi
}

# Main installation process
main() {
    log_section "OQS-OpenSSH Installation"
    log_info "Starting OQS-OpenSSH installation..."

    mkdir -p "${BUILD_DIR}"
    cd "${PROJECT_ROOT}"

    install_dependencies

    # Step 1: Clone liboqs at the tip of the configured branch.
    log_info "Cloning liboqs..."
    rm -rf "${BUILD_DIR}/tmp" && mkdir -p "${BUILD_DIR}/tmp"
    git clone --branch "${LIBOQS_BRANCH}" --single-branch --depth 1 "${LIBOQS_REPO}" "${BUILD_DIR}/tmp/liboqs"

    # Detect the OpenSSL installation root so cmake and ./configure both find it,
    # even when OpenSSL was built from source and installed to /usr/local.
    if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists libssl 2>/dev/null; then
        OPENSSL_DETECTED_ROOT="$(pkg-config --variable=prefix libssl)"
    elif command -v openssl >/dev/null 2>&1; then
        # Derive root from the binary path  (/usr/local/bin/openssl → /usr/local)
        OPENSSL_DETECTED_ROOT="$(dirname "$(dirname "$(command -v openssl)")")"
    else
        OPENSSL_DETECTED_ROOT="${OPENSSL_SYS_DIR}"
    fi

    # Locate the actual libcrypto shared library file. cmake's FindOpenSSL module
    # does not search multiarch dirs (e.g. /usr/lib/x86_64-linux-gnu) when only
    # OPENSSL_ROOT_DIR=/usr is given, so we resolve the path explicitly.
    OPENSSL_CRYPTO_LIB=""
    # 1. Ask the runtime linker cache first — most reliable
    OPENSSL_CRYPTO_LIB="$(ldconfig -p 2>/dev/null | awk '/libcrypto\.so[^.0-9]/{print $NF; exit}')"
    # 2. Fall back to common prefixes/multiarch paths
    if [ -z "${OPENSSL_CRYPTO_LIB}" ]; then
        for _d in \
            "${OPENSSL_DETECTED_ROOT}/lib" \
            "${OPENSSL_DETECTED_ROOT}/lib64" \
            /usr/lib/x86_64-linux-gnu \
            /usr/lib/aarch64-linux-gnu \
            /usr/lib64 \
            /usr/local/lib \
            /usr/local/lib64; do
            if [ -f "${_d}/libcrypto.so" ]; then
                OPENSSL_CRYPTO_LIB="${_d}/libcrypto.so"
                break
            fi
        done
    fi

    log_info "Using OpenSSL root:    ${OPENSSL_DETECTED_ROOT}"
    log_info "Using libcrypto:       ${OPENSSL_CRYPTO_LIB:-<not found, relying on root>}"
    # Override the config-file default so the openssh ./configure step uses the same root
    OPENSSL_SYS_DIR="${OPENSSL_DETECTED_ROOT}"

    # Step 2: Build liboqs
    log_info "Building liboqs..."
    cd "${BUILD_DIR}/tmp/liboqs"
    rm -rf build
    mkdir build && cd build
    cmake .. -GNinja -DBUILD_SHARED_LIBS=ON -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
        -DOPENSSL_ROOT_DIR="${OPENSSL_DETECTED_ROOT}" \
        ${OPENSSL_CRYPTO_LIB:+-DOPENSSL_CRYPTO_LIBRARY="${OPENSSL_CRYPTO_LIB}"}
    ninja
    ninja install
    cd "${PROJECT_ROOT}"

    # Step 3: Clone OpenSSH at the tip of the configured branch.
    log_info "Cloning OpenSSH..."
    git clone --branch "${OPENSSH_BRANCH}" --single-branch --depth 1 "${OPENSSH_REPO}" "${BUILD_DIR}/openssh"

    # Patch configure.ac to accept OpenSSL 3.5+ (upstream check only tested up to 3.3/3.4).
    # Downgrade the hard error to a warning so the build continues on newer OpenSSL.
    sed -i \
        's/AC_MSG_ERROR(\[Unknown\/unsupported OpenSSL/AC_MSG_WARN([Unknown\/unsupported OpenSSL/' \
        "${BUILD_DIR}/openssh/configure.ac" || true

    # Step 4: Build OpenSSH
    log_info "Building OpenSSH..."
    cd "${BUILD_DIR}/openssh"

    autoreconf -i

    ./configure --prefix="${INSTALL_PREFIX}" \
               --with-ldflags="-Wl,-rpath -Wl,${INSTALL_PREFIX}/lib" \
               --with-libs=-lm \
               --with-ssl-dir="${OPENSSL_SYS_DIR}" \
               --with-liboqs-dir="${PREFIX}" \
               --with-cflags="-I${INSTALL_PREFIX}/include" \
               --sysconfdir="${INSTALL_PREFIX}/etc" \
               --with-privsep-path="${INSTALL_PREFIX}/var/empty" \
               --with-pid-dir="${INSTALL_PREFIX}/var/run" \
               --with-xauth="${INSTALL_PREFIX}/bin/xauth" \
               --with-default-path="/usr/local/bin:/usr/bin:/bin" \
               --with-privsep-user=sshd

    make -j"$(nproc)"

    handle_shared_libraries

    make install

    cd "${PROJECT_ROOT}"

    log_section "Installation Complete"
    log_info "OQS-OpenSSH installed to: ${INSTALL_PREFIX}"
    log_info "liboqs installed to:      ${PREFIX}"

    # Optional: Run basic tests
    log_info "Would you like to run the test suite?"
    read -rp "Run tests? (y/N): " run_tests
    if [[ "${run_tests}" == "y" || "${run_tests}" == "Y" ]]; then
        if [ -d "${BUILD_DIR}/openssh" ] && [ -f "${BUILD_DIR}/openssh/oqs-test/run_tests.sh" ]; then
            log_info "Starting test suite..."
            cd "${BUILD_DIR}/openssh" && ./oqs-test/run_tests.sh
        else
            log_error "Test script not found. Cannot run tests."
        fi
    else
        log_info "Skipping tests."
    fi
}

main
