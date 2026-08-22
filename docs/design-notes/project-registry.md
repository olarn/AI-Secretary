# ProjectRegistry

## The per-character file migration is a value, and the move is in the adapter

`perCharacterFileMigration` decides; `FileProjectStore.adoptLegacyProjects`
moves. The split exists because a migration only ever runs on a machine that
holds the old file, so it cannot be checked by launching a fresh build — and
getting it wrong costs the person every project they had registered along with
the tool approvals attached to them. Splitting the decision out is what lets the
dangerous case be tested without a machine in that state.

## Why each character gets her own file

A project row is not a bookmark: it carries `allowedTools`, so the file is the
character's allowlist. Sharing one file means approving Claude Code for one
character approves it for all of them, which is the thing the separation exists
to prevent.

`FileProjectStore.legacySharedFile` keeps the old `projects.json` name rather
than becoming one character's by coincidence, so a second launch can still see
there was something to adopt.

## A path is never guessed from a name

`resolveProject` matches on registered names only. An unregistered name comes
back `.notFound`, never a directory derived from the query. This is a charter
rule, restated here because the function that enforces it is small enough to
look harmless.

## `grant` is called when a human approves, never on load

A project registered before a tool existed must not silently gain it, which is
why loading the file never grants and only the approval path calls `grant`.
