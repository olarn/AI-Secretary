#!/usr/bin/env python3
"""Stops the first Swift edit of a session until the skill has been read.

Why a hook and not a sentence in CLAUDE.md: the sentence was already there, and
a whole phase of work went past it anyway, because "is this domain code?" is a
judgement, and judgements get skipped under momentum. So this is a gate rather
than a nudge — but only the first `.swift` edit of a session, once, after which
it is silent for the rest of it.

What it costs: one refused edit, repeated after the skill is invoked. What it
buys: the Bow API facts arrive before the code is written rather than after the
build fails.

Reviewing and refactoring can't be hooked — they read rather than write — so
the skill's own description and CLAUDE.md carry that half.

To switch it off: delete the PreToolUse block in `.claude/settings.json`.
"""
import json
import os
import sys

STATE = "/tmp/claude-swift-skill-reminded"


def main() -> int:
    try:
        event = json.load(sys.stdin)
    except Exception:
        return 0

    path = (event.get("tool_input") or {}).get("file_path", "")
    if not path.endswith(".swift"):
        return 0

    # Once per session: the second reminder is noise, and noise is what gets
    # filtered out along with the first one.
    marker = f"{STATE}-{event.get('session_id', 'unknown')}"
    if os.path.exists(marker):
        return 0
    try:
        open(marker, "w").close()
    except OSError:
        pass

    print(
        "This edit was not applied. Swift in this repo is written to the "
        "`swift-functional-programming` skill — Bow APIs that do and don't "
        "exist, plus nine design rules and the SwiftUI boundary. Invoke the "
        "skill, then make this edit again. The same applies to any review or "
        "refactor in this session. (First Swift edit only; this won't fire "
        "again.)",
        file=sys.stderr,
    )
    # 2 is the exit code Claude Code reads as "refuse the call and show the
    # model why" — the only one that reaches the model rather than the log.
    return 2


if __name__ == "__main__":
    sys.exit(main())
