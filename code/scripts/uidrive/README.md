# uidrive — driving the running app

A charter rule says a UI feature is not done until it has been driven in the
running app. These are the tools that make that possible: they find the
window, move the pointer, post keys, and take the picture.

Nothing here is part of the build, and nothing here is run by the test suite.
`swift <script>.swift` interprets each one directly — no target, no package
membership. They were written one at a time over many sessions in a scratch
directory that gets deleted with its job, which is why they now live in the
repo.

```
swift win.swift $(pgrep -f "AISecretary.app/Contents/MacOS")   # where is it?
./cap.sh <pid> shot.png                                        # what does it look like?
swift glide.swift 1200 400 click                               # press the thing
```

## The four rules these encode

Each is a mistake that was made first and guarded against second. They are the
reason to reach for a script here instead of writing a one-liner.

**1. Ask the window where it is; never type a rectangle.** A rectangle copied
from an earlier run reads as "it fits" when it doesn't — a 720pt capture of a
643pt window once hid a panel overflowing past its bottom edge, because the
overflow was outside the crop. `cap.sh` reads the live bounds every time.

**2. Check frontmost immediately before every keystroke, in the same process.**
Synthetic keys have leaked into a terminal twice, both times because the check
happened in an earlier command and the focus moved in between. `keysafe`,
`cmdsafe`, `modkey`, `keyto`, `paste` and `sendmsg` all re-check and exit
non-zero rather than post. **The ungated key-posting scripts were deliberately
left behind** — `key.swift`, `cmdkey.swift`, `cmdshift.swift` — because a
gated and an ungated tool sitting side by side means eventually reaching for
the wrong one.

**3. Move the pointer the way a hand does.** `CGWarpMouseCursorPosition`
teleports, and a teleport can deliver a control's mouse-entered before the
box's mouse-exited, reaching hover states a real pointer never reaches. It also
generates no move event at all on its own. `glide.swift` steps and posts
`mouseMoved` for each step; `move.swift` is the raw warp, for when you only
want the cursor somewhere.

**4. Put the text on the pasteboard, don't pass it as an argument.** `paste`
and `sendmsg` take only a pid and paste whatever `pbcopy` left. Text that
begins with `-` broke the CLI once by being read as a flag; going through the
pasteboard means the text is never parsed by anything.

## What each one does

Pid below always means the app's pid:
`pgrep -f "AISecretary.app/Contents/MacOS"`.

### Finding things

| Script | Args | What it tells you |
|---|---|---|
| `win.swift` | `[pid]` | On-screen windows with `x= y= w= h= alpha=`. The panel is the one wider than 200pt. |
| `wins.swift` | — | This app's windows including hidden ones, with alpha and on-screen flag. For "did it get created at all?" — a panel that exists at `alpha: 0` is a different problem from one that was never made. |
| `onscreen.swift` | — | On-screen windows, desktop elements excluded. |
| `menubar.swift` | `pid` | The status item's bar window, for clicking the menu. |
| `screens.swift` | — | `frame` and `visibleFrame` of every display. |
| `front.swift` | — | Frontmost pid and name. |
| `hidden.swift` | `pid` | `isHidden` / `isActive` — an app can be running and invisible. |
| `keystate.swift` | — | Frontmost app plus current modifier flags. Read-only; safe to run any time. |
| `hotkeyprobe.swift` | `code mods` | Asks the system whether that combination is registered, and by whom. Written when a hot key was declared but never fired. |
| `activate.swift` | `pid` | Brings the app to the front. Run before anything that posts keys. |

### Pictures

| Script | Args | Notes |
|---|---|---|
| `cap.sh` | `pid out.png` | The panel at its live bounds. **Start here.** |
| `capchar.sh` | `pid out.png [nth]` | One character window — the narrow ones — at its live bounds. There is one per profile, hence the index. |
| `changed.swift` | `a.png b.png` | Bounding box of what differs between two captures, or `identical`. **The only way to check an animation**: one still cannot show a thing moving, and cannot show it has stopped. Caught the 0.14.259 badge still breathing at idle. |
| `shot.swift` | `pid out.png [height]` | Top `height` points of the window (default 90) — the header strip. |
| `shotbottom.swift` | `pid out.png` | The bottom strip — the input row and footer. |
| `diff.swift` | — | Greyscale-diffs `f0.png` against `f1.png`, `f2.png`, … in the working directory. Name frames that way and it reports which ones actually changed. |

### Pointer

