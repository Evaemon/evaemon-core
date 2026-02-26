# Security Guide

This document describes the threat model Evaemon is designed to address, the security properties of the supported algorithms, operational best practices, and known limitations.

---

## Table of Contents

1. [Threat model](#threat-model)
2. [Algorithm selection](#algorithm-selection)
3. [Key management](#key-management)
4. [Server hardening](#server-hardening)
5. [Client hardening](#client-hardening)
6. [Backup security](#backup-security)
7. [Key rotation policy](#key-rotation-policy)
8. [Known limitations and caveats](#known-limitations-and-caveats)
9. [Incident response](#incident-response)

---

## Threat model

### What this toolkit protects against

**Harvest-now / decrypt-later attacks**
A powerful adversary can record encrypted SSH traffic today and decrypt it once they have access to a cryptographically-relevant quantum computer. Evaemon addresses this at both layers:
- **Session encryption (KEX):** the generated `sshd_config` and client connection scripts set `KexAlgorithms` to prefer Kyber-based hybrid key exchange, meaning the session key itself cannot be recovered by a future quantum computer.
- **Authentication:** PQ signature algorithms ensure that recorded authentication exchanges cannot be forged later by a quantum attacker.

**Authentication forgery by a quantum-capable adversary**
Classical RSA and ECDSA authentication can be broken by a sufficiently powerful quantum computer running Shor's algorithm. The signature schemes in this toolkit are based on lattice or hash problems believed to be hard even for quantum computers.

### What this toolkit does NOT protect against

- **Compromised server** -- if an attacker has root on the server, no SSH configuration helps.
- **Compromised endpoint** -- malware on the client can steal keys regardless of algorithm.
- **Side-channel attacks** -- this toolkit does not address timing or power side-channels in the OQS library implementations.
- **Denial of service** -- monitoring tools detect issues; they do not prevent attacks on the SSH port.
- **Protocol downgrade to classical SSH** -- this toolkit runs a *separate* sshd; the system's standard OpenSSH remains unchanged and clients can still connect to it unless you firewall it.

---

## Algorithm selection

### Supported algorithms and security levels

| Algorithm | Type | NIST Level | Notes |
|-----------|------|-----------|-------|
| `ssh-falcon1024` | Lattice (NTRU) | 5 | **Recommended** -- fastest verification, small signatures at L5 |
| `ssh-mldsa66` | Lattice (Module-LWE) | 3 | NIST PQC standard (FIPS 204) |
| `ssh-mldsa44` | Lattice (Module-LWE) | 2 | Lighter ML-DSA variant |
| `ssh-dilithium5` | Lattice (Module-LWE) | 5 | Conservative L5 lattice choice |
| `ssh-dilithium3` | Lattice (Module-LWE) | 3 | Balanced |
| `ssh-dilithium2` | Lattice (Module-LWE) | 2 | Lightweight |
| `ssh-falcon512` | Lattice (NTRU) | 1 | Fast, small; L1 only -- use sparingly |
| `ssh-sphincsharaka192frobust` | Hash (SPHINCS+) | 3-4 | Different hardness assumption; large signatures |
| `ssh-sphincssha256128frobust` | Hash (SPHINCS+) | 1 | Fast verification; large signatures |
| `ssh-sphincssha256192frobust` | Hash (SPHINCS+) | 3 | Conservative hash-based |

### Guidance

- **For most deployments:** `ssh-falcon1024` (Level 5, fast, compact)
- **If you want a NIST standard:** `ssh-mldsa66` (standardised as FIPS 204)
- **If you distrust lattice math:** `ssh-sphincssha256192frobust` (hash-based, orthogonal assumption)
- **For constrained bandwidth:** `ssh-falcon512` (Level 1 -- only use if Level 5 is genuinely impractical)

Avoid mixing security levels across client and server. A Level-1 client key is the weakest link even when the server is configured for Level 5.

---

## Key management

### Private key permissions

Private keys **must** have permissions `600`. The toolkit enforces this on generation and warns on weaker permissions.

```bash
chmod 600 ~/.ssh/id_ssh-falcon1024
```

### Passphrase protection

Protect private keys with a passphrase. During key generation you are prompted:

```
Protect the new key with a passphrase? (y/N):
```

Use `ssh-agent` to avoid repeated passphrase entry:

```bash
eval "$(build/bin/ssh-agent -s)"
build/bin/ssh-add ~/.ssh/id_ssh-falcon1024
```

### Key uniqueness

Generate distinct key pairs for distinct purposes (personal workstations, CI/CD, jump hosts). Do not share private keys between users or machines.

### Known hosts verification

On first connection to a server, verify the host key fingerprint out-of-band (e.g., from the server console) before accepting it. The health check and debug tools print the current server fingerprint to aid verification.

---

## Server hardening

### Additional `sshd_config` directives

The generated `sshd_config` applies conservative defaults. Recommended additions:

```
# Disable password authentication entirely
PasswordAuthentication no
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no

# Restrict to specific users
AllowUsers alice bob

# Idle session timeout
ClientAliveInterval 300
ClientAliveCountMax 2

# Bind to a specific interface (if multi-homed)
ListenAddress 192.168.1.10
```

Edit `build/etc/sshd_config`, then validate:

```bash
bash server/tools/diagnostics.sh
```

### Firewall

Restrict SSH access to known source IP ranges:

```bash
sudo ufw allow from 192.168.0.0/24 to any port 22
sudo ufw deny 22
```

### Non-standard port

Running the post-quantum sshd on a non-standard port reduces automated scanner noise. Edit the `Port` directive in `build/etc/sshd_config`, update the firewall, and inform clients.

### Host key rotation

Rotate the server's host key periodically or after a suspected compromise. After regeneration, distribute the new fingerprint to all clients out-of-band and ask them to remove the old known_hosts entry:

```bash
build/bin/ssh-keygen -R <server_host>
```

---

## Client hardening

### SSH config alias

Create or extend `~/.ssh/config`:

```
Host pqserver
    HostName               192.168.1.10
    User                   alice
    Port                   22
    IdentityFile           ~/.ssh/id_ssh-falcon1024
    HostKeyAlgorithms      ssh-falcon1024
    PubkeyAcceptedKeyTypes ssh-falcon1024
    KexAlgorithms          ecdh-nistp384-kyber-1024r3-sha384-d00@openquantumsafe.org,ecdh-nistp256-kyber-512r3-sha256-d00@openquantumsafe.org,x25519-kyber-512r3-sha256-d00@openquantumsafe.org
```

For a hybrid server that also accepts classical clients, append the classical fallback KEX:

```
Host pqserver-hybrid
    HostName               192.168.1.10
    User                   alice
    Port                   22
    IdentityFile           ~/.ssh/id_ssh-falcon1024
    HostKeyAlgorithms      ssh-falcon1024,ssh-ed25519,rsa-sha2-512,rsa-sha2-256
    PubkeyAcceptedKeyTypes ssh-falcon1024,ssh-ed25519,rsa-sha2-512,rsa-sha2-256
    KexAlgorithms          ecdh-nistp384-kyber-1024r3-sha384-d00@openquantumsafe.org,ecdh-nistp256-kyber-512r3-sha256-d00@openquantumsafe.org,x25519-kyber-512r3-sha256-d00@openquantumsafe.org,curve25519-sha256,diffie-hellman-group16-sha512
```

Then connect with:
```bash
build/bin/ssh pqserver
```

### Authorized keys audit

Periodically review `~/.ssh/authorized_keys` on every server you have access to and remove stale entries. Use `client/key_rotation.sh` to retire old keys cleanly.

### known_hosts hygiene

Remove stale host entries when a server is decommissioned:

```bash
build/bin/ssh-keygen -R old-server.example.com
```

---

## Backup security

Backup files produced by `client/backup.sh` are encrypted with AES-256-CBC (PBKDF2, 600,000 iterations). They are as sensitive as the private keys they contain.

- Store backups in an **offline** location (encrypted USB, offline cold storage).
- Never store a backup and its passphrase together.
- Test restoration periodically.
- After key rotation, create a new backup and securely destroy the old one.

---

## Key rotation policy

| Scenario | Rotate every |
|----------|-------------|
| Personal / low-risk | 1-2 years |
| Enterprise / privileged access | 6-12 months |
| CI/CD automation keys | 90 days |
| Post suspected compromise | Immediately |

Use `client/key_rotation.sh`. The tool verifies the new key authenticates before removing the old one.

---

## CVE advisories and dependency vulnerabilities

The following CVEs affect components that Evaemon builds from source.
Ensure you pull up-to-date source (or pin to the versions noted) before building.

### liboqs

| CVE | Severity | Affected versions | Fixed in | Description |
|-----|----------|-------------------|----------|-------------|
| CVE-2024-36405 | Moderate | < 0.10.1 | 0.10.1 | KyberSlash: control-flow timing leak in Kyber/ML-KEM decapsulation when compiled with Clang 15–18 at -O1/-Os. Enables secret-key recovery. |
| CVE-2024-54137 | Moderate | < 0.12.0 | 0.12.0 | HQC decapsulation returns incorrect shared secret on invalid ciphertext. |
| CVE-2025-48946 | Moderate | < 0.14.0 | 0.14.0 | HQC design flaw: large number of malformed ciphertexts share the same implicit rejection value. |
| CVE-2025-52473 | Moderate | < 0.14.0 | 0.14.0 | HQC secret-dependent branches when compiled with Clang above -O0. |

> **Note:** HQC is not used by any of the signature algorithms in this toolkit's
> default `ALGORITHMS` list, but it is present in the liboqs build. CVE-2024-36405
> (KyberSlash) **does** apply to the Kyber-based `KEX_ALGORITHMS` used for session
> key exchange.

**Recommendation:** build against liboqs `main` (≥ 0.14.0) or the latest tagged release.

### OQS-OpenSSH (upstream OpenSSH inherited CVEs)

OQS-OpenSSH is a fork of upstream OpenSSH. The following upstream CVEs may be
present depending on the base version included in the OQS fork branch:

| CVE | CVSS | Description |
|-----|------|-------------|
| CVE-2024-6387 | 8.1 Critical | "regreSSHion" — unauthenticated RCE as root via signal-handler race in sshd on glibc Linux (OpenSSH 8.5p1–9.7p1). |
| CVE-2024-6409 | 7.0 High | Race condition RCE in privilege-separation child (OpenSSH 8.7–8.8, RHEL/Fedora). |
| CVE-2025-26465 | 6.8 Medium | Client MitM if `VerifyHostKeyDNS=yes` (OpenSSH 6.8p1–9.9p1). |
| CVE-2025-26466 | 5.9 Medium | Pre-authentication CPU/memory DoS (OpenSSH 9.5p1–9.9p1). Fixed in 9.9p2. |

> **Note:** The OQS-OpenSSH repository (`OQS-v9` branch) is archived and no longer
> actively maintained by the Open Quantum Safe project. It may not have received
> patches for all upstream CVEs. **This toolkit is intended for research and
> evaluation, not production use with sensitive data.**

---

## Known limitations and caveats

1. **OQS implementations are not yet FIPS-validated.** The underlying liboqs library is research-grade. Await formal FIPS 204 certification for regulated environments.

2. **PQ KEX is hybrid, not pure-PQ by default.** The recommended KEX algorithms (e.g. `ecdh-nistp384-kyber-1024r3`) combine a classical elliptic-curve exchange with Kyber. Security holds as long as either component remains unbroken. Pure-PQ KEX options (`kyber-1024r3-sha512-d00@openquantumsafe.org`) are available in `shared/config.sh` but sacrifice compatibility with clients that lack Kyber support.

3. **System SSH is unmodified.** Both standard and post-quantum sshd run simultaneously by default. Ensure classical SSH is also hardened or firewalled.

4. **Host key compromise is not automatically detected.** Rotate host keys immediately upon suspicion of compromise.

5. **Algorithm agility.** If a PQ algorithm is later found vulnerable, rotating to a different one requires reconfiguring both server and all clients. Maintain a record of which key type each client uses.

---

## Incident response

### Suspected private key compromise

1. Run key rotation immediately:
   ```bash
   bash client/key_rotation.sh
   ```
2. Confirm the old key is removed from all servers' `authorized_keys`.
3. Review server logs for unusual activity:
   ```bash
   bash server/monitoring.sh
   ```
4. Rotate the server's host key if the server itself may be compromised.

### Suspected server compromise

1. Stop the post-quantum sshd:
   ```bash
   sudo systemctl stop evaemon-sshd.service
   ```
2. Use out-of-band console access for investigation -- do not SSH in.
3. After remediation, rebuild from scratch, regenerate all host keys, and rotate all client keys that had access.
