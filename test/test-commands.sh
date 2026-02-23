#!/usr/bin/env bash
set -euo pipefail

# Test suite for ai-session commands (init, new, attach, list, show)
# Usage: ./test-commands.sh [path/to/ai-session]

AI_SESSION="${1:-$(dirname "$0")/../ai-session}"
AI_SESSION="$(cd "$(dirname "$AI_SESSION")" && pwd)/$(basename "$AI_SESSION")"

PASS=0
FAIL=0
TEST_DIR=""

# ─── Test framework ───────────────────────────────────────────────────────────

new_repo() {
  TEST_DIR="$(mktemp -d)"
  TEST_CACHE="$(mktemp -d)"
  cd "$TEST_DIR"
  git init -q
  git config user.name "test-user"
  git config user.email "test@test.com"
  git commit -q --allow-empty -m "init"
}

# Resolve a session trailer path to an absolute path (uses cache dir or in-tree)
resolve_session() {
  local trailer_path="$1"
  if [[ "$trailer_path" == .ai/* ]]; then
    echo "$TEST_DIR/$trailer_path"
  else
    echo "$TEST_CACHE/$trailer_path"
  fi
}

teardown() {
  if [[ -n "$TEST_DIR" && -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
  fi
  if [[ -n "${TEST_CACHE:-}" && -d "$TEST_CACHE" ]]; then
    rm -rf "$TEST_CACHE"
  fi
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

assert_file_exists() {
  local name="$1" path="$2"
  if [[ -f "$path" ]]; then
    printf '  PASS  %s\n' "$name"
    PASS=$((PASS + 1))
  else
    printf '  FAIL  %s (file not found: %s)\n' "$name" "$path"
    FAIL=$((FAIL + 1))
  fi
}

assert_dir_exists() {
  local name="$1" path="$2"
  if [[ -d "$path" ]]; then
    printf '  PASS  %s\n' "$name"
    PASS=$((PASS + 1))
  else
    printf '  FAIL  %s (dir not found: %s)\n' "$name" "$path"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_contains() {
  local name="$1" path="$2" pattern="$3"
  if grep -qE "$pattern" "$path" 2>/dev/null; then
    printf '  PASS  %s\n' "$name"
    PASS=$((PASS + 1))
  else
    printf '  FAIL  %s (pattern not found: %s)\n' "$name" "$pattern"
    FAIL=$((FAIL + 1))
  fi
}

assert_fails() {
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then
    printf '  FAIL  %s (expected failure, got success)\n' "$name"
    FAIL=$((FAIL + 1))
  else
    printf '  PASS  %s\n' "$name"
    PASS=$((PASS + 1))
  fi
}

assert_succeeds() {
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then
    printf '  PASS  %s\n' "$name"
    PASS=$((PASS + 1))
  else
    printf '  FAIL  %s (command failed)\n' "$name"
    FAIL=$((FAIL + 1))
  fi
}

jq_eq() {
  local name="$1" file="$2" query="$3" expected="$4"
  local actual
  actual=$(jq -r "$query" "$file" 2>/dev/null)
  assert_eq "$name" "$expected" "$actual"
}

# ─── Tests ────────────────────────────────────────────────────────────────────

run_tests() {
  trap teardown EXIT

  printf 'Running command tests...\n\n'

  # ─── cmd_init ─────────────────────────────────────────────────────────────

  printf 'cmd_init:\n'
  new_repo

  "$AI_SESSION" init --cache "$TEST_CACHE" >/dev/null 2>&1

  assert_dir_exists "creates .ai directory" "$TEST_DIR/.ai"
  assert_file_exists "creates .ai/config.json" "$TEST_DIR/.ai/config.json"
  assert_file_exists ".ai/.gitignore exists" "$TEST_DIR/.ai/.gitignore"
  assert_file_contains ".gitignore has active-session" "$TEST_DIR/.ai/.gitignore" "^\.active-session$"
  assert_file_exists "scrub-patterns exists" "$TEST_DIR/.ai/scrub-patterns"
  assert_file_exists "prepare-commit-msg hook" "$TEST_DIR/.git/hooks/prepare-commit-msg"
  assert_file_exists "post-commit hook" "$TEST_DIR/.git/hooks/post-commit"
  assert_file_exists "pre-push hook" "$TEST_DIR/.git/hooks/pre-push"
  assert_file_contains "prepare-commit-msg has marker" \
    "$TEST_DIR/.git/hooks/prepare-commit-msg" "_hook_prepare_commit_msg"
  assert_file_contains "post-commit has marker" \
    "$TEST_DIR/.git/hooks/post-commit" "_hook_post_commit"
  assert_file_contains "pre-push has marker" \
    "$TEST_DIR/.git/hooks/pre-push" "_hook_pre_push"
  assert_file_exists "claude settings.local.json exists" "$TEST_DIR/.claude/settings.local.json"
  assert_file_contains "settings.local.json has ai-session hook" \
    "$TEST_DIR/.claude/settings.local.json" "ai-session _mark-active"

  # .gitignore has sessions/
  assert_file_contains ".gitignore has sessions/" "$TEST_DIR/.ai/.gitignore" "^sessions/"

  # Idempotent
  "$AI_SESSION" init --cache "$TEST_CACHE" >/dev/null 2>&1
  local hook_count
  hook_count=$(grep -c "_hook_prepare_commit_msg" "$TEST_DIR/.git/hooks/prepare-commit-msg")
  assert_eq "init is idempotent (no duplicate hooks)" "1" "$hook_count"

  # Appends to existing hook file
  teardown
  new_repo
  mkdir -p "$TEST_DIR/.git/hooks"
  printf '#!/usr/bin/env bash\necho "existing hook"\n' > "$TEST_DIR/.git/hooks/prepare-commit-msg"
  chmod +x "$TEST_DIR/.git/hooks/prepare-commit-msg"
  "$AI_SESSION" init --cache "$TEST_CACHE" >/dev/null 2>&1
  assert_file_contains "preserves existing hook content" \
    "$TEST_DIR/.git/hooks/prepare-commit-msg" "existing hook"
  assert_file_contains "appends ai-session to existing hook" \
    "$TEST_DIR/.git/hooks/prepare-commit-msg" "_hook_prepare_commit_msg"

  # Writes hook to settings.local.json, leaves settings.json untouched
  teardown
  new_repo
  mkdir -p "$TEST_DIR/.claude"
  echo '{"permissions":{"allow":["Read"]}}' > "$TEST_DIR/.claude/settings.json"
  "$AI_SESSION" init --cache "$TEST_CACHE" >/dev/null 2>&1
  assert_file_contains "preserves existing settings.json" \
    "$TEST_DIR/.claude/settings.json" '"allow"'
  assert_file_contains "hook goes to settings.local.json" \
    "$TEST_DIR/.claude/settings.local.json" "ai-session _mark-active"

  # ─── cmd_new ──────────────────────────────────────────────────────────────

  printf '\ncmd_new:\n'
  teardown
  new_repo
  "$AI_SESSION" init --cache "$TEST_CACHE" >/dev/null 2>&1

  # Basic --stdin
  local session_path session_abs
  session_path=$(echo "test content" | "$AI_SESSION" new --goal "Test basic new" --stdin 2>/dev/null)
  session_abs=$(resolve_session "$session_path")
  assert_dir_exists "session directory created" "$session_abs"
  assert_file_exists "meta.json created" "$session_abs/meta.json"
  assert_file_exists "transcript.md created" "$session_abs/transcript.md"
  assert_eq "transcript content" "test content" "$(cat "$session_abs/transcript.md")"

  # meta.json fields
  jq_eq "meta: goal" "$session_abs/meta.json" ".goal" "Test basic new"
  jq_eq "meta: author" "$session_abs/meta.json" ".author" "test-user"
  jq_eq "meta: repo" "$session_abs/meta.json" ".repo" "$(basename "$TEST_DIR")"
  jq_eq "meta: branch" "$session_abs/meta.json" ".branch" "main"
  jq_eq "meta: model (default)" "$session_abs/meta.json" ".model" "unknown"
  jq_eq "meta: commits empty" "$session_abs/meta.json" ".commits | length" "0"
  jq_eq "meta: pr null" "$session_abs/meta.json" ".pr" "null"
  jq_eq "meta: links empty" "$session_abs/meta.json" ".links | length" "0"

  # session_id and short_id consistency
  local full_id short
  full_id=$(jq -r '.session_id' "$session_abs/meta.json")
  short=$(jq -r '.short_id' "$session_abs/meta.json")
  assert_eq "short_id matches session_id prefix" "$short" "${full_id:0:8}"

  # transcript_hash is set
  local thash
  thash=$(jq -r '.transcript_hash' "$session_abs/meta.json")
  assert_match "transcript_hash starts with sha256:" "^sha256:[0-9a-f]{64}$" "$thash"

  # created_at is ISO format
  local created
  created=$(jq -r '.created_at' "$session_abs/meta.json")
  assert_match "created_at is ISO 8601" '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$created"

  # Folder naming convention — now <project>/sessions/<folder>
  assert_match "folder name format" '/sessions/[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{4}Z_[a-z0-9-]+__[a-f0-9]{8}$' "$session_path"

  # --model flag
  session_path=$(echo "x" | "$AI_SESSION" new --goal "model test" --stdin --model "claude-opus-4-6" 2>/dev/null)
  session_abs=$(resolve_session "$session_path")
  jq_eq "meta: explicit model" "$session_abs/meta.json" ".model" "claude-opus-4-6"

  # --author flag
  session_path=$(echo "x" | "$AI_SESSION" new --goal "author test" --stdin --author "custom-author" 2>/dev/null)
  session_abs=$(resolve_session "$session_path")
  jq_eq "meta: explicit author" "$session_abs/meta.json" ".author" "custom-author"

  # --link flags
  session_path=$(echo "x" | "$AI_SESSION" new --goal "link test" --stdin \
    --link "https://example.com/pr/1" --link "https://example.com/issue/2" 2>/dev/null)
  session_abs=$(resolve_session "$session_path")
  jq_eq "meta: links count" "$session_abs/meta.json" ".links | length" "2"
  jq_eq "meta: first link" "$session_abs/meta.json" ".links[0]" "https://example.com/pr/1"
  jq_eq "meta: second link" "$session_abs/meta.json" ".links[1]" "https://example.com/issue/2"

  # --transcript flag (file copy)
  echo "transcript file content" > "$TEST_DIR/my-transcript.txt"
  session_path=$("$AI_SESSION" new --goal "transcript file test" --transcript "$TEST_DIR/my-transcript.txt" 2>/dev/null)
  session_abs=$(resolve_session "$session_path")
  assert_file_exists "copied transcript file" "$session_abs/my-transcript.txt"
  assert_eq "transcript file content preserved" "transcript file content" \
    "$(cat "$session_abs/my-transcript.txt")"

  # Missing --goal fails
  assert_fails "new without --goal fails" "$AI_SESSION" new --stdin

  # Unknown option fails
  assert_fails "new with unknown option fails" "$AI_SESSION" new --goal "x" --bogus

  # Breadcrumb reading
  mkdir -p "$TEST_DIR/.ai"
  jq -n '{session_id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", timestamp: "2025-01-01T00:00:00Z", model: "breadcrumb-model"}' \
    > "$TEST_DIR/.ai/.active-session"
  session_path=$(echo "x" | "$AI_SESSION" new --goal "breadcrumb test" --stdin 2>/dev/null)
  session_abs=$(resolve_session "$session_path")
  jq_eq "reads session_id from breadcrumb" "$session_abs/meta.json" ".claude_session_id" "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
  jq_eq "reads model from breadcrumb" "$session_abs/meta.json" ".model" "breadcrumb-model"
  jq_eq "short_id from breadcrumb session" "$session_abs/meta.json" ".short_id" "aaaaaaaa"

  # --model overrides breadcrumb
  jq -n '{session_id: "11111111-2222-3333-4444-555555555555", model: "breadcrumb-model"}' \
    > "$TEST_DIR/.ai/.active-session"
  session_path=$(echo "x" | "$AI_SESSION" new --goal "model override" --stdin --model "explicit-model" 2>/dev/null)
  session_abs=$(resolve_session "$session_path")
  jq_eq "explicit --model overrides breadcrumb" "$session_abs/meta.json" ".model" "explicit-model"

  # --repo flag (manual override)
  local ext_dir
  ext_dir="$(mktemp -d)"
  session_path=$(echo "external" | "$AI_SESSION" new --goal "external repo" --stdin --repo "$ext_dir" 2>/dev/null)
  assert_dir_exists "session created in external repo" "$ext_dir/$session_path"
  assert_file_exists "meta.json in external repo" "$ext_dir/$session_path/meta.json"
  rm -rf "$ext_dir"

  # ─── cmd_attach ───────────────────────────────────────────────────────────

  printf '\ncmd_attach:\n'
  teardown
  new_repo
  "$AI_SESSION" init --cache "$TEST_CACHE" >/dev/null 2>&1

  session_path=$(echo "x" | "$AI_SESSION" new --goal "attach target" --stdin 2>/dev/null)
  session_abs=$(resolve_session "$session_path")
  local sid
  sid=$(jq -r '.short_id' "$session_abs/meta.json")

  # Attach single commit
  "$AI_SESSION" attach "$sid" "abc1234" 2>/dev/null
  jq_eq "single commit attached" "$session_abs/meta.json" ".commits[0]" "abc1234"

  # Attach multiple commits
  "$AI_SESSION" attach "$sid" "def5678" "ghi9012" 2>/dev/null
  jq_eq "multiple commits total" "$session_abs/meta.json" ".commits | length" "3"

  # Deduplication
  "$AI_SESSION" attach "$sid" "abc1234" 2>/dev/null
  jq_eq "duplicate commits deduplicated" "$session_abs/meta.json" ".commits | length" "3"

  # Missing session fails
  assert_fails "attach to nonexistent session" "$AI_SESSION" attach "nonexist" "abc1234"

  # Missing args fails
  assert_fails "attach with no args" "$AI_SESSION" attach

  # ─── cmd_list ─────────────────────────────────────────────────────────────

  printf '\ncmd_list:\n'
  teardown
  new_repo
  "$AI_SESSION" init --cache "$TEST_CACHE" >/dev/null 2>&1

  # Empty list
  local list_output
  list_output=$("$AI_SESSION" list 2>&1)
  assert_match "empty list says no sessions" "no sessions found" "$list_output"

  # Create some sessions and list
  echo "x" | "$AI_SESSION" new --goal "first session" --stdin 2>/dev/null
  echo "x" | "$AI_SESSION" new --goal "second session" --stdin 2>/dev/null
  list_output=$("$AI_SESSION" list 2>/dev/null)
  assert_match "list shows first session" "first session" "$list_output"
  assert_match "list shows second session" "second session" "$list_output"

  # ─── cmd_show ─────────────────────────────────────────────────────────────

  printf '\ncmd_show:\n'
  teardown
  new_repo
  "$AI_SESSION" init --cache "$TEST_CACHE" >/dev/null 2>&1

  session_path=$(echo "x" | "$AI_SESSION" new --goal "show me" --stdin 2>/dev/null)
  session_abs=$(resolve_session "$session_path")
  sid=$(jq -r '.short_id' "$session_abs/meta.json")

  local show_output
  show_output=$("$AI_SESSION" show "$sid" 2>/dev/null)
  assert_match "show outputs goal" "show me" "$show_output"
  assert_match "show outputs valid JSON" "session_id" "$show_output"

  # Show nonexistent
  assert_fails "show nonexistent session" "$AI_SESSION" show "nonexist"

  # Show without args
  assert_fails "show with no args" "$AI_SESSION" show

  # ─── cmd_version / cmd_help ───────────────────────────────────────────────

  printf '\nversion & help:\n'
  local ver_output
  ver_output=$("$AI_SESSION" version 2>/dev/null)
  assert_match "version output" "^ai-session [0-9]+\.[0-9]+\.[0-9]+" "$ver_output"

  local help_output
  help_output=$("$AI_SESSION" help 2>/dev/null)
  assert_match "help mentions init" "init" "$help_output"
  assert_match "help mentions new" "new" "$help_output"
  assert_match "help mentions resume" "resume" "$help_output"

  # ─── cmd_new --auto ───────────────────────────────────────────────────────

  printf '\ncmd_new --auto:\n'
  teardown
  new_repo
  "$AI_SESSION" init --cache "$TEST_CACHE" >/dev/null 2>&1

  # --auto with no Claude projects dir just creates session without transcript
  session_path=$("$AI_SESSION" new --goal "auto no transcript" --auto 2>/dev/null)
  session_abs=$(resolve_session "$session_path")
  assert_file_exists "meta.json exists with --auto" "$session_abs/meta.json"
  jq_eq "transcript_hash null when no transcript" "$session_abs/meta.json" ".transcript_hash" "null"

  # ─── Summary ──────────────────────────────────────────────────────────────

  printf '\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
  printf 'Results: %d passed, %d failed\n' "$PASS" "$FAIL"
  printf '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'

  return "$FAIL"
}

run_tests
exit $?
