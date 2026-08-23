---
name: rework-git-history
description: Rewrites a branch's messy commit history (many small "fix", "wip", "iteration" commits) into a small set of atomic, meaningful commits to ease code review. Triggers on "/rework-git-history", "clean up my commits", "squash these into logical commits", "reorganize this branch's history", or when a branch is ready for a PR but its history is noisy. Never pushes to a remote.
---

# Rework Git History

## Why this exists

During feature work it's normal to accumulate a long trail of small fix,
typo, and "wip" commits. That trail is useful while working but bad for
reviewers — it forces them to reconstruct intent from noise. This skill turns
that trail into a small number of commits that each tell a coherent part of
the story, while guaranteeing the resulting code is byte-for-byte identical
to what was there before the rework.

Speed is not the goal here — safety is. Every step below exists to make sure
the user can always get back to exactly where they started, and to make sure
you never silently change what the code does while changing how the history
looks.

## Overview

1. Preflight checks (clean tree, on a branch, not main)
2. Determine and confirm the commit range to rework
3. Read and understand the actual changes in that range
4. Propose a new commit plan and get it approved
5. Snapshot the current branch to `save/<branch-name>`
6. Rebuild the history via reset + re-stage
7. Verify the diff is unchanged and report the result

Do not skip a step or silently make decisions on the user's behalf at steps
2, 4, or 7 — those are the points where being wrong is expensive (lost work,
a misleading history, a PR that doesn't match reality), so they always need
an explicit human confirmation. The rest of the steps are mechanical once
those are settled.

## Step 1: Preflight

Run:

```bash
git status --porcelain
git branch --show-current
```

- If `git status --porcelain` is non-empty, **stop** and tell the user to
  commit or stash their changes first. Do not auto-stash — a rework already
  moves a lot of history around, and stashing on top adds a second thing
  that can go wrong silently.
- If the current branch is `main` (or whatever the repo's trunk branch is
  called — check `git symbolic-ref refs/remotes/origin/HEAD` or ask if
  unclear), stop. This skill only reworks feature branches.
- Note the current branch name — you'll need it for the save branch and for
  the final report.

## Step 2: Determine and confirm the commit range

Find the fork point from the trunk branch:

```bash
git merge-base HEAD main
git log --oneline $(git merge-base HEAD main)..HEAD
```

Show the user this commit list (oneline is enough at this stage) and the
merge-base commit, and ask them to confirm the range is right. Sometimes the
right range to rework is *not* the full branch — e.g. the user may only want
to clean up commits after a certain point (an earlier part of the branch may
already be reviewed, or already pushed and shared with someone else).

Prefer `AskUserQuestion` or a direct question over assuming. Do not proceed
past this point without an explicit confirmation of the range.

## Step 3: Understand the changes

For the confirmed range, read the actual content, not just the commit
messages — commit messages in the noisy trail are often stale or misleading
(that's part of why the rework is needed):

```bash
git diff <merge-base>..HEAD --stat
git diff <merge-base>..HEAD
```

For a large diff, read it in logical chunks (by directory or file group)
rather than trying to hold the whole thing in one pass. Build a real
understanding of what functionality changed, not just which lines changed —
you need this to propose commit boundaries that make sense to a reviewer.

Also check the repo's existing commit message convention so the new commits
match it:

```bash
git log -20 --format='%s' main
```

If commits follow a pattern (Conventional Commits, a ticket-prefix style,
plain imperative sentences, etc.), match it. If there's no clear pattern,
default to short imperative-mood subject lines (e.g. "Add X", "Fix Y"),
which is git's own convention.

## Step 4: Propose and confirm the new commit plan

Draft a plan: an ordered list of new commits, each with a description of
what it contains and a proposed commit message. Group changes by logical
purpose, not by chronology or by file type — e.g. "add the new API endpoint"
and "wire the frontend to it" are better boundaries than "backend changes"
then "frontend changes" if the frontend change only makes sense with the
endpoint, or worse, than commit-per-file.

Guidelines for a good plan:
- Each commit should build and, ideally, pass tests on its own — a reviewer
  should be able to check out any prefix of the new history and see a
  working state. If the original work makes this impossible without heavy
  surgery, say so rather than forcing it.
- Prefer fewer, more complete commits over many fragmentary ones. The
  original had too many; don't just relabel the same fragments.
- Pure noise (formatting-only fixes, revert-of-own-earlier-commit, "oops"
  typo fixes) should be folded into the commit that introduced the thing
  being fixed, not preserved as its own step.

Present this plan to the user and get explicit approval before touching any
git state. Expect iteration here — the user may want commits split,
merged, or reordered. Re-confirm after any change to the plan.

## Step 5: Snapshot the current branch

Before changing anything, save the current state so it can never be lost:

```bash
git branch save/<branch-name> HEAD
```

If `save/<branch-name>` already exists (e.g. from a previous rework
attempt), ask the user whether to overwrite it or use a different suffix
(e.g. `save/<branch-name>-2`) — never overwrite a save branch silently, it
may be the only copy of a previous rework's original state.

Tell the user this branch now exists and that it's their rollback path:
`git reset --hard save/<branch-name>` restores the pre-rework state exactly.

## Step 6: Rebuild the history

Reset to the fork point, keeping all changes in the working tree, then
rebuild commits one at a time from the approved plan:

```bash
git reset --soft <merge-base>
git reset   # now merge-base..HEAD's changes are unstaged in the working tree
```

For each commit in the approved plan, in order:

```bash
git add -p <relevant files>   # or git add <file> for whole-file commits
git commit -m "<message>"
```

Use `git add -p` (or `git restore --staged`/targeted `git add <path>`)
rather than `git add -A` whenever a commit needs only part of a file's
changes. After each commit, `git status` should show progressively less
unstaged/uncommitted material, ending at nothing once the plan is fully
applied.

If, partway through, the plan turns out not to match reality (e.g. changes
in two files are more entangled than expected and can't be split as
planned), stop and re-confirm the adjusted plan with the user rather than
improvising silently — this is the same bar as Step 4.

## Step 7: Verify and report

The entire point of the rework is that it changes *history*, not *code*.
Verify that directly:

```bash
git diff save/<branch-name> HEAD
```

This must be empty. If it is not, something in the rebuild introduced a real
change (not just a reordering) — stop, investigate, and fix it before
reporting success. Do not report the rework as done on the strength of "the
commits look right"; only an empty diff here is evidence.

Then show the user:
- The new commit list (`git log --oneline <merge-base>..HEAD`)
- Confirmation that `git diff save/<branch-name> HEAD` is empty
- The save branch name, as their rollback path

## Hard constraints

- **Never push, fetch with side effects, or touch any remote.** This skill
  only rewrites local history on the current branch. If the user asks to
  push the result, tell them the command to run themselves rather than
  running it — pushing rewritten history is a separate, higher-stakes
  decision that belongs to them, especially if the branch was ever pushed
  before.
- **Never skip the save-branch step**, even if the user seems to be in a
  hurry. It costs one command and it's the only thing standing between a
  mistake and lost work.
- **Never force the user's confirmation steps (2, 4, 7) into an assumption.**
  If you're inferring instead of asking because it "seems obvious", that's
  the moment to actually ask.
