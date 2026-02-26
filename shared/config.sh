#!/bin/bash

# Get the actual project root directory (parent of this script)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Build directories
BUILD_DIR="${PROJECT_ROOT}/build"
BIN_DIR="${BUILD_DIR}/bin"
SBIN_DIR="${BUILD_DIR}/sbin"
PREFIX="${BUILD_DIR}/oqs"
INSTALL_PREFIX="${BUILD_DIR}"

# Repository information
LIBOQS_REPO="https://github.com/open-quantum-safe/liboqs.git"
LIBOQS_BRANCH="main"
# Supply-chain pinning: always build from a known commit, not just a branch tip.
# Verify hashes against the upstream release page before updating.
# liboqs 0.14.0 (May 2025) — fixes CVE-2024-36405, CVE-2025-48946, CVE-2025-52473.
LIBOQS_COMMIT="e53b7f89caf7adf33d55ec9e2b9e9c8f19e1f4a7"

OPENSSH_REPO="https://github.com/open-quantum-safe/openssh.git"
OPENSSH_BRANCH="OQS-v9"
# Pin the OQS-OpenSSH commit used for reproducible builds.
OPENSSH_COMMIT="0f2e26f7ca2e5b46f04b8cf1e45c9e4a8b3c9d12"

# System directories
OPENSSL_SYS_DIR="/usr"
SSH_DIR="${HOME}/.ssh"

# Supported algorithms
ALGORITHMS=(
    "ssh-falcon1024"
    "ssh-mldsa66"
    "ssh-mldsa44"
    "ssh-dilithium5"
    "ssh-sphincsharaka192frobust"
    "ssh-sphincssha256128frobust"
    "ssh-sphincssha256192frobust"
    "ssh-falcon512"
    "ssh-dilithium2"
    "ssh-dilithium3"
)

# Classical key types for hybrid mode (passed to ssh-keygen -t)
CLASSICAL_KEYTYPES=("ed25519" "rsa")

# Classical SSH algorithm names for sshd_config directives (HostKeyAlgorithms etc.)
CLASSICAL_HOST_ALGOS="ssh-ed25519,rsa-sha2-512,rsa-sha2-256"

# Post-quantum and hybrid key exchange algorithms (for KexAlgorithms directive).
# Hybrid algorithms combine a classical base (ECDH/X25519) with Kyber for
# defense-in-depth: quantum-safe AND classically-secure at the same time.
KEX_ALGORITHMS=(
    "ecdh-nistp384-kyber-1024r3-sha384-d00@openquantumsafe.org"
    "ecdh-nistp256-kyber-512r3-sha256-d00@openquantumsafe.org"
    "x25519-kyber-512r3-sha256-d00@openquantumsafe.org"
    "kyber-1024r3-sha512-d00@openquantumsafe.org"
    "kyber-512r3-sha256-d00@openquantumsafe.org"
)

# Classical key exchange algorithms appended in hybrid server deployments so
# standard (non-OQS) SSH clients can still connect alongside PQ clients.
# Note: diffie-hellman-group14-sha256 (2048-bit DH) is intentionally excluded
# — it is deprecated per NIST SP 800-77r1; group16 (4096-bit) is the minimum.
CLASSICAL_KEX_ALGORITHMS="curve25519-sha256,ecdh-sha2-nistp384,diffie-hellman-group16-sha512"