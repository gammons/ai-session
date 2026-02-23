#!/usr/bin/env bash
set -euo pipefail

# Test suite for ai-session helper functions
# Usage: ./test-helpers.sh [path/to/ai-session]

AI_SESSION="${1:-$(dirname "$0")/../ai-session}"
AI_SESSION="$(cd "$(dirname "$AI_SESSION")" && pwd)/$(basename "$AI_SESSION")"

PASS=0
FAIL=0
TEST_DIR=""

# ─── Test framework ───────────────────────────────────────────────────────────

setup() {
  TEST_DIR="$(mktemp -d)"
  cd "$TEST_DIR"
  git init -q
  git config user.name "test-user"
  git config user.email "test@test.com"
  git commit -q --allow-empty -m "init"
}

teardown() {
  if [[ -n "$TEST_DIR" && -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
  fi
}

source_helpers() {
  eval "$(sed -n '/^# ─── Helpers/,/^# ─── Subcommands/p' "$AI_SESSION" | head -n -1)"
}

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    printf '  PASS  %s\n' "$name"
    PASS=$((PASS + 1))
  else
    printf '  FAIL  %s\n' "$name"
    printf '    expected: %s\n' "$expected"
    printf '    actual:   %s\n' "$actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_match() {
  local name="$1" pattern="$2" actual="$3"
  if [[ "$actual" =~ $pattern ]]; then
    printf '  PASS  %s\n' "$name"
    PASS=$((PASS + 1))
  else
    printf '  FAIL  %s\n' "$name"
    printf '    pattern:  %s\n' "$pattern"
    printf '    actual:   %s\n' "$actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_neq() {
  local name="$1" unexpected="$2" actual="$3"
  if [[ "$unexpected" != "$actual" ]]; then
    printf '  PASS  %s\n' "$name"
    PASS=$((PASS + 1))
  else
    printf '  FAIL  %s\n' "$name"
    printf '    should not be: %s\n' "$unexpected"
    FAIL=$((FAIL + 1))
  fi
}

# ─── Tests ────────────────────────────────────────────────────────────────────

run_tests() {
  trap teardown EXIT
  setup
  source_helpers

  printf 'Running helper function tests...\n\n'

  # --- slugify ---
  printf 'slugify:\n'
  assert_eq "lowercase" "hello-world" "$(slugify "Hello World")"
  assert_eq "special chars to hyphens" "fix-the-bug-in-auth" "$(slugify "Fix the bug in auth!")"
  assert_eq "leading/trailing hyphens stripped" "hello" "$(slugify "---hello---")"
  assert_eq "colons and slashes" "feat-api-v2-endpoint" "$(slugify "feat: API v2/endpoint")"
  local long_slug
  long_slug=$(slugify "this is a very long goal description that should be truncated to forty characters maximum")
  assert_eq "truncate to 40 chars" 40 "${#long_slug}"
  assert_eq "numbers preserved" "fix-issue-42" "$(slugify "Fix issue 42")"
  assert_eq "consecutive special chars collapsed" "a-b" "$(slugify "a!!!b")"
  assert_eq "already kebab" "already-kebab-case" "$(slugify "already-kebab-case")"
  assert_eq "single word" "refactor" "$(slugify "Refactor")"

  # --- short_id ---
  printf '\nshort_id:\n'
  assert_eq "truncates to 8 chars" "abcdef12" "$(short_id "abcdef1234567890")"
  assert_eq "short input unchanged" "abc" "$(short_id "abc")"
  assert_eq "exactly 8 chars" "12345678" "$(short_id "12345678")"
  assert_eq "UUID format" "550e8400" "$(short_id "550e8400-e29b-41d4-a716-446655440000")"

  # --- now_iso ---
  printf '\nnow_iso:\n'
  local iso
  iso=$(now_iso)
  assert_match "ISO 8601 format" '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$iso"

  # --- now_folder_prefix ---
  printf '\nnow_folder_prefix:\n'
  local prefix
  prefix=$(now_folder_prefix)
  assert_match "folder prefix format" '^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{4}Z$' "$prefix"

  # --- gen_uuid ---
  printf '\ngen_uuid:\n'
  local uuid1 uuid2
  uuid1=$(gen_uuid)
  uuid2=$(gen_uuid)
  assert_match "UUID format (8-4-4-4-12)" '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' "$uuid1"
  assert_neq "UUIDs are unique" "$uuid1" "$uuid2"

  # --- file_age_hours ---
  printf '\nfile_age_hours:\n'
  assert_eq "missing file returns 9999" "9999" "$(file_age_hours "/nonexistent/file")"

  local tmpfile="$TEST_DIR/agefile"
  touch "$tmpfile"
  assert_eq "fresh file is 0 hours" "0" "$(file_age_hours "$tmpfile")"
  rm -f "$tmpfile"

  # --- repo_name ---
  printf '\nrepo_name:\n'
  local rname
  rname=$(repo_name)
  assert_eq "returns basename of repo" "$(basename "$TEST_DIR")" "$rname"

  # --- current_branch ---
  printf '\ncurrent_branch:\n'
  assert_eq "main branch" "main" "$(current_branch)"

  git checkout -q -b feature/test-branch
  assert_eq "feature branch" "feature/test-branch" "$(current_branch)"
  git checkout -q main

  # --- git_author ---
  printf '\ngit_author:\n'
  assert_eq "returns configured name" "test-user" "$(git_author)"

  # --- claude_project_key ---
  printf '\nclaude_project_key:\n'
  local key
  key=$(claude_project_key)
  assert_match "contains only alnum and hyphens" '^[a-zA-Z0-9-]+$' "$key"
  assert_match "contains tmp dir base" "$(basename "$TEST_DIR")" "$key"

  # --- file_sha256 ---
  printf '\nfile_sha256:\n'
  echo -n "hello" > "$TEST_DIR/hashfile"
  local hash
  hash=$(file_sha256 "$TEST_DIR/hashfile")
  assert_eq "sha256 of 'hello'" "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824" "$hash"
  assert_match "64 hex chars" '^[0-9a-f]{64}$' "$hash"

  echo -n "world" > "$TEST_DIR/hashfile2"
  local hash2
  hash2=$(file_sha256 "$TEST_DIR/hashfile2")
  assert_neq "different content different hash" "$hash" "$hash2"

  # --- jsonl_to_markdown ---
  printf '\njsonl_to_markdown:\n'

  echo '{"type":"human","message":"Hello there"}' > "$TEST_DIR/test.jsonl"
  local md
  md=$(jsonl_to_markdown "$TEST_DIR/test.jsonl")
  assert_match "human string message" "## User" "$md"
  assert_match "human message content" "Hello there" "$md"

  echo '{"type":"assistant","message":{"content":[{"type":"text","text":"Hi back"}]}}' > "$TEST_DIR/test2.jsonl"
  md=$(jsonl_to_markdown "$TEST_DIR/test2.jsonl")
  assert_match "assistant content array" "## Assistant" "$md"
  assert_match "assistant message text" "Hi back" "$md"

  cat > "$TEST_DIR/test3.jsonl" << 'EOF'
{"type":"human","message":"What is 2+2?"}
{"type":"assistant","message":{"content":[{"type":"text","text":"4"}]}}
{"type":"human","message":"Thanks"}
{"type":"assistant","message":"You're welcome"}
EOF
  md=$(jsonl_to_markdown "$TEST_DIR/test3.jsonl")
  assert_match "multi-turn has multiple User headers" ".*## User.*## Assistant.*## User.*## Assistant" "$md"
  assert_match "first question present" "What is 2\+2" "$md"
  assert_match "answer present" "4" "$md"

  echo '{"type":"system","message":"ignored"}' > "$TEST_DIR/test4.jsonl"
  md=$(jsonl_to_markdown "$TEST_DIR/test4.jsonl")
  assert_eq "system messages ignored" "" "$md"

  echo '{"type":"human","message":{"content":[{"type":"text","text":"array format"}]}}' > "$TEST_DIR/test5.jsonl"
  md=$(jsonl_to_markdown "$TEST_DIR/test5.jsonl")
  assert_match "human content array format" "array format" "$md"

  # ─── Summary ────────────────────────────────────────────────────────────────

  printf '\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
  printf 'Results: %d passed, %d failed\n' "$PASS" "$FAIL"
  printf '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'

  return "$FAIL"
}

run_tests
exit $?
