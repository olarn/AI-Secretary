# ToolAdapters

## What makes the git adapter safe

`git` is launched by absolute path, never resolved through `PATH`. Arguments go
to `Process` as an array, so no shell is involved and there is no quoting or
injection surface. The argument vectors are hardcoded per operation: user text
selects a `CodeToolOperation` case and never reaches the command line. The
working directory comes only from a registered `Project`. Output is capped and
the process killed on timeout.

The checks are rails — each returns the value the next one needs — so nothing
launches unless every earlier check produced a right.

## `.git` is a file in a worktree, not a directory

`requireGitRepository` checks only that the `.git` entry exists, deliberately
without asking what kind it is. A worktree stores `.git` as a file; testing for
a directory would refuse every worktree in this repository.

## Path containment in the file adapter

The target is resolved against the project root and its real path — symlinks and
`..` resolved — must remain inside the project's real root. Both halves matter
and neither is redundant: absolute paths are refused before resolution, and
symlink resolution happens before the containment test so a link inside the
project cannot point outside it.

`FileToolAdapter.resolve` is public because watching a folder needs the same
answer as reading one. The alternative is a second copy of the escape check
elsewhere, which is how one of the two copies ends up subtly weaker.
