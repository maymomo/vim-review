# vim-review

Local inline code review comments for Vim.

`vim-review` lets you add comments to specific lines, show them later, and keep them scoped to the current Git commit (or current working directory outside Git).

## Features

- Add/edit comments on the current line.
- Show current-line comment quickly.
- Acknowledge comments without deleting original text.
- List comments for current file or full commit store in location list.
- Line signs (`💬`) for unacknowledged comments.
- Commit-scoped storage under `.vim_review/`.

## Installation

Use any Vim plugin manager, or copy this repo into your `runtimepath`.

Minimal manual setup:

```vim
set rtp+=/path/to/vim-review
runtime plugin/vim_review.vim
```

## Commands

- `:ReviewCommentAdd` add/edit comment at cursor line
- `:ReviewCommentAck` acknowledge comment at cursor line (mark ignored, keep text)
- `:ReviewCommentDel` delete comment at cursor line
- `:ReviewCommentCur` show comment at cursor line
- `:ReviewCommentShow` show comments for current file (location list)
- `:ReviewCommentList` list comments for current commit store (location list)

## Default mappings

- `<leader>ca` add/edit
- `<leader>ck` acknowledge
- `<leader>cd` delete
- `<leader>cs` show current line
- `<leader>cl` list commit comments

Disable defaults:

```vim
let g:vim_review_no_mappings = 1
```

## Storage

In a Git repo:

- `<git-root>/.vim_review/<commit-sha>-comments.json` (if `json_encode` exists)
- `<git-root>/.vim_review/<commit-sha>-comments.vim` (fallback)
- `<git-root>/.vim_review/latest-comments.json|vim` (link/copy to latest active store)

Outside Git:

- `<cwd>/.vim_review_comments.json|vim`

Acknowledged comments are saved as objects that preserve original text, for example:

```json
{
  "/abs/path/to/file": {
    "42": { "text": "rename this variable", "ack": 1, "ai": "ignore this comment." }
  }
}
```

## Quick workflow

1. Open a file and move to a line.
2. Run `:ReviewCommentAdd`.
3. Run `:ReviewCommentCur` to inspect current line.
4. Run `:ReviewCommentAck` when resolved.
5. Run `:ReviewCommentList` to review all comments for the current commit.

## Development checks

```bash
vim -Nu NONE -n +'set rtp+=.' +':runtime plugin/vim_review.vim' +q
vim -Nu NONE -n +'helptags doc' +q
```
