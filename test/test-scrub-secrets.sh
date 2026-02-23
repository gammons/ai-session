#!/usr/bin/env bash
set -euo pipefail

# Test suite for ai-session secret scrubbing
# Usage: ./test-scrub-secrets.sh [path/to/ai-session]

AI_SESSION="${1:-$(dirname "$0")/../ai-session}"
AI_SESSION="$(cd "$(dirname "$AI_SESSION")" && pwd)/$(basename "$AI_SESSION")"

PASS=0
FAIL=0
TEST_DIR=""

# ─── Helpers ──────────────────────────────────────────────────────────────────

setup() {
  TEST_DIR="$(mktemp -d)"
  cd "$TEST_DIR"
  git init -q
  git config user.name "test"
  git config user.email "test@test.com"
  git commit -q --allow-empty -m "init"
  "$AI_SESSION" init >/dev/null 2>&1
}

teardown() {
  if [[ -n "$TEST_DIR" && -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
  fi
}

# Run a single test. Args: test_name input expected_output
assert_scrubbed() {
  local name="$1" input="$2" expected="$3"
  local session_path
  rm -rf "$TEST_DIR"/.ai/sessions/*

  session_path=$(echo "$input" | "$AI_SESSION" new --goal "$name" --stdin 2>/dev/null) || {
    printf '  FAIL  %s (session creation failed)\n' "$name"
    FAIL=$((FAIL + 1))
    return
  }

  local actual
  actual="$(cat "$TEST_DIR/$session_path/transcript.md")"

  if [[ "$actual" == "$expected" ]]; then
    printf '  PASS  %s\n' "$name"
    PASS=$((PASS + 1))
  else
    printf '  FAIL  %s\n' "$name"
    printf '    expected: %s\n' "$expected"
    printf '    actual:   %s\n' "$actual"
    FAIL=$((FAIL + 1))
  fi
}

# Assert session creation fails (secrets detected after scrub)
assert_blocked() {
  local name="$1" input="$2"
  rm -rf "$TEST_DIR"/.ai/sessions/*

  if echo "$input" | "$AI_SESSION" new --goal "$name" --stdin >/dev/null 2>&1; then
    printf '  FAIL  %s (expected failure, got success)\n' "$name"
    FAIL=$((FAIL + 1))
  else
    printf '  PASS  %s\n' "$name"
    PASS=$((PASS + 1))
  fi
}

# Assert session creation succeeds and file contains no literal match
assert_not_present() {
  local name="$1" input="$2" forbidden="$3"
  rm -rf "$TEST_DIR"/.ai/sessions/*

  local session_path
  session_path=$(echo "$input" | "$AI_SESSION" new --goal "$name" --stdin 2>/dev/null) || {
    printf '  FAIL  %s (session creation failed)\n' "$name"
    FAIL=$((FAIL + 1))
    return
  }

  if grep -qF -- "$forbidden" "$TEST_DIR/$session_path/transcript.md"; then
    printf '  FAIL  %s (found forbidden string: %s)\n' "$name" "$forbidden"
    FAIL=$((FAIL + 1))
  else
    printf '  PASS  %s\n' "$name"
    PASS=$((PASS + 1))
  fi
}

# Assert text survives scrubbing unchanged
assert_preserved() {
  local name="$1" input="$2"
  rm -rf "$TEST_DIR"/.ai/sessions/*

  local session_path
  session_path=$(echo "$input" | "$AI_SESSION" new --goal "$name" --stdin 2>/dev/null) || {
    printf '  FAIL  %s (session creation failed)\n' "$name"
    FAIL=$((FAIL + 1))
    return
  }

  local actual
  actual="$(cat "$TEST_DIR/$session_path/transcript.md")"

  if [[ "$actual" == "$input" ]]; then
    printf '  PASS  %s\n' "$name"
    PASS=$((PASS + 1))
  else
    printf '  FAIL  %s (text was modified)\n' "$name"
    printf '    input:  %s\n' "$input"
    printf '    actual: %s\n' "$actual"
    FAIL=$((FAIL + 1))
  fi
}

# ─── Tests ────────────────────────────────────────────────────────────────────

trap teardown EXIT
setup

printf 'Running secret scrubbing tests...\n\n'

# --- AWS keys ---
printf 'AWS keys:\n'
assert_scrubbed "AWS access key" \
  "key: AKIAIOSFODNN7EXAMPLE" \
  "key: [REDACTED]"

assert_scrubbed "AWS access key mid-sentence" \
  "Found AKIAIOSFODNN7EXAMPLE in config" \
  "Found [REDACTED] in config"

# --- GitHub tokens ---
printf '\nGitHub tokens:\n'
assert_scrubbed "GitHub PAT (ghp_)" \
  "ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn" \
  "[REDACTED]"

assert_scrubbed "GitHub OAuth (gho_)" \
  "gho_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn" \
  "[REDACTED]"

assert_scrubbed "GitHub user token (ghu_)" \
  "ghu_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn" \
  "[REDACTED]"

assert_scrubbed "GitHub server token (ghs_)" \
  "ghs_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn" \
  "[REDACTED]"

assert_scrubbed "GitHub refresh token (ghr_)" \
  "ghr_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn" \
  "[REDACTED]"

# --- Slack tokens ---
printf '\nSlack tokens:\n'
assert_scrubbed "Slack bot token" \
  "xoxb-123456789012-1234567890123-ABCDefgh" \
  "[REDACTED]"

assert_scrubbed "Slack app token" \
  "xoxa-123456789-abcdef" \
  "[REDACTED]"

# --- JWTs ---
printf '\nJWTs:\n'
assert_scrubbed "JWT token" \
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIn0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c" \
  "[REDACTED]"

# --- Bearer tokens ---
printf '\nBearer tokens:\n'
assert_scrubbed "Bearer auth header" \
  "Authorization: Bearer sk-ant-api03-AAAAAAAAA" \
  "Authorization: Bearer [REDACTED]"

# --- Private keys ---
printf '\nPrivate keys:\n'
assert_scrubbed "RSA private key block" \
  "-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEA0Z3VS5JJcds3xfn
AAAABBBBCCCC1234567890abcdef
-----END RSA PRIVATE KEY-----" \
  "[REDACTED PRIVATE KEY]
[REDACTED]
[REDACTED]
[REDACTED END KEY]"

assert_scrubbed "EC private key block" \
  "-----BEGIN EC PRIVATE KEY-----
MHQCAQEEIBkg4LVWM9nuwNSk3yByxZpO
-----END EC PRIVATE KEY-----" \
  "[REDACTED PRIVATE KEY]
[REDACTED]
[REDACTED END KEY]"

assert_scrubbed "Generic private key" \
  "-----BEGIN PRIVATE KEY-----
MIIEvgIBADANBgkqhkiG9w0BAQEFAASC
-----END PRIVATE KEY-----" \
  "[REDACTED PRIVATE KEY]
[REDACTED]
[REDACTED END KEY]"

# --- Generic key=value patterns ---
printf '\nGeneric key=value:\n'
assert_scrubbed "api_key= unquoted" \
  "api_key=sk_live_abcdefghijklmnop" \
  "api_key=[REDACTED]"

assert_scrubbed "secret_key= double-quoted" \
  'secret_key = "wJalrXUtnFEMIbPxRfiCY"' \
  'secret_key = "[REDACTED]"'

assert_scrubbed "token := double-quoted (Go)" \
  'token := "my-super-secret-token-value-here"' \
  'token := "[REDACTED]"'

assert_scrubbed "password: double-quoted" \
  'password: "SuperSecretP@ssw0rd123!"' \
  'password: "[REDACTED]"'

assert_scrubbed "PASSWORD= upper case" \
  "PASSWORD=mysupersecretpass123" \
  "PASSWORD=[REDACTED]"

assert_scrubbed "access_token= unquoted" \
  "access_token=abcdef123456789xyz" \
  "access_token=[REDACTED]"

assert_scrubbed "client_secret= unquoted" \
  "client_secret=abcdef123456789xyz" \
  "client_secret=[REDACTED]"

assert_scrubbed "signing_key= unquoted" \
  "signing_key=abcdef123456789xyz" \
  "signing_key=[REDACTED]"

assert_scrubbed "credential= unquoted" \
  "credential=abcdef123456789xyz" \
  "credential=[REDACTED]"

assert_scrubbed "auth= unquoted" \
  "auth=my-long-auth-value-12345" \
  "auth=[REDACTED]"

assert_scrubbed "token single-quoted" \
  "token = 'my-super-secret-token-value-here'" \
  "token = '[REDACTED]'"

# --- Short values should NOT be scrubbed ---
printf '\nShort values (should be preserved):\n'
assert_preserved "Short key value (7 chars)" \
  "key=abcdefg"

assert_preserved "Short password" \
  'password: "short"'

# --- Innocent text should NOT be scrubbed ---
printf '\nFalse positive resistance:\n'
assert_preserved "Normal prose" \
  "This is a normal sentence about programming."

assert_preserved "Code variable named key" \
  "key = i"

assert_preserved "Short token assignment" \
  "token=abc"

assert_preserved "The word password in prose" \
  "Enter your password below"

# --- Custom patterns via .ai/scrub-patterns ---
printf '\nCustom patterns (.ai/scrub-patterns):\n'

echo 'CUSTOM-[0-9]{8}' >> "$TEST_DIR/.ai/scrub-patterns"
assert_scrubbed "Custom pattern match" \
  "Found CUSTOM-12345678 in logs" \
  "Found [REDACTED] in logs"

# Comments should be ignored
echo '# this is a comment' >> "$TEST_DIR/.ai/scrub-patterns"
assert_preserved "Comment in patterns file" \
  "# this is a comment"

# Multiple custom patterns
echo 'INTERNAL_[A-Z]{10,}' >> "$TEST_DIR/.ai/scrub-patterns"
assert_scrubbed "Second custom pattern" \
  "Got INTERNAL_SECRETTOKEN here" \
  "Got [REDACTED] here"

# --- Combined secrets in one file ---
printf '\nCombined secrets:\n'
assert_not_present "AWS key in multi-secret file" \
  "key: AKIAIOSFODNN7EXAMPLE and ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn" \
  "AKIAIOSFODNN7EXAMPLE"

assert_not_present "GitHub token in multi-secret file" \
  "key: AKIAIOSFODNN7EXAMPLE and ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn" \
  "ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ"

# --- _check_secrets safety net ---
printf '\n_check_secrets safety net:\n'

# We can't easily bypass _scrub_secrets to test _check_secrets catching leftovers,
# but we can verify the normal flow doesn't leave anything behind.
assert_not_present "No AWS key survives" \
  "config: AKIAIOSFODNN7EXAMPLE" \
  "AKIAIOSFODNN7EXAMPLE"

assert_not_present "No GitHub token survives" \
  "ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn" \
  "ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ"

assert_not_present "No JWT survives" \
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIn0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c" \
  "eyJhbGciOiJIUzI1NiI"

assert_not_present "No private key header survives" \
  "-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEA
-----END RSA PRIVATE KEY-----" \
  "-----BEGIN RSA PRIVATE KEY-----"

# --- Init creates scrub-patterns ---
printf '\ncmd_init:\n'
local_test_dir="$(mktemp -d)"
cd "$local_test_dir"
git init -q
git config user.name "test"
git config user.email "test@test.com"
git commit -q --allow-empty -m "init"
"$AI_SESSION" init >/dev/null 2>&1

if [[ -f "$local_test_dir/.ai/scrub-patterns" ]]; then
  printf '  PASS  scrub-patterns file created by init\n'
  PASS=$((PASS + 1))
else
  printf '  FAIL  scrub-patterns file NOT created by init\n'
  FAIL=$((FAIL + 1))
fi

if grep -q '^#' "$local_test_dir/.ai/scrub-patterns"; then
  printf '  PASS  scrub-patterns contains comments\n'
  PASS=$((PASS + 1))
else
  printf '  FAIL  scrub-patterns missing comments\n'
  FAIL=$((FAIL + 1))
fi

# Re-running init should not overwrite existing patterns
echo 'MY_CUSTOM_PATTERN' >> "$local_test_dir/.ai/scrub-patterns"
"$AI_SESSION" init >/dev/null 2>&1
if grep -q 'MY_CUSTOM_PATTERN' "$local_test_dir/.ai/scrub-patterns"; then
  printf '  PASS  init does not overwrite existing scrub-patterns\n'
  PASS=$((PASS + 1))
else
  printf '  FAIL  init overwrote existing scrub-patterns\n'
  FAIL=$((FAIL + 1))
fi

rm -rf "$local_test_dir"
cd "$TEST_DIR"

# ─── Summary ──────────────────────────────────────────────────────────────────

printf '\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
printf 'Results: %d passed, %d failed\n' "$PASS" "$FAIL"
printf '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'

exit "$FAIL"
