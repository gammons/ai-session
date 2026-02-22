# ai-session

**Persist Claude Code conversation transcripts as git artifacts, linked bidirectionally to commits and PRs.**

Every time you use Claude Code to write code and then `git commit`, the conversation that produced that code is automatically captured — stored right in your repo, traceable from the commit, and surfaced on your pull request.

No extra steps. No copy-pasting. Just `claude`, `git commit`, `git push`.

```
commit a1f29c3 — Fix race condition in websocket reconnect

  Claude-Session: 2d8dfda4
  Claude-Session-Path: .ai/sessions/2026-02-22_0715Z_fix-race-condition-in-websocket-reconnec__2d8dfda4
```

## Why

Code tells you *what* changed. Commit messages tell you the *intent*. But neither captures the *reasoning* — the back-and-forth where you explored alternatives, debugged edge cases, and arrived at a solution.

When you work with Claude Code, that reasoning exists in the conversation transcript. `ai-session` makes sure it doesn't evaporate when the terminal closes:

- **Code review** — reviewers can read the AI conversation to understand *why* the code looks the way it does
- **Onboarding** — new team members trace commits back to the full problem-solving context
- **Debugging** — when something breaks, you can see exactly what Claude was told and what it considered
- **Audit trail** — every AI-assisted change is linked, hashed, and versioned alongside the code it produced
- **Session resume** — pick up exactly where you left off, even weeks later

## How it works

```
┌─────────────┐     PostToolUse hook      ┌──────────────────┐
│ Claude Code  │ ──────────────────────▶  │ .ai/.active-session │
│  (you work)  │   writes breadcrumb      │   (ephemeral)       │
└─────────────┘                           └────────┬─────────┘
                                                   │
┌─────────────┐     prepare-commit-msg    ┌────────▼─────────┐
│ git commit   │ ◀────────────────────── │ ai-session hook   │
│              │   creates session,       │  • creates folder │
│              │   adds trailers,         │  • copies transcript│
│              │   stages .ai/sessions/   │  • injects trailers│
└──────┬──────┘                           └──────────────────┘
       │
       │            post-commit
       ├──────────────────────────────▶ backfills commit SHA
       │                                into meta.json
       │
       │            pre-push
       └──────────────────────────────▶ auto-updates PR body
                                        with sessions table
```

Three git hooks, one Claude Code hook. All installed with a single command.

## Quick start

### Install

```bash
# Clone the repo
git clone https://github.com/your-org/ai-session.git

# Add to PATH (pick one)
ln -s "$PWD/ai-session/ai-session" ~/.local/bin/ai-session
# or
export PATH="$PWD/ai-session:$PATH"  # add to .bashrc/.zshrc
```

**Dependencies:** `bash`, `git`, `jq`. Optional: `gh` (for PR integration).

### Set up a repo

```bash
cd your-project
ai-session init
```

This creates the `.ai/` directory, installs three git hooks, and adds a Claude Code `PostToolUse` hook to `.claude/settings.json`.

### Use it

There's nothing else to do. Work normally:

```bash
claude                       # work with Claude Code
git add -p && git commit     # session auto-captured, trailers added
git push                     # PR body auto-updated
```

Your commit message will have trailers appended:

```
Claude-Session: 2d8dfda4
Claude-Session-Path: .ai/sessions/2026-02-22_0715Z_fix-race-condition__2d8dfda4
```

And your PR gets an AI Sessions table:

| Session | Goal | Model | Commits |
|---------|------|-------|---------|
| `2d8dfda4` | Fix race condition in websocket reconnect | claude-opus-4-6 | a1f29c3 |

## What gets stored

```
.ai/
  sessions/
    2026-02-22_0715Z_fix-race-condition-in-websocket-reconnec__2d8dfda4/
      meta.json            # structured metadata
      transcript.jsonl     # raw Claude Code transcript
      transcript.md        # human-readable markdown conversion
```

**`meta.json`** ties everything together:

```json
{
  "session_id": "2d8dfda4-b60c-4ffe-ace9-b66d93392823",
  "short_id": "2d8dfda4",
  "created_at": "2026-02-22T07:15:00Z",
  "author": "grant",
  "repo": "my-project",
  "branch": "fix/websocket-reconnect",
  "goal": "Fix race condition in websocket reconnect",
  "model": "claude-opus-4-6",
  "commits": ["a1f29c3"],
  "pr": "https://github.com/org/repo/pull/42",
  "claude_session_id": "2d8dfda4-b60c-4ffe-ace9-b66d93392823",
  "transcript_hash": "sha256:a3f2..."
}
```

