# Developer scripts

The developer scripts: the icon generator, and the UI-driving tools under
`scripts/uidrive/` that exist to open the app and press things at it.

`scripts/uidrive/README.md` remains the place to start — it says which script to
reach for. What is kept below is the per-script reasoning that used to sit in
the source: why a probe uses the value it does, what a measurement is really
measuring, and which variants were deleted on purpose.

## make-icon.swift

Renders a source PNG into a set of square, transparent icon images and builds
an .icns file. The source needn't be square, and needn't be cropped: its
transparent margin is trimmed off, then what's left is aspect-fit and
centered on a transparent canvas, so nothing is stretched and nothing is
rendered smaller than the icon slot allows.

Usage: swift scripts/make-icon.swift <source.png> <output.icns>
The part of `source` that isn't fully transparent, in the image's own
coordinates.

Icon art arrives padded: the drawing in `docs/Noti-Icon.png` covers 62% x
57% of its 1024pt canvas, and drawing that margin too meant the artwork was
rendered at 62% of the size the icon slot allows — which is why it couldn't
be made out in Finder's list view (owner, 2026-08-19). Trimming here rather
than cropping the file keeps the source as it was delivered.

Returns the whole image when it is fully opaque, or when the pixels can't
be read — a slightly small icon beats no icon.

**Do not expect this to change what Finder shows on macOS 26.** It doesn't,
and that was measured, not assumed: asking `NSWorkspace.icon(forFile:)` for
the bundle before and after this trim returned artwork covering 80% x 80% of
the tile both times, `lsregister -f` included so it wasn't a stale cache.
macOS 26 fits the icon to its own tile regardless of the padding in the
`.icns`, so it is already doing this. What the trim fixes is the `.icns`
itself — 62% x 57% of its canvas became 91% x 84% — which is what any
surface reading the file directly gets. Making the icon read *larger* on
macOS 26 means an Icon Composer `.icon` asset instead, not a bigger drawing
in here.
Anything this faint reads as nothing on screen, and a stray
near-zero pixel in a corner would defeat the whole trim.
colorAt(x:y:) counts y down from the top; draw(in:from:) counts it up
from the bottom. Drop this flip and the art sits off-centre vertically by
however much the margins differ — which looks nearly right, so it is not
caught by glancing at it.
Scanned once, not once per variant: it is a read of every pixel in the
source, and there are ten variants.
How much of the icon's square the trimmed artwork is scaled to fill.

Not 1.0, because macOS masks app icons to a rounded square: art that reaches
the edge loses its corners. Measured against that mask at a 22.4%-of-side
corner radius, this drawing loses nothing even at 1.0 — its corners are
empty, being an atom rather than a square — so the 8% here is not paying for
clipping. It is margin against the mask being slightly tighter than that
measurement assumes, and it keeps the outer planets off the very edge of the
tile, where they would sit closer to it than any neighbouring app's icon.
Draws the opaque part of `source` aspect-fit and centered on a transparent
square of `pixels`.
(filename, pixel size) pairs required by iconutil.
Hand off to iconutil to produce the .icns.


## changed.swift

Where do two captures differ, and by how much?

Usage: swift changed.swift a.png b.png

Written for the thinking animation in 0.14.259-260, where neither question a
still can answer was the question that mattered. "Is it animating?" is two
frames apart in time differing *only* in the region that should move — this
prints that region's bounding box, so the claim names the pixels instead of
asserting from a screenshot. "Has it stopped?" is the same two frames coming
back `identical`, which is how the 259 bug was caught: three captures a
second apart with the app idle, and the badge differed in every pair.

`diff.swift` is the neighbour that greyscale-diffs a numbered f0/f1/f2 series
at once. This one takes two named files and tells you *where*.
Sum of channel differences. 0.06 is above capture noise and well
below anything a person would call a visible change.


## cmdsafe.swift

Presses a Command-shortcut N times, but only while the named process is
frontmost — checked in the same run, immediately before each press.
Synthetic keys have leaked into a terminal twice by trusting a check made
earlier in a different command.


## dragcap.swift

Drag a real file from Finder onto the app, and photograph the app *while the
pointer is still holding it*.

usage: swift dragcap.swift x0 y0 x1 y1 holdSeconds out.png x,y,w,h

Written for the drop area in 0.14.263, which exists only mid-drag: `drag.swift`
presses, moves and releases in one shot, so there is no moment left to
capture and the one thing worth checking cannot be seen. The hold here is
what makes it photographable.

Two things this encodes, both learned by getting them wrong first:

1. **Ask the picture where the icon is, not AppleScript.** Finder's
   `position of item` is relative to the icon view, and adding it to the
   window's `bounds` lands in the sidebar — the first run dragged the
   "Recents" row onto the app and the app, correctly, ignored it. Capture the
   Finder window, look at it, and read the icon's coordinates off the image.
2. **Keep moving while holding.** A drag with no events in flight can be
   treated as finished by the view under it, and the drop area disappears a
   moment before the capture.
Stepped and slow: Finder starts its drag session off the first few moves, and
a teleport produces no session at all.


## dragmeasure.swift

Drags the chat's resize grip outward in steps, printing both window frames at
each step so a character that moves during a resize is visible as numbers.
The grip is in whichever top corner the button row isn't. Both are probed by
starting the drag where the grip's glyph is drawn: 14pt padding from the edge.


## glide.swift

Moves the pointer the way a hand does — in steps, posting a mouseMoved for
each — then clicks. A warp teleports, which can deliver a control's
mouse-entered before the box's mouse-exited and leave hover in a state a
real pointer never reaches.


## hotkeyprobe.swift

Asks the system for the same combination the app claims. If the app is
holding it, this fails; if the app released it, this succeeds. A direct read
of who owns the key, rather than trusting the code that was supposed to
release it. Registers and immediately unregisters, so nothing is left held.


## keysafe.swift

Never post keys unless the intended app is frontmost — synthetic keys have
leaked into a terminal before.


## keyto.swift

Sends one keystroke, but only if the app that is about to receive it is the
one named on the command line. Testing a system-wide hot key means firing
keys while some *other* app is frontmost, so the usual "is our app in front?"
guard is inverted here — the risk is the same either way, which is a key
landing somewhere nobody expected.


## measure.swift

The two calls `partView` makes per message on every parent body evaluation.


## menubar.swift

The status item lives in the menu bar; find its owner's bar window.


## modkey.swift

Presses a key with modifiers, only while the given pid is frontmost.
An unknown name is a hard error, not a skipped modifier. `cmd` was missing
from this table while the README said it was supported, so `modkey <pid> 4
cmd` posted a bare `h`, printed "pressed", and read as "⌘H is broken" — for
half an hour, against an app whose ⌘H was fine. Silently dropping a modifier
is worse than refusing: the bare key still goes somewhere, and into a focused
chat box that means typing a letter into the person's message.


## paste.swift

Paste only — deliberately no Return, so nothing is sent.


## sendmsg.swift

The input sits just above the Settings/Profile/Projects row at the bottom.


## vwheel.swift

Vertical scroll at an explicit screen point. dir > 0 scrolls back up.


## wheelat.swift

Horizontal scroll at an explicit screen point.

