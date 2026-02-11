# Repository Guidelines

## Project Structure & Module Organization
This repository is a small Vim plugin organized by standard runtime directories:
- `plugin/vim_review.vim`: plugin entrypoint, commands, mappings, and autocommands.
- `autoload/vim_review.vim`: core implementation (`vim_review#...` functions, storage, signs).
- `doc/vim-review.txt`: user-facing help documentation.

Keep command/mapping wiring in `plugin/` and reusable logic in `autoload/`. Update `doc/vim-review.txt` whenever behavior or user commands change.

## Build, Test, and Development Commands
There is no build step; development is script-driven.
- `vim -Nu NONE -n +'set rtp+=.' +':runtime plugin/vim_review.vim' +q` loads the plugin in a clean Vim session to catch startup errors.
- `vim -Nu NONE -n +'set rtp+=.' +'help vim-review' +q` verifies help docs resolve (after generating tags).
- `vim -Nu NONE -n +'helptags doc' +q` regenerates help tags for local docs.

For interactive checks, open any file and test `:ReviewCommentAdd`, `:ReviewCommentShow`, and `:ReviewCommentList`.

## Coding Style & Naming Conventions
- Language: Vimscript (legacy script style in this repo).
- Indentation: 2 spaces, no tabs.
- Function naming:
  - Public autoload API: `vim_review#name`.
  - Script-local helpers/state: `s:name` / `s:var`.
- Prefer guard clauses (`if ... | return | endif`) for early exits.
- Keep side effects explicit (`echo`, file writes, sign placement) and localized.

## Testing Guidelines
Automated tests are not present yet. Use focused manual regression checks:
1. Add/edit/delete comments in a file.
2. Confirm signs refresh on `BufEnter`.
3. Confirm store switching between git repos/commits.
4. Confirm fallback storage outside git repos.

When adding logic, include at least one reproducible manual test case in the PR description.

## Commit & Pull Request Guidelines
Current history is minimal (`init commit`), so follow conventional, readable commits:
- Use imperative subject lines, e.g. `Add commit-aware comment store fallback`.
- Keep subject <= 72 chars; explain why in the body when non-trivial.

PRs should include:
- What changed and why.
- Manual test steps executed and results.
- Doc updates (`doc/vim-review.txt`) when commands/mappings/storage behavior change.
