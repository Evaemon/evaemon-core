#!/bin/bash
# Unit tests for client/copy_key_to_server.sh — copy_client_key()
#
# The real BIN_DIR/ssh binary is replaced with a lightweight mock that records
# the arguments it receives.  No server or OQS binary is required.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

source "${SCRIPT_DIR}/../test_runner.sh"

# Isolated scratch area
WORK_DIR="$(mktemp -d)"
WORK_SSH="${WORK_DIR}/.ssh"
MOCK_BIN="${WORK_DIR}/bin"
MOCK_ARGS_FILE="${WORK_DIR}/mock_ssh_args"
MOCK_STDIN_FILE="${WORK_DIR}/mock_ssh_stdin"
mkdir -p "${WORK_SSH}" "${MOCK_BIN}"
chmod 700 "${WORK_SSH}"
trap 'rm -rf "${WORK_DIR}"' EXIT

# ── Create mock SSH binary ────────────────────────────────────────────────────
# The mock writes one argument per line to MOCK_ARGS_FILE, saves stdin to
# MOCK_STDIN_FILE, prints the success message copy_client_key expects, and
# exits 0.

cat > "${MOCK_BIN}/ssh" << MOCK_SCRIPT
#!/bin/bash
printf '%s\n' "\$@" > "${MOCK_ARGS_FILE}"
cat > "${MOCK_STDIN_FILE}"
echo "Key added to authorized_keys."
exit 0
MOCK_SCRIPT
chmod +x "${MOCK_BIN}/ssh"

# Source copy_key_to_server.sh for its functions.
# The BASH_SOURCE guard prevents main() from running.
# Override BIN_DIR to our mock directory BEFORE sourcing so config.sh's value
# is immediately overridden afterward.
BIN_DIR="${MOCK_BIN}"
source "${PROJECT_ROOT}/client/copy_key_to_server.sh" 2>/dev/null
set +eo pipefail
# Re-assert our overrides (config.sh re-sources itself inside the script)
SSH_DIR="${WORK_SSH}"
BIN_DIR="${MOCK_BIN}"

# ── Fixture: fake public key ──────────────────────────────────────────────────
_PUB="${WORK_SSH}/id_ssh-falcon1024.pub"
printf 'ssh-falcon1024 FAKEBASE64 unit-test-key\n' > "${_PUB}"

_ALGO="ssh-falcon1024"
_HOST="192.168.10.20"
_USER="alice"
_PORT="2222"

# Invoke copy_client_key and capture mock args for inspection
copy_client_key "${_HOST}" "${_USER}" "${_PUB}" "${_PORT}" "${_ALGO}" 2>/dev/null
_ARGS="$(cat "${MOCK_ARGS_FILE}" 2>/dev/null || echo "")"
_STDIN="$(cat "${MOCK_STDIN_FILE}" 2>/dev/null || echo "")"

# ── Argument checks ───────────────────────────────────────────────────────────

describe "copy_client_key — SSH argument verification"

it "passes HostKeyAlgorithms=<algorithm> to ssh"
assert_contains "HostKeyAlgorithms=${_ALGO}" "$_ARGS"

it "passes PubkeyAcceptedKeyTypes=<algorithm> to ssh"
assert_contains "PubkeyAcceptedKeyTypes=${_ALGO}" "$_ARGS"

it "passes -p flag to ssh"
assert_contains "-p" "$_ARGS"

it "passes the correct port number to ssh"
assert_contains "${_PORT}" "$_ARGS"

it "passes user@host to ssh"
assert_contains "${_USER}@${_HOST}" "$_ARGS"

it "passes -i <private_key> to ssh"
assert_contains "-i" "$_ARGS"

# ── Stdin content check ───────────────────────────────────────────────────────

describe "copy_client_key — public key delivery"

it "streams the public key file content on ssh stdin"
assert_contains "ssh-falcon1024" "$_STDIN"

it "stdin content matches the public key file exactly"
expected="$(cat "${_PUB}")"
assert_eq "$expected" "$_STDIN"

# ── Failure path ──────────────────────────────────────────────────────────────

describe "copy_client_key — missing public key"

it "exits non-zero when the public key file does not exist"
rc=0
(copy_client_key "${_HOST}" "${_USER}" "${WORK_SSH}/nonexistent.pub" "${_PORT}" "${_ALGO}" \
    2>/dev/null) || rc=$?
assert_nonzero $rc

it "does not invoke ssh when the public key file is missing"
rm -f "${MOCK_ARGS_FILE}"
(copy_client_key "${_HOST}" "${_USER}" "${WORK_SSH}/gone.pub" "${_PORT}" "${_ALGO}" \
    2>/dev/null) || true
[[ ! -f "${MOCK_ARGS_FILE}" ]] && pass || fail "mock ssh was invoked despite missing key file"

# ── Done ─────────────────────────────────────────────────────────────────────
test_summary