| Script | Args | Notes |
|---|---|---|
| `glide.swift` | `x y [click]` | Stepped move, then optionally clicks. The one to use for hover. |
| `move.swift` | `x y` | Raw warp, no events. |
| `click.swift` | `x y` | Warp, pause, click. |
| `slowclick.swift` | `x y hold` | Click holding the button `hold` seconds — for press-and-hold. |
| `cmdclick.swift` | `x y` | Command-click. |
| `drag.swift` | `x0 y0 x1 y1` | Press, move, release. |
| `dragcap.swift` | `x0 y0 x1 y1 hold out.png x,y,w,h` | Drags a real file from Finder onto the app and photographs it **while still holding it**. For anything that only exists mid-drag — `drag.swift` releases before there is anything to see. Read the source icon's position off a capture of the Finder window; Finder's own `position of item` is relative to the icon view and lands in the sidebar. |
| `dragmeasure.swift` | `pid steps dx dy [right]` | Drags the resize grip and prints the window size after each step, so the numbers can be compared against what the layout intended. |
| `vwheel.swift` | `x y dir [ticks]` | Vertical scroll at a point; `dir > 0` scrolls up. Ticks default 10. |
| `wheelat.swift` | `x y dir` | Horizontal scroll at a point. |
| `wheel.swift` | `pid dir` | Scrolls over the middle of the app's window. |

### Keys and text — all frontmost-gated

| Script | Args | Notes |
|---|---|---|
| `keysafe.swift` | `pid code times` | Posts a bare key `times` times, only while `pid` is frontmost. |
| `cmdsafe.swift` | `pid code times` | Command-shortcut, re-checking frontmost before each press. |
| `modkey.swift` | `pid code mod…` | Key with modifiers named as words: `cmd`, `shift`, `option`, `control`. An unrecognised name exits 2 rather than being skipped — `cmd` was absent from the table while this row claimed it worked, so `modkey <pid> 4 cmd` posted a bare `h` and read for half an hour as "⌘H is broken" in an app whose ⌘H was fine. **SwiftUI's `onKeyPress` does not see the modifier on a synthetic event** (measured 2026-08-17 on Shift+Return): the key arrives, `press.modifiers` is empty, and a handler that branches on it takes the wrong arm. A modifier the app reads through `NSEvent` is fine; one read through `onKeyPress` has to be pressed by hand. |
| `keyto.swift` | `appName code [cmd]` | **Inverted guard**: refuses unless the named app *is* frontmost — for testing a system-wide hot key, where the point is that our app is *not* in front. |
| `paste.swift` | `pid` | Opens the panel, focuses the input, pastes the clipboard. Deliberately does **not** press Return. |
| `sendmsg.swift` | `pid` | Same, then Return. Put the message on the clipboard with `pbcopy` first. |
| `frames.sh` | `pid` | Three captures of the choice list — before any key, after Down, after Up — as `frame1/2/3.png`. A worked example of the gated pattern. |

### One-off harnesses, kept as examples

`measure.swift` takes no arguments and measures the two `NSAttributedString`
calls the transcript makes per message. It produced the ~0.2ms-per-message
figure behind the scroll fix in 0.10.199. Keep it as the shape to copy when a
cost needs a number rather than an opinion: measure the real call, in a
standalone process, before changing anything.

## Key codes

The ones that come up: Return 36, Tab 48, Escape 53, Down 125, Up 126, Left
123, Right 124, `c` 8, `v` 9, `h` 4, `,` 43.

## Caveats

- The pid is not stable. Re-read it after every relaunch; a stale pid makes
  `win.swift` print nothing, which looks like "the window is gone".
- Coordinates are screen points with the origin at the top-left, matching what
  `win.swift` prints and what `screencapture -R` wants — not AppKit's
  bottom-left `NSScreen` coordinates.
- Posting events needs Accessibility permission, and capturing needs Screen
  Recording — both granted to whatever runs them (Terminal, or the editor's
  shell), not to the app. The failure looks like a bug in the script rather
  than a permission: `screencapture` prints `could not create image from rect`
  for *any* rectangle, and posted clicks are simply ignored. Check
  `swift front.swift` first — if the app you meant to drive isn't frontmost,
  nothing else you observe means anything.
- **Don't drive the app while someone is using the machine.** `front.swift`
  showing an app you didn't expect is the signal to stop, not to activate over
  it.

## What was verified when these moved here

Moved out of the job scratch directory on 2026-08-12. Every script here had
been used successfully in the sessions that produced it. Re-run from this
directory at the time of the move: `win.swift`, `wins.swift`, `front.swift`,
`screens.swift`, `activate.swift`, `glide.swift`, `slowclick.swift`, and
`cap.sh`'s "panel isn't open" path.

`cap.sh` is the one file rewritten during the move — it had a pid and an
absolute scratch path baked in, and now takes `<pid> <out.png>`. **Its capture
path is unverified**: Screen Recording was denied to this shell at the time,
so `screencapture` failed for every rectangle. The bounds-finding half of it
was checked; the last line was not.
