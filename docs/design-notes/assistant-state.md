# AssistantState

## The pulse is read from the clock, not stored in a flag

`pulseProgress` takes an absolute time and returns a number. The first version
instead toggled an `@State` bool under a SwiftUI `repeatForever` animation, and
it kept breathing after the answer had arrived and the state was back to idle:
a repeating SwiftUI animation outlives the value that started it. Measured, not
guessed — three captures of the character window a second apart, all in idle,
and the badge region differed in every pair.

Absolute rather than elapsed time is what lets the halo and the badge compute
the phase separately and stay in step. Anyone rewriting this as a stored
animation reintroduces the stuck breath.

## Only the badge scales; the halo never does

The halo is the frame the character sits in, and a frame that changes size moves
the character inside it. `peakScale` therefore applies to the badge alone — the
type cannot enforce which view reads it.

## The numbers

- `StatusPulse.busy` is a 10% step over 1.2s. The size step is what the owner
  asked for: large enough to catch the eye at 22pt across, small enough that it
  does not shove the character's shoulder about.
- `SubagentWatch.quietAfter` is 30s. Claude Code emits a `task_progress` line
  per step of a sub-agent's work; measured 2026-08-18 on CLI 2.1.234, a whole
  trivial sub-agent ran in 5.2s with a progress line at 2.7s. A gap of half a
  minute is already unusual, while anything shorter flickers on a sub-agent
  thinking between two tool calls.
- `SubagentWatch.presumedLostAfter` is five minutes. It does not mean "it
  failed" — nothing available here can know that. It is the point past which the
  honest thing is to stop implying work is under way: long enough for a slow
  single tool call (a test suite, a big grep) to finish and report, short enough
  to notice within one coffee.

## Why the pulse follows `isBusy` rather than a per-state table

A table with a row per state is a row somebody has to remember to add. The owner
wrote the request against `thinking`; `working` is the same wait with a tool
attached, and giving it a different rhythm would say something that is not true.
