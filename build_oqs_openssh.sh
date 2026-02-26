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

# Backward-compat alias so existing call sites keep working
log() { log_info "$*"; }

install_dependencies() {
    log "Installing dependencies..."
    if [ -f /etc/debian_version ]; then
        sudo apt-get update
        sudo apt-get install -y autoconf automake cmake gcc libtool libssl-dev make ninja-build zlib1g-dev git doxygen graphviz
        sudo mkdir -p -m 0755 /var/empty
        if ! getent group sshd >/dev/null; then sudo groupadd sshd; fi
        if ! getent passwd sshd >/dev/null; then sudo useradd -g sshd -c 'sshd privsep' -d /var/empty -s /bin/false sshd; fi
    else
        log_warn "Non-Debian system detected. Please install dependencies manually."
    fi
}

# Copy necessary shared libraries
handle_shared_libraries() {
    log "Setting up shared libraries..."

    mkdir -p "${INSTALL_PREFIX}/lib"

    if [ -d "${PREFIX}/lib" ]; then
        cp -R "${PREFIX}/lib/"* "${INSTALL_PREFIX}/lib/"
        log "Copied liboqs libraries to ${INSTALL_PREFIX}/lib/"
    else
        log_fatal "liboqs libraries not found in ${PREFIX}/lib"
    fi

    # Update ldconfig if on Linux
    if [ "$(uname)" == "Linux" ]; then
        echo "${INSTALL_PREFIX}/lib" | sudo tee /etc/ld.so.conf.d/oqs-ssh.conf
        sudo ldconfig
        log "Updated system library cache"
    fi
}

# Main installation process
main() {
    log_section "OQS-OpenSSH Installation"
    log "Starting OQS-OpenSSH installation..."

    mkdir -p "${BUILD_DIR}"
    cd "${PROJECT_ROOT}"

    install_dependencies

    # Step 1: Clone liboqs and pin to a verified commit (supply-chain protection).
    # Update LIBOQS_COMMIT in shared/config.sh after reviewing the release notes.
    log "Cloning liboqs..."
    rm -rf "${BUILD_DIR}/tmp" && mkdir -p "${BUILD_DIR}/tmp"
    git clone --branch "${LIBOQS_BRANCH}" --single-branch "${LIBOQS_REPO}" "${BUILD_DIR}/tmp/liboqs"
    git -C "${BUILD_DIR}/tmp/liboqs" checkout "${LIBOQS_COMMIT}"
    log "Pinned liboqs to commit ${LIBOQS_COMMIT}"

    # Step 2: Build liboqs
    log "Building liboqs..."
    cd "${BUILD_DIR}/tmp/liboqs"
    rm -rf build
    mkdir build && cd build
    cmake .. -GNinja -DBUILD_SHARED_LIBS=ON -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DCMAKE_INSTALL_PREFIX="${PREFIX}"
    ninja
    ninja install
    cd "${PROJECT_ROOT}"

    # Step 3: Clone OpenSSH and pin to a verified commit.
    log "Cloning OpenSSH..."
    git clone --branch "${OPENSSH_BRANCH}" --single-branch "${OPENSSH_REPO}" "${BUILD_DIR}/openssh"
    git -C "${BUILD_DIR}/openssh" checkout "${OPENSSH_COMMIT}"
    log "Pinned OQS-OpenSSH to commit ${OPENSSH_COMMIT}"

    # Step 4: Build OpenSSH
    log "Building OpenSSH..."
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
    log "OQS-OpenSSH installed to: ${INSTALL_PREFIX}"
    log "liboqs installed to:      ${PREFIX}"
}

# Run the main installation
main

# Optional: Run basic tests
log "Would you like to run the test suite?"
read -rp "Run tests? (y/N): " run_tests
if [[ "${run_tests}" == "y" || "${run_tests}" == "Y" ]]; then
    if [ -d "${BUILD_DIR}/openssh" ] && [ -f "${BUILD_DIR}/openssh/oqs-test/run_tests.sh" ]; then
        log "Starting test suite..."
        cd "${BUILD_DIR}/openssh" && ./oqs-test/run_tests.sh
    else
        log_error "Test script not found. Cannot run tests."
    fi
else
    log "Skipping tests."
fi