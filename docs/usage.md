# Usage Manual

This manual covers every tool in Evaemon: what it does, when to use it, and how to invoke it both via the interactive wizard and directly from the command line.

---

## Table of Contents

1. [Wizard quick-reference](#wizard-quick-reference)
2. [Client tools](#client-tools)
3. [Server tools](#server-tools)
4. [Shared / configuration](#shared--configuration)
5. [Running the test suite](#running-the-test-suite)

---

## Wizard quick-reference

```bash
sudo bash wizard.sh
```

### Mode selection
| Input | Mode |
|-------|------|
| `1`   | Server |
| `2`   | Client |
| `3`   | Exit |

### Server menu
| Input | Action |
|-------|--------|
| `1`   | Build and install OQS-OpenSSH |
| `2`   | Configure server |
| `3`   | Monitor sshd |
| `4`   | Update / Rebuild |
| `5`   | Diagnostics |
| `6`   | Back |
| `7`   | Exit |

### Client menu
| Input | Action |
|-------|--------|
| `1`   | Build and install OQS-OpenSSH |
| `2`   | Generate key pair |
| `3`   | Copy public key to server |
| `4`   | Connect to server |
| `5`   | Backup / Restore keys |
| `6`   | Health check |
| `7`   | Rotate keys |
| `8`   | Debug tools |
| `9`   | Performance benchmark |
| `10`  | Back |
| `11`  | Exit |

---

## Client tools

### Key generation (`client/keygen.sh`)

Generates an SSH key pair and saves it to `~/.ssh/`. Supports both post-quantum and classical key types.

```bash
bash client/keygen.sh
```

When prompted, select a key type:

| Mode | Description |
|------|-------------|
| `1`  | Post-quantum key — choose from all supported PQ algorithms |
| `2`  | Classical key — Ed25519 (recommended) or RSA |

Private key: `~/.ssh/id_<algorithm>` (permissions 600)
Public key:  `~/.ssh/id_<algorithm>.pub` (permissions 644)

---

### Copy key to server (`client/copy_key_to_server.sh`)

Appends your public key to the server's `~/.ssh/authorized_keys` over an existing SSH connection.

```bash
bash client/copy_key_to_server.sh
```

---

### Connect (`client/connect.sh`)

Opens an interactive SSH session using the OQS ssh binary. Supports PQ-only and hybrid connection modes.

```bash
bash client/connect.sh
```

#### Connection modes

| Mode | Description |
|------|-------------|
| `1`  | **PQ only** — `KexAlgorithms` and `HostKeyAlgorithms` are restricted to PQ algorithms; connects only to PQ-configured servers |
| `2`  | **Hybrid** — `KexAlgorithms` and `HostKeyAlgorithms` include both PQ and classical algorithms; interoperates with hybrid servers |

#### Equivalent manual commands

PQ-only connection:
```bash
build/bin/ssh \
  -o "KexAlgorithms=ecdh-nistp384-kyber-1024r3-sha384-d00@openquantumsafe.org,..." \
  -o "HostKeyAlgorithms=ssh-falcon1024" \
  -o "PubkeyAcceptedKeyTypes=ssh-falcon1024" \
  -i ~/.ssh/id_ssh-falcon1024 \
  -p 22 user@server
```

Hybrid connection:
```bash
build/bin/ssh \
  -o "KexAlgorithms=ecdh-nistp384-kyber-1024r3-sha384-d00@openquantumsafe.org,...,curve25519-sha256,..." \
  -o "HostKeyAlgorithms=ssh-falcon1024,ssh-ed25519,rsa-sha2-512,rsa-sha2-256" \
  -o "PubkeyAcceptedKeyTypes=ssh-falcon1024,ssh-ed25519,rsa-sha2-512,rsa-sha2-256" \
  -i ~/.ssh/id_ssh-falcon1024 \
  -p 22 user@server
```

---

### Backup / Restore (`client/backup.sh`)

Creates an AES-256-CBC encrypted tarball of all `~/.ssh/id_ssh-*` key pairs and `known_hosts`. Also decrypts and restores from a previous backup.

```bash
# Interactive
bash client/backup.sh

# Backup to a specific path
bash client/backup.sh backup /path/to/output.tar.gz.enc

# Restore from a specific path
bash client/backup.sh restore /path/to/backup.tar.gz.enc
```

On restore, private key permissions are automatically reset to 600. Mismatched or incorrect passphrases are rejected before any files are written.

---

### Health check (`client/health_check.sh`)

Runs a five-stage connectivity and authentication check against a server. Each network stage retries with exponential backoff before reporting failure.

```bash
bash client/health_check.sh
```

| Stage | What is checked |
|-------|----------------|
| Binary check | `build/bin/ssh` and `ssh-keygen` present and executable |
| Key check | Private key exists; permissions are 600 |
| TCP reachability | Server port reachable (3 attempts, 2 → 4 → 8 s backoff) |
| SSH handshake | Full authentication with echo probe (3 attempts, 3 → 6 → 12 s backoff) |
| Host fingerprint | Fingerprint retrieved and printed for manual verification |

Exit code 0 = all PASS; non-zero = at least one FAIL.

---

### Key rotation (`client/key_rotation.sh`)

Rotates a post-quantum SSH key pair safely:

```bash
bash client/key_rotation.sh
```

Steps: generate new key → push to server → verify auth (4 attempts, 2 → 4 → 8 → 16 s backoff) → optionally remove old key → archive old key locally.

**Safety guarantee:** the old key is never removed from the server until the new key has been verified to authenticate successfully. The old key is renamed to `id_<algo>.retired_<timestamp>` with 400 permissions.

---

### Debug tool (`client/tools/debug.sh`)

Collects comprehensive diagnostics for troubleshooting failed connections.

```bash
bash client/tools/debug.sh
```

Output includes OQS binary versions, key inventory with fingerprints, server algorithm probe (`ssh-keyscan`), a full `-vvv` SSH session log saved to `build/debug_<timestamp>.log`, and remote `authorized_keys` inspection.

---

### Performance benchmark (`client/tools/performance_test.sh`)

Measures and compares key generation speed, key sizes, and optionally SSH handshake latency across algorithms. One warm-up run is performed before each measured series to eliminate JIT/cache effects.

```bash
bash client/tools/performance_test.sh
```

Sample output:
```
Algorithm                           Keygen(ms)   PrivKey(B)   PubKey(B)  Handshake(ms)
-----------------------------------  ----------  ------------ -----------  --------------
ssh-falcon1024                              184        4095         2113             312
ssh-mldsa66                                  97        4016         1952             N/A
```

Results are also saved to `build/perf_<timestamp>.csv`.

---

## Server tools

### Server setup (`server/server.sh`)

Configures the post-quantum sshd for first-time use:
- Generates host key pairs (one per selected algorithm)
- Writes `build/etc/sshd_config` including `HostKeyAlgorithms`, `PubkeyAcceptedKeyTypes`, and `KexAlgorithms`
- Creates and enables the `evaemon-sshd` systemd service

```bash
sudo bash server/server.sh
```

#### Algorithm modes

| Mode | Description |
|------|-------------|
| `1`  | All supported PQ algorithms — broadest PQ client compatibility |
| `2`  | Select specific PQ algorithms — restrict to a security level or performance profile |
| `3`  | Hybrid — all PQ algorithms + Ed25519 and RSA; classical clients can connect too |
| `4`  | Hybrid — select specific PQ algorithms + Ed25519 and RSA |

In hybrid modes (3 and 4), the generated `KexAlgorithms` directive includes both PQ/hybrid Kyber-based KEX (preferred) and classical KEX (fallback for standard clients).

Manage the service:
```bash
sudo systemctl {start|stop|restart|status} evaemon-sshd.service
```

---

### Monitor (`server/monitoring.sh`)

Shows real-time and recent activity of the post-quantum sshd.

```bash
sudo bash server/monitoring.sh
```

Modes: one-shot snapshot or continuous watch (default 10 s interval, Ctrl-C to stop).

Information shown: service status, active connections, recent auth events, PQ algorithm negotiation events, system load, sshd process uptime.

---

### Update / Rebuild (`server/update.sh`)

Performs a controlled in-place upgrade of the OQS-OpenSSH stack:

```bash
sudo bash server/update.sh
```

Steps: optional `git pull` → stop sshd → rebuild → `sshd -t` config check → restart → health check.

> Run during a maintenance window. The sshd is unavailable for the duration of the build (typically 5-20 minutes).

---

### Diagnostics (`server/tools/diagnostics.sh`)

Produces a comprehensive server health report covering binary versions, annotated `sshd_config`, syntax check, host key fingerprints, systemd service status, port conflict detection, and recent log entries.

```bash
sudo bash server/tools/diagnostics.sh
```

---

## Shared / configuration

### `shared/config.sh`

| Variable | Default | Description |
|----------|---------|-------------|
| `BUILD_DIR` | `<repo>/build` | Root of all build output |
| `BIN_DIR` | `<repo>/build/bin` | OQS SSH client binaries |
| `SBIN_DIR` | `<repo>/build/sbin` | OQS sshd binary |
| `SSH_DIR` | `~/.ssh` | User SSH directory |
| `ALGORITHMS` | (array, 10 entries) | Supported PQ authentication algorithms |
| `CLASSICAL_KEYTYPES` | `("ed25519" "rsa")` | Classical key types for hybrid mode |
| `CLASSICAL_HOST_ALGOS` | `"ssh-ed25519,rsa-sha2-512,rsa-sha2-256"` | Classical algorithm names for sshd_config |
| `KEX_ALGORITHMS` | (array, 5 entries) | PQ/hybrid Kyber KEX algorithms, preference order |
| `CLASSICAL_KEX_ALGORITHMS` | `"curve25519-sha256,..."` | Classical KEX fallback for hybrid deployments |

Override `BUILD_DIR` to install to a non-default path:
```bash
export BUILD_DIR=/opt/evaemon/build
sudo bash wizard.sh
```

### Log verbosity (`shared/logging.sh`)

```bash
export LOG_LEVEL=0   # DEBUG
export LOG_LEVEL=1   # INFO (default)
export LOG_LEVEL=2   # WARN
export LOG_LEVEL=3   # ERROR
export LOG_FILE=/var/log/evaemon.log   # optional file sink
```

Log entries include millisecond-precision timestamps. Successful operations emit a green `OK` line via `log_success`.

---

## Running the test suite

### Unit tests (no OQS binary required)

```bash
bash shared/tests/unit_tests/test_validation.sh   # 44 tests — input validation
bash shared/tests/unit_tests/test_logging.sh      # 26 tests — log levels, log_success
bash shared/tests/unit_tests/test_functions.sh    # 13 tests — retry_with_backoff
bash shared/tests/unit_tests/test_backup.sh       # 13 tests — backup/restore roundtrip
bash shared/tests/unit_tests/test_copy_key.sh     # 10 tests — copy_client_key (mock SSH)
bash shared/tests/unit_tests/test_connect.sh      # 15 tests — connect() KexAlgorithms args
```

### Integration tests (auto-skip OQS-dependent tests if binary absent)

```bash
bash shared/tests/integration_tests/test_keygen.sh      # 11 tests — key generation
bash shared/tests/integration_tests/test_server.sh      # 53 tests — sshd_config, hybrid, KexAlgorithms
bash shared/tests/integration_tests/test_key_rotation.sh # 14 tests — archive + retry verification
```

Exit code 0 = all tests passed; 1 = at least one failed. The full suite counts **199 tests, 0 failures**.