## Commands

### `ai-session init`

One-time setup per repo. Creates `.ai/`, installs git hooks, configures Claude Code hook. Safe to run again — idempotent.

### `ai-session list`

```
$ ai-session list
2d8dfda4   2026-02-22T07:15:00Z claude-opus-4-6      Fix race condition in websocket reconnect
a9c3e1f0   2026-02-22T09:30:00Z claude-sonnet-4-6    Add unit tests for auth module
```

### `ai-session show <id>`

Print full session metadata as JSON.

### `ai-session new`

Manually create a session. Normally the git hooks handle this, but useful for edge cases.

```bash
# Capture current Claude session with a goal
ai-session new --goal "Refactor database layer" --auto

# Capture and immediately commit
ai-session new --goal "Add retry logic" --auto --commit

# Pipe in a transcript
cat notes.md | ai-session new --goal "Design review" --stdin

# With extra metadata
ai-session new --goal "Fix auth bug" --auto \
  --model claude-opus-4-6 \
  --link https://linear.app/team/issue/ENG-123
```

| Flag | Description |
|------|-------------|
| `--goal "..."` | Summary (required) |
| `--auto` | Auto-detect latest Claude Code transcript |
| `--transcript <path>` | Provide a transcript file |
| `--stdin` | Read transcript from stdin |
| `--model <name>` | Model name (auto-detected from breadcrumb/JSONL when possible) |
| `--author <name>` | Author (default: `git config user.name`) |
| `--link <url>` | Arbitrary URL, repeatable |
| `--commit` | Stage + commit with trailers |
| `--amend` | Amend last commit with trailers |
| `--repo <path>` | Store in an external repo instead |

### `ai-session attach <id> <sha>...`

Retroactively link a session to commits that were made without the hook active.

```bash
ai-session attach 2d8dfda4 abc1234 def5678
```

### `ai-session pr [<id>...] --pr <N>`

Link sessions to a pull request and inject an AI Sessions table into the PR body.

```bash
# Auto-detect: scan current branch for session trailers, update current PR
ai-session pr

# Explicit
ai-session pr 2d8dfda4 a9c3e1f0 --pr 42
```

### `ai-session resume <sha|--pr N>`

Relaunch Claude Code with a previous session's context.

```bash
# Resume from a commit
ai-session resume HEAD
ai-session resume abc1234

# Resume from the latest commit on a PR
ai-session resume --pr 42
```

## How the automation works

### Layer 1: Claude Code hook

When Claude Code edits a file (via `Edit` or `Write` tools), a `PostToolUse` hook fires and writes `.ai/.active-session` — a small JSON breadcrumb with the session ID, timestamp, and model. This file is gitignored.

### Layer 2: Git hooks

**`prepare-commit-msg`** checks for the breadcrumb. If it exists and is fresh (< 2 hours), the hook:
1. Uses the commit message's first line as the session goal
2. Creates the session folder with `meta.json` and transcript files
3. Stages everything under `.ai/sessions/`
4. Appends `Claude-Session` and `Claude-Session-Path` trailers to the commit message
5. Removes the breadcrumb

**`post-commit`** reads the trailers from the new commit and backfills the commit SHA into `meta.json`.

**`pre-push`** scans outgoing commits for session trailers. If the current branch has an open PR, it auto-updates the PR body with an AI Sessions table.

If no breadcrumb exists (you're making a normal commit without Claude), all hooks silently no-op.

## FAQ

**Does this slow down my commits?**
No. The hooks add ~100ms for session creation. If there's no active Claude session, they're instant no-ops.

**What if I don't want a session for a particular commit?**
Delete `.ai/.active-session` before committing, or just don't use Claude for that change — the hook only fires when the breadcrumb exists.

**Can I use this without Claude Code?**
Yes. Use `ai-session new --goal "..." --transcript my-notes.md --commit` to manually attach any document to a commit.

**Does this work with other git hook managers (husky, lefthook, etc.)?**
The hooks are thin shell wrappers. You can copy the one-liner from each hook into your existing hook manager config.

**How big are the transcripts?**
Varies. A typical Claude Code session produces 10-100KB of JSONL. For large repos, consider using `--repo` to store sessions in a separate repository.

**Can I strip sessions from history later?**
Yes — they're regular files. Use `git filter-repo` or similar tools to remove `.ai/sessions/` from history if needed.

## License

MIT
