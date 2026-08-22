# AISecretaryApp (SwiftUI and AppKit)

The SwiftUI and AppKit layer. Nothing here is linked into the test bundle —
measured at v0.6.60, not one of these files appeared in the `llvm-cov` report at
all — so this is the one target where a comment could not be turned into a
failing test, and where a refactor could not be proved safe by running the
suite. It was therefore cleared of comments **without restructuring**: the code
below is the code that shipped, with its explanations moved here.

That makes this file the most important one in the directory. Most of what
follows is AppKit and SwiftUI behaviour that was discovered by driving the app
and watching it go wrong — a window that shrank back to its layout size, a key
that never arrived, a cursor that would not change while the app was inactive.
None of it is derivable from the code, and all of it is the kind of thing a
later reader will otherwise "clean up" and rediscover the hard way.

If you are about to change a view, a panel, or a window here, read its section
first.

## AboutPanel.swift

The About window, opened from the status bar menu.

AppKit's own panel rather than a hand-built window: it already lays out the
icon, name, version and credits the way every other Mac app does, and this
app has no reason to look different in the one place users go to check what
they're running.

The values are passed explicitly instead of being read from the bundle. The
app is often run straight from the SwiftPM build directory, where there is no
`Info.plist` at all, and an About window that says "AISecretaryApp" with no
version is worse than none.
The panels never take focus, so without this the window opens behind
whatever the user is working in — it looks like nothing happened.
Blank, or AppKit appends its own build number in parentheses;
there is only one number worth showing here.
The commit is here rather than in the version line so the version
stays the thing people quote, while "which build is this?" — the
question that comes up when a fixed thing looks broken again — is
still answerable without a terminal.


## AppDelegate.swift

What belongs to the app rather than to any one character: the look, the
roster, and the single status bar item. A character's own world — her
Secretary, her windows, her Claude Code session, and since 13-1 the
projects she may work in — lives in `CharacterInstance`.
Where Claude Code is — the machine's answer, found once and handed to
every character. The session built on top of it is hers; this is not.
The characters on the desktop. One for now; the point of the type is
that this becomes several without the delegate changing shape.
The one the menu and the app-wide shortcuts act on: whoever was last
worked with, falling back to the first on the desktop.

It matters more since 13-1 than it did when it was simply
`characters.first`. Token Usage and About have no look of their own, so
this is also the character whose theme and text size they borrow.
How the characters reach each other. Asks for the roster rather than
holding it, so a character added or deleted needs nothing rewired.
Banners for work that finished while nobody was watching, and the way
back in when one is clicked.
Watches this app's own key events for ⌘H; see `watchForHideShortcut`.
The same, for Esc with nothing left to put away; see `watchForDismissKey`.
Who ⌘H took off the desktop, so reopening puts back exactly them.
Who had a chat open when everything went away, so "Show All" can put the
conversation back rather than only the characters.
Whether ⌘H took the command window too, so Show All brings it back.
The command window's state: who is ticked, and who has been commanded.
Delivery goes through `submit` — a broadcast is the same act as typing
the same thing in each ticked character's own chat, which is the whole
promise of the window.
Attachments first, so the submit that follows carries them —
the same order typing in her own chat produces.
No visibility callback: the status menu rebuilds itself every time it
opens, which is the only moment its wording can be seen.
Who the usage window adds up. Kept in step by `reconcileCharacters`.
Every profile is a character, and every character is on the desktop.
Adding or deleting a profile is adding or deleting a character; the
roster follows the library rather than being kept in step by hand.
Before this method returns: a click on a banner may be what launched
the app, and the system delivers it the moment a delegate exists.
Renaming or re-describing a character has to reach her prompt, not
just her label.
Esc is claimed from the whole system, so the bubble answers it while
the user is typing in another app. Only Esc, and only while the chat
is showing — see `GlobalShortcut` for why ⌘H is not in this list.
Esc means "put away whatever is in front" — for whichever
character that is. `dismissDecision` decides; this only asks the
windows who has the keyboard.
MARK: - The roster

Brings the characters on screen into line with the profiles that exist.

Written as a reconcile rather than as "add this one" / "remove that one"
so that add, delete and launch are the same code path — the alternative
is three places that can disagree about who is on the desktop.
The one place that should touch the real files. Everywhere else —
every test — gets the in-memory defaults and cannot reach them.
Who else is on the desktop, and how to reach them. Read at the start
of each turn rather than pushed, so a character added or renamed
mid-session is simply there in the next prompt.
A card raised while she is under command belongs where the person is
looking. Told both ways: put up, and taken down again.
Token Usage is wearing somebody's look and the somebody just
changed. Doing this only when the window is reopened left it in
the previous character's theme for as long as it stayed open.
Her settings resize her own windows and nobody else's — this was one
callback for the whole app when there was one look to apply, and
applying one character's theme to all of them is now precisely the
bug.

The re-lighting still goes through the app-wide sweep, though, and
that is not a leftover. Token Usage has no theme of its own and is
wearing the focused character's; when she changes hers while it is
open, nothing else would tell it. Driven at 0.13.216 before this
line existed: its body went light and its title bar stayed dark.
This character's own history file, adopting the one everybody shared
before characters had their own.

The failure is discarded on purpose, and explicitly rather than by
omission: it can only be a rename that didn't happen, the character then
starts with an empty history instead of her old one, and there is no
useful thing to say about it while the app is still opening. Nothing is
deleted either way — the old file is still there to adopt next launch.
This character's own project registry, adopting the one everybody shared
before characters had their own. Same shape as `historyFile`, and the
failure is discarded for the same reason.

What she adopts is an allowlist, not a list of folders: a project row
carries the tools approved for it. Whoever is built first takes it, and
nobody else inherits those approvals — which is the whole point, and is
also why a second character starts with none.
MARK: - Notifications

A character has finished something. Whether that is worth a banner is
`completionNotice`'s decision — this only gathers the one fact she
cannot see from inside herself: whether her chat is on screen.
The command window's results strip hears about every commanded
character's turn, banner or no banner — the strip is the reason the
person does not have three chats open.
Her portrait rides along when she has one. Asked through the Bool and
the URL rather than `resolve`, whose `Option` would mean importing
FunctionalCore into a file that sits next to SwiftUI.
A banner was clicked: bring back the character who posted it, with her
chat open — the answer being on screen is the point of the click.

The two ⌘H sets are cleared for her because she is on the desktop again
whatever they say, and leaving her in them would have Show All believe
it still owes her an appearance.
MARK: - The status bar menu

Reads the current state of every character for `statusBarMenu`, which
decides what the menu contains. Gathering, not deciding.
Applies what a menu row asked for. Every case names the character it is
about, so nothing here has to guess which one the click meant.
Starting a conversation means having one. Clearing the slate
behind a hidden window would leave nothing to show for the click,
and the bubble being closed is a common reason to reach for the
menu in the first place.
Reopening a conversation from the menu means wanting to look at
it, and the bubble may well be hidden — that is often why the
menu was used at all.
From the default profile, not a clone of whoever is focused —
the owner asked for that switch in 20.1. What she is called is
still `newCharacterDraft`'s decision; adding her to the library
brings her window up through `reconcileCharacters`.
Her default face is the app icon itself — the icns, whose art
`make-icon.swift` has already trimmed and fitted, which is what
sits well in the round avatar frame. The raw artwork PNG was
tried first and the owner sent it back: its proportions don't
fit the character frame (2026-08-19). Read from the bundle
file, NOT `applicationIconImage`, which answers with a generic
folder when the app runs unbundled (`swift run`, while
driving) and put a folder on a character once. No icns — a dev
run — means no picture at all: never a wrong face.
Esc. The system grants the key once, so one character has to be picked;
the rule is `dismissDecision`, and this gathers what it needs.

- Returns: whether it acted, which the local monitor needs in order to
  decide whether to swallow the keystroke or hand it on.
The command window first, on either path. While it holds the
keyboard, Esc typed into it is what the backlog specifies: hide the
window, leave the sessions running. Without this rung the hot key —
claimed whenever any chat bubble is dismissable — consumes the press
and spends it on a chat the person is not even typing in.
Esc once more, with the chat already closed: she goes away too.

A *local* monitor, and that is the entire design. Esc could not be added
to the system-wide claim — `GlobalShortcut` is a receipt for what that
costs, and a character is visible nearly all the time, so claiming Esc
while she is on screen is claiming it permanently. Locally, the key only
reaches us when one of our own windows holds the keyboard, which is also
the only situation in which "hide her" is what the person meant.

It cannot double up with the hot key: `dismissDecision` returns nothing
for a local press while anything is dismissable, so exactly one of the
two paths answers any given press.
⌘H, taken from this app's own event stream while one of its windows has
the keyboard.

The menu item can't do it alone. The chat bubble is a non-activating
panel: it takes the keyboard without making the app frontmost, and a menu
key equivalent is only searched in the *active* app's menu — so pressing
⌘H while typing in the bubble hid whatever was behind it instead. A local
monitor sees the event because the key window is ours, which is exactly
the condition under which the shortcut should be ours.

Local, not a Carbon hot key: taking ⌘H from the whole system broke Hide
in every other app once already, and this claim ends the moment the
keyboard does.
What ⌘H does: the whole app leaves the screen — every character, every
chat, every pinned pane, Token Usage and About.

`NSApplication.hide` is not it. An accessory app has no Dock tile to come
back from, and its own panels are `hidesOnDeactivate: false` precisely so
that clicking into another app does not take the companion away — which
leaves this as the one thing that can honestly mean "all of it, now".

Written as `hide`, never `toggle`: applied to a roster, a toggle brings
back whoever was already away, so ⌘H would have shown a character
instead of hiding one.
Taken before they close, because that is the only moment it is
knowable — and it is what "bring it all back" has to mean.
Remembered before the blanket sweep below takes it, or "Show All"
could never bring it back — the asymmetry this method's doc warns of.
The About window is AppKit's, opened by
`orderFrontStandardAboutPanel`, and there is no handle to it — this
sweep is how it goes away, and it also catches anything a later sprint
puts on screen without telling this method about it.
The other half of the menu's one row: everybody back on the desktop,
with the chat that was open when they left.

Symmetric with `hideEverything` on purpose — what went away is what
comes back. Restoring the characters but not the conversation would make
"Show All" a different act from undoing "Hide All", and the bubble that
vanished is usually the reason the menu is being opened again.

Nothing is opened that was not open. If no chat was showing, none
appears: a window arriving unasked is worse than one that stayed shut.
Anyone the roster gained while everything was away comes back too —
a character created behind a hidden desktop must not stay invisible
with no row that would reveal her.
Esc is worth claiming only while something is on screen to dismiss —
a chat bubble or a pinned pane. Called from the characters, since any of
them can be the last one standing.
Hands Esc back to the rest of the system on the way out. The process
dying releases it anyway; doing it explicitly means a slow teardown
can't leave the key claimed by a window that's already gone.
A kept Claude Code process is not a child that ends when we do —
quitting without this leaves one `claude` per character running with
nothing attached to them.
Launching the app again while it is already running.

macOS does not start a second process — it reactivates this one and
sends this. With the character hidden, nothing at all would appear, and
double-clicking the app again is exactly what someone does when they
can't see it. Hiding is for getting it out of the way for a moment, not
a setting to be remembered, so reopening always brings it back.
Exactly who ⌘H took away, since ⌘H can now take away several. Coming
back with one character when three went is the kind of asymmetry that
reads as a lost character rather than as a shortcut.
MARK: - Menu commands

⌘+ / ⌘−, doing exactly what the +/− buttons in Settings do. Wired here
rather than in the panel because the shortcut has to work whenever the
app is active, including when the chat is closed.

It resizes the text of one character — whoever was last worked with —
now that the size is hers rather than the app's. A shortcut that changed
all of them would be the one thing on this screen that still treats them
as one.
While the command box holds the keyboard the shortcut sizes *that
box's* text — the window is the app's, and growing one character's
bubbles because the caret happened to be here would resize windows the
person is not looking at.
⌘H. Goes through the same toggle the status bar item uses; the character
reports back so the menu's wording doesn't go stale.
Finds Claude Code off the main thread. The fast path is a handful of
`stat` calls, but the fallback launches the user's login shell, which can
take seconds — doing that here would delay the character appearing.

Asked of the detector rather than of a character's backend: the answer
is the machine's, every backend is already watching for it, and running
it once is the point of the split.
Asking as soon as there is something to ask: the sign-in
check needs the executable, so it cannot run any earlier, and
waiting for the panel to be opened would leave the app with
no idea whether it can work until somebody looked.
Re-lights every window, each character from her own theme.

Token Usage has no theme of its own and takes the focused character's,
which is the same one it was built with unless the person has since gone
and worked with somebody else — `show(using:)` catches that case.


## AppMenu.swift

The app runs with `.accessory` activation policy, so this menu is never
*drawn* — there is no menu bar for an agent app. It still has to exist:
`NSApplication` matches command-key equivalents against `mainMenu` before
anything else, so without it ⌘Q, ⌘C, ⌘V and friends simply do nothing while
the app is active. Installing an invisible menu is the supported way to give
a menu-bar-only app the standard keyboard shortcuts.

Every item targets `nil` so it travels the responder chain: Quit reaches
`NSApplication`, and the editing items reach whichever text field is first
responder inside the chat panel.
⌘+ and ⌘− for the text size, the same thing the +/− buttons in Settings
do. Unlike the editing items these can't travel the responder chain —
nothing in it knows about the appearance — so they're aimed at an explicit
target, which must outlive the menu.

Both `+` and `=` are registered for growing: ⌘+ on most layouts is really
⌘⇧=, and people press it with and without the shift.
No ⌘H item here, deliberately. There was one — "Hide Character", from
before Sprint 13-2 made ⌘H mean the whole app — and because this menu
is searched before any local monitor, it went on answering ⌘H with the
old one-character behaviour whenever `handlesHideLocally` declined.
Under a non-Latin layout that was *every* press, so the newer feature
never ran. The monitor in `AppDelegate.watchForHideShortcut` owns the
key now, and it is the only thing that can: a menu key equivalent is
searched in the frontmost app's menu, and the chat bubble takes the
keyboard without making this app frontmost.

Per-character hiding is still there, on each character's own row in the
status bar menu.

Also in the status bar menu, but a key equivalent only works from the
main menu — a status item's menu is not searched for shortcuts, so
⌘U there did nothing at all until this existed.
Standard editing shortcuts. Without these the chat text field has no
copy, paste, select-all or undo — a real gap in an app whose only input
is a text field.
What the shortcut items call. Declared as a protocol so `AppMenu` can name
the selectors without depending on the delegate that implements them.

These can't travel the responder chain the way the editing items do —
nothing in it knows about the appearance or the character window — so each is
aimed at an explicit target, which must outlive the menu.


## Appearance.swift

One character's look: her text size, her window height, how big she is
drawn, and her theme. Shared by the panel that changes it and the window
that has to resize.

One of these per character since 13-1. The app-wide windows — Token Usage,
About — have no character of their own, so they follow whichever character
was used last; see `AppDelegate.focused`.

The rules live in `AppearanceSettings`; this holds the current value,
persists every change, and tells the window when to resize. `onChange` is a
callback rather than the delegate observing the object, because resizing an
`NSPanel` is imperative work that has to happen once per change, not
re-derived during a view update.
Whether macOS is currently in dark mode. Stored and observed rather than
read where it's needed: the `System` theme has to repaint when the user
flips the system setting, and a value read inside a `body` is not
something SwiftUI knows to re-read.
No screen to measure means no limit to apply, so the saved size stands
as its own ceiling. Falling back to the default here would shrink a
window the user had deliberately grown.
The colours everything is painted with right now.

Module-qualified because the property and the function that computes it
share a name, which is the right name for both.
AppKit posts this on the distributed centre when the user changes the
system's light/dark setting. Without it, `System` would only be re-read
at launch — the app would keep its old palette until relaunched, which
looks exactly like the setting not working.
Only `System` is following it; the other two are the user
saying the system setting is not what they want.
Re-applies the limits of the screen the character is actually on. Worth
doing when the panel is about to be shown, since the display may have
changed since launch.

A `nil` frame leaves the limits alone: an unknown screen is not the same
as a tiny one, and treating it as tiny would collapse the window and
leave the widen button dead with no way to explain why.
The character window is resized imperatively too, so a scale change
has to reach the delegate the same way a height change does.
A theme change is imperative work on the window too: the control
appearance is an AppKit property, not something a SwiftUI body can
return, so it goes through the same callback as a resize.
Glass flips an NSWindow property too — the shadow, which hides
behind the solid bubble and hangs as a dark blot behind the
glass one. Same reasoning as theme: not something a SwiftUI
body can return.


## AttachmentPicker.swift

Picks a file to hand to the assistant through a system panel.

Same rule as the project and profile pickers: the file always comes from an
explicit human choice rather than a path the app derived. The allowed types
are the ones the assistant can actually read, so a file it would refuse is
greyed out in the panel rather than refused afterwards.
Several at once: the data for one form is often several files — the
rows in one, the attachment to upload in another — and making that
three trips through a dialog is three chances to send the wrong one.
The list has its own cap and says so when it is reached.
Broad on purpose: source files, notes, configuration and PDFs are
all things people hand over, and a panel that greys out the file
they came to send is a dead end with no explanation in it. `.data`
catches the extensions macOS has no type for — an unnamed format is
taken if its bytes are text, and refused with words if they aren't.
An open panel owned by an inactive app is not key, and its file list
ignores clicks until something activates the app — the same reason
`ProjectPicker` and `ImagePicker` do this.
Esc has to cancel this dialog, not the chat window behind it.


## BackendStatus.swift

What the UI knows about where work will run.

Detection can involve launching a login shell, so it happens on a background
task after launch and this object is how the result reaches the views. `nil`
means "still looking" — the panel shows neither the onboarding card nor a
confirmed backend until we actually know.
Whether the maker can actually be reached, which is a different question
from whether its tool is on disk — see `VendorConnection`.
Which maker the app is set up to use. One today; this is the value the
vendor picker will write.
True only once we've looked and found nothing.
Asks the maker whether it can be reached, and publishes the answer.

Every state it can be in is produced by `vendorConnection`, so this
method chooses nothing — it gathers the two inputs and applies the
answer. That is deliberate: `AISecretaryApp` is never linked into the
test bundle, so a rule decided here would be a rule no test can see.


## BoxHover.swift

Which box in the transcript the pointer is on, and which was last copied.

A reference type rather than two `@State` values on the panel, for one
reason: with `@Observable`, a view is subscribed to exactly the properties
it *reads*. Keeping these here lets the panel own them and hand them to the
leaf that draws the buttons, without the panel itself being invalidated when
they change — which is what scrolling a long thread does, repeatedly, as
each box slides under a stationary pointer.

It holds two values and applies one rule; the rule itself is
`hoverClaim`, in `SecretaryCore`, where it can be tested.
The box's one `.onHover`. Only the box calls this — see `hoverClaim`
for why the buttons must not.
Assigning an unchanged value would still notify every observer, and
a sweep across the thread delivers plenty of events that change
nothing.
Draws `content` only while the pointer is on `box`.

This exists to be a leaf. The comparison against `hover.pointingAt` has to
happen somewhere, and wherever it happens is what gets rebuilt on every
hover change — so it happens here, in a view whose entire body is an `if`,
rather than in the panel, whose body rebuilds sixty messages.


## CharacterBus.swift

Carries a message from one character on this desktop to another.

**Routing, and nothing else.** Whether a message may go, what each
conversation says about it, and how a relayed request is put to the
character who has to act on it are all pure functions in `SecretaryCore` —
this target is never linked into the test bundle, so a rule decided here
would be a rule no test has ever run.

Everyone lives in one process on one actor, so delivery is a call. The
shared file with a lock around it that Sprint 14.3 describes would buy every
hazard that sprint lists and nothing else, while this is true.
Asked for the roster rather than holding it. The characters are owned by
the app delegate and come and go as profiles are added and deleted; a
list kept here would keep a deleted character alive and answering.
Everyone except her, as her prompt needs to see them.
On the next pass rather than inside the call that produced it: a
report is sent while the sender is still closing off her own reply,
and a recipient that starts a turn synchronously would start it
inside that one.
Her as her neighbours are allowed to see her: a name, a model, an
effort, and the *name* of the project she has open. No path, and nothing
that could be used to reach into her work.
The *effective* pair, short. `modelDescription` was handing over a
raw model id and the phrase "your Claude Code default", so the
roster paragraph read "claude-opus-5, effort your Claude Code
default" — against this field's own documented contract, and
against the wording every test fixture here has always used.


## CharacterInstance.swift

One character on the desktop, and everything that belongs to her alone.

This type exists to be multiplied. Until now each of these was a single
property on `AppDelegate` — one state machine, one Secretary, one pair of
windows, one Claude Code session — which made "add a second character" mean
editing the same forty lines twice. Gathering them here first means the
second character is a second `CharacterInstance`, not a second copy of the
delegate's body.

What stays outside is what is genuinely the app's rather than hers: the
theme and text size, the roster of profiles, the project registry, the
status bar item, and the Esc claim, which the whole system can only grant
once.
Which profile she is. The profile itself lives in the shared
`ProfileLibrary`; this is the key, so two instances can never disagree
about who they are.
Hers since 13-1. Not private: the app-wide windows have no look of their
own and borrow the focused character's.
Hers since 13-1, and the file behind it is hers too. Held so
`buildWindows` can hand the panel the same instance the Secretary was
given.
Hers: which maker she works through, and whether it can be reached.
Told when this character gains or loses something Esc could dismiss.
The claim is system-wide and singular, so the decision is not hers to
make — she only reports that her answer changed.
Told when this character is the one being worked with. Token Usage,
About and the ⌘+/⌘− shortcuts have no character of their own and follow
whoever this last named.
What the character view asks for at 1×, measured from the view itself
rather than written down here — a hard-coded window that was a few points
too small clipped the halo into a flat edge across the top of the head.
The window follows the S/M/L choice; `CharacterView` scales to match.
Both axes are the user's now, from Appearance. The tail is positioned
against the width rather than at a fixed offset, so `applyChatLayout`
re-anchors it on every size change and it stays on the character.
Where the tail tip sits along the bubble's edge, taken from the shape
itself so the two can't drift apart. A distance rather than a fraction,
so widening the bubble leaves the tip on the character.
How far the bubble is pushed sideways, away from the character, as a
fraction of **the character's** width — not the bubble's.

It has to scale with the character or the same offset reads differently at
each size: a fixed 36pt put the tail tip outside a small character
altogether (S looked detached) and well inside a large one (L sat under
the bubble). As a share of the character's width, the tip lands on the
same spot at every size.
Gap between the character and the bubble window. The tail tip now ends
exactly at the window edge, and the character's avatar sits ~12pt inside
its own window, so a small negative gap makes the tail visually touch
the avatar. Scaled with the character, since the inset it compensates for
scales too.
Her own session over the app's one search — see `ClaudeCodeDetector`.
Hers, keyed by profile like every other per-character file. Built
here rather than defaulted in `Secretary`, whose default reaches
nowhere on purpose — a suite that forgot to override it would
otherwise be granting permissions in the person's own name.
Hers, and keyed by profile like everything else of hers. Built
here rather than defaulted in `Secretary` for the same reason as
the grant store: a suite that forgot to override it would write
into the person's own preferences.
After the secretary, because it reads and writes her chosen model:
one that belongs to the maker she just left has to be dropped.

Hers, keyed by profile like the model and effort beside it — two
characters on one desktop may reasonably run through different
makers, one on the Claude Code subscription and one on a local model.
MARK: - Windows

Kept so it can be taken off again. Left on, an observer for a window
that has gone still fires — which did not matter while there was one
character for the life of the process and does the moment characters can
be deleted.
Builds both windows and puts them where they go. Separate from `init`
because it reaches for the screen, and because the callbacks it installs
point back at whoever owns this instance.

- Parameter ordinal: how many characters were already on the desktop, so
  she stands clear of them rather than exactly on top.
Ask the view how big it wants to be at 1×, then give it exactly that
times the S/M/L factor, so nothing is cropped.
Wrapped in a plain container rather than used as the content view
directly: an NSHostingView publishes its SwiftUI layout size as an
intrinsic size, and Auto Layout then shrinks the window back to it.
`scaleEffect` doesn't change that layout size, so at L the character
was drawn 1.3x inside a 1x window and clipped on every side.
The chat is where the keyboard belongs once you click into it —
typing, Esc, the arrow keys and ⌘H all read as "to the chat".
The character isn't: clicking it opens or closes this panel, and
taking the keyboard from the app behind to do that would be rude.
A reply can ask for part of itself to be kept on screen.
Takes her off the desktop for good. Both windows, her pinned panes, and
the observer that would otherwise outlive them.
Her Claude Code process outlives the turn now, so it has to be ended
deliberately — nothing else will. A deleted character that left one
running would be an invisible process nobody could account for.
Lets the window own its size and the hosted view fill it.
Where she was left last time, if that spot still exists — a save
from a display that is gone falls back to the launch position, per
`savedCharacterOrigin`'s rule (20.1).
Delivered on the main queue, so it's safe to assert main-actor
isolation to reach the panel and layout without a warning.
Every move is remembered, the same way the command window's
is — the restore's staleness rule lives in
`savedCharacterOrigin`, not here.
Repositions the bubble relative to the character's current frame.
The decision itself is `placeBubble`, which can be checked without a
screen; this only feeds it the current frames and applies the answer.
Resizes both windows to the current choices and re-anchors the bubble,
keeping the tail on the character and the whole panel on screen.

The character grows from its bottom-centre: it usually sits near the Dock
with the bubble above it, and growing from the top-left corner instead
would walk it across the desktop each time the size changed.
Only a character that just changed size can have been pushed off
an edge by this call. Resizing the chat used to run this too, and
a character standing where the user put it — at the bottom of the
screen, over the Dock — was yanked 54pt upward the moment the
grip moved. Resizing the bubble must resize the bubble and
nothing else.
A character that just grew near an edge would otherwise hang off it.

Measured against the whole screen rather than the part left over by the
Dock and menu bar: standing on top of the Dock is a normal place to put
a desktop character, and having it shoved out of there for growing one
size is the same complaint as being shoved for a resize. The rule is
only "don't end up off the screen".
The NSWindow shadow follows the glass setting: on for the solid bubble,
off for glass. Sprint 21's backlog warned about exactly this ("glass's
shadow stacking with the NSWindow's") and the owner saw it on a real
desktop (2026-08-20): with glass on, a dark blot hung behind the chat
window — the window shadow, now cast for a mostly-transparent shape and
showing *through* the glass it used to hide behind. Screen captures
never show it, because `screencapture` records the window's own layer
without the system-drawn shadow; only eyes on the desktop catch it.
`invalidateShadow` because AppKit caches the shadow's shape and does not
recompute it just because the flag flipped.
Tells AppKit which way this character's windows are lit.

A window property, not something a SwiftUI body can return, and it has
to be re-applied rather than set once: without it the caret, the
scroller and the text-selection tint keep coming from the system's
light/dark setting — a white scroll bar down the side of a dark panel
the moment the theme is overridden.
The same, from her own theme. Her windows are lit by her settings now,
so nobody outside has to know which they are.
MARK: - Visibility

Anything Esc would put away for this character. The rule is
`hasSomethingToDismiss`, in `SecretaryCore` where it has tests and where
the bug it was written for is recorded.
Whether one of her windows is the one being typed in. What makes Esc
hers rather than another character's.
Puts the character on screen. Safe when she is already showing.
Takes the character off the desktop, along with her chat. Safe when she
is already hidden, which is what makes it usable from ⌘H — a toggle
applied to everyone brings back whoever was already away.
Everything of hers, off the screen: her pinned panes as well as the
bubble and the character. What ⌘H means by "the whole app".
Shows or hides the floating character. Returns the new visibility so the
menu can relabel its item. Hiding the character also hides the chat.
Opens the chat, making the character visible first if it was hidden so the
bubble has something to anchor to.
Opening her chat is the clearest statement of which character the
person is working with, and the app-wide windows have to borrow one
character's look from somewhere.
The display may have changed since launch; re-clamp before showing,
against the screen the character is on rather than whichever one
happens to be "main" at the time.
Clicking the character is someone starting to say something. Landing
in the box means they can just type; without it the bubble opened with
the caret nowhere and the first keystroke went into the void.
Esc closes the chat; Esc again puts her away. Only the local monitor
can carry that second press, and it needs one of our windows to hold
the keyboard — closing the chat dropped it entirely, so the second
press reached nothing. Driven in the running app: two presses, chat
gone, character still there.

This hands over a keyboard we already had; it never takes one. That
is why the character panel still refuses key status on a click, where
taking it would mean taking it from the app behind.
Esc goes back to whichever app the user is actually in the moment
there is nothing left to put away.
Esc: a pinned pane in front is what it puts away; otherwise the chat.

Three rungs, not two. The middle one is for the press that arrives from
the system-wide claim while the person is typing in another app: a pane of
hers is on screen, none of her windows holds the keyboard, and the chat is
already shut — so without it the key was swallowed and spent on nothing.


## CharacterView.swift

Falls back to the built-in placeholder avatar when the user has placed no
picture of her own — see `CharacterAsset`. The badge and tap-to-open behave
the same either way.
Whose face this is. Every character on the desktop draws her own, so the
picture is looked up by id rather than by "whichever profile is active".
S/M/L is a whole-character zoom rather than a re-layout: the badge, the
halo, and the bubble's tail are all positioned against each other, so
scaling the finished view keeps them in the same relationship.

`fixedSize` makes it take its own ideal size rather than whatever the
window offers. The window is then sized from that ideal (see
`AppDelegate.characterSize`): sized the other way round, a window even a
few points too small clipped the halo into a flat edge across the top of
the character's head.
Centred, so the character sits in the middle of its halo whatever
shape the picture is. The badge is an overlay rather than a third
layer in here: aligning the stack to the corner for the badge's
sake pushed the character over with it, by however much narrower
than the halo it happened to be.
The status badge doubles as the switch for the running
commentary: it already shows what the assistant is doing, so
it's the natural place to ask for more or less of it.
Who this is, and what they're doing when that's anything. It read
"IDLE" almost always, which named a state nobody was waiting on
and never said whose desktop companion it was.
The ring the character stands in, which is also where "she is thinking"
is said loudest — it is the largest thing on the desktop that can change
colour, and the owner asked for the blink to be the whole frame rather
than the badge alone.

Grey at rest, the state's colour at full stretch, on the same clock as
the badge. Same clock, not a shared flag: both read `pulseProgress` from
the current time, so they cannot drift apart however long they run.

The halo does not scale. It is the frame the character sits in, and a
frame that changes size drags the character's edges with it.

Deliberately its own `TimelineView`, wrapping only this circle: the one
above it would rebuild `characterArt` thirty times a second, and that
reads the picture off disk.
This character's picture, falling back to the legacy drop-in file and
then to the built-in avatar. A profile with no picture at all is normal,
so the last fallback has to hold up on its own.
Read the revision so an upload or a profile switch invalidates this.
A user-supplied character image, loaded from outside the git repo so
licensed/copyrighted art never gets committed or distributed with the
project. Drop a PNG at this path to override the built-in placeholder;
remove it to fall back automatically.


## ChatBubbleLayout.swift

Tracks which side/orientation the chat bubble's tail should be on.
Updated by `AppDelegate` whenever the character (and therefore the
bubble) is repositioned, so the bubble can flip horizontally and/or
vertically to stay on-screen while the tail keeps pointing naturally at
the character.
Bumped each time the bubble is shown, so the message box can take the
caret.

A count rather than a flag, and a count rather than `onAppear`: the view
is built once and then hidden and shown by changing the window's alpha,
so `onAppear` fires at launch and never again, and a `Bool` set true a
second time is not a change SwiftUI will act on. Showing the bubble twice
has to read as two separate events.
Reports where the end of the transcript sits, in global coordinates, so the
panel can tell whether the reader is at the bottom. macOS 14 has no
scroll-position API; this is the way to measure it.

Global, not the scroll view's own named coordinate space. The named version
was delivered exactly once, at launch — never on a token of a reply, never
on a turn of the wheel — which is how a scroll pin that read correctly could
never have worked.


## ChatPanelView+Composer.swift

The composer: the growing message box, the attachments riding with it, the
file-request card and the ↵ that sends.
Asked for: the message box grows to ten lines and then scrolls. Past
that it starts eating the conversation it is replying to.

Was five, and raised on request (2026-08-17) now that a line break lands
where the caret is — writing a message of several paragraphs in the box
became a thing people actually do.
The box spans the full width, with the send affordance inside it rather
than a button beside it.
Where a dragged file is going, shown only while one is over the window.

Above the box rather than as an outline around it. The whole window
takes the drop — see `ChatPanelView.body` — and a border drawn around
the composer said the opposite of that: it named one rectangle as the
place to aim for, which is the belief this change exists to undo.

Never hit-tests. It sits inside the region it advertises, and a view
that took the pointer here would make "anywhere" untrue at exactly the
spot that promises it.
The chips live *in* the field rather than above it because that is what
they are — part of the message being written, not a separate thing that
happens to be nearby. Sending takes both, and the box that Return
belongs to should look like it holds both.
The field is left to grow to its full height and a `ScrollView` is what's
capped, rather than capping the field with `lineLimit`. Both look the same
until you reach for the wheel: a line-limited field scrolls only to follow
the caret, and a wheel over it does nothing at all.
The persona's own name, not "the Secretary": the app can be
several people and the box should ask for whoever is listening.
Return sends. `onSubmit` doesn't fire for a vertical field in
this panel — Return quietly drops first responder instead —
which would leave no way to send from the keyboard.
Shift/Option-Return is left alone so it still breaks the line.
The lane the ↵ sits in. Taken out of the field's own width so
the text wraps before it rather than running underneath —
an overlay alone would have let a long line slide behind it.
Nothing to scroll until it has outgrown the box; without this the
content drifts under a trackpad's rubber-banding while still short.
Keeps the newest line in view as the message grows, which is where the
caret is while typing.
Shift/Option-Return breaks the line **where the caret is**.

It used to be `draft.append("\n")`, which put every break at the end of
the message: editing a sentence in the middle and pressing Shift+Return
moved the break to the bottom and left the sentence intact. Reported
2026-08-17.

Done through the field editor rather than by splicing the binding.
`NSTextView` already knows where the caret is, and it is the only thing
here that gets it right for Thai and for emoji: `selectedRange` is in
UTF-16 units, and an index built from one by hand can land inside a
grapheme cluster and cut a character in half.

`insertNewlineIgnoringFieldEditor` rather than `insertNewline`, which
would end editing — the same reason Return has to be caught at all.

Appending is kept as the fallback for the case where the field editor
cannot be found. It is the old bug, but a break in the wrong place beats
a key that does nothing.
The field editor behind the message box.

**Not `NSApp.keyWindow`.** This panel is non-activating, so the app is
usually not the active one and `keyWindow` is nil even while the box has
the caret and is taking keystrokes — driven on 2026-08-17, where the
fallback ran every time and gave itself away by resetting the caret to
the start of the message, which is what writing to the binding does.

Editable, because the panes pinned out of the conversation are
`NSTextView`s too and any of them can be a window's last first
responder; only the message box can be typed into.
One line of the message font, measured rather than guessed — a fraction
of the point size is wrong by a whole line at the larger text sizes.
The files waiting to go with the next message, each with a way off the
list. Attached and invisible is the state that gets a file sent twice.
Scrolls sideways rather than widening the box. Five files with long
names are wider than any chat panel, and a row that can push the box
out is a row that decides the window's width — the same mistake the
panels were structurally stopped from making.
Says what kind of thing was attached at a glance, which is the one
question a row of names can't answer.
The assistant asking for a file.

A card rather than a line of buttons, and its own colour: this is a
question waiting on the person, which is what the approval card is too —
but nothing here acts on their behalf, so it must not wear the colour
that means "something is about to happen as you". Teal against the
orange and red of the cards that do.

A button, not a path: nobody knows where their spreadsheet is in a path,
and the panel is also the only way a sandboxed build could ever open one.
Files she has just made, offered for keeping.

The mirror of `fileRequestCard` and deliberately the same colour: this
is the other half of the same conversation — a file crossing between the
two of them — and nothing here acts on the person's behalf either. The
save panel is what acts, and only after they have said where.

The size is on the row because it is the one fact that tells an empty
file from a real one before saving it, and "0 bytes" has been the whole
story of a failed export more than once.
The ↵'s point size, relative to the message text. Was 1.1 — 10% smaller
now that it is drawn at full strength and no longer needs the size to be
noticed.
How much room the ↵ needs, glyph plus breathing space on either side.
Derived from the glyph's own size rather than repeating the arithmetic:
a lane that stopped matching the glyph would let a long line slide back
under it.
Return, drawn rather than boxed: the keyboard is how this is sent, so the
affordance says which key rather than offering a second, different thing
to press. Still clickable for anyone who reaches for the mouse.

Bottom-aligned, because the box grows downward as the message wraps and a
centred glyph would drift away from the caret.
Empty box: exactly the placeholder's colour, so the glyph sits at the
same weight as the "Ask the Secretary…" beside it. It used to be
dimmed to 35% of that and read as switched off.
`placeholderTextColor` and `secondaryLabelColor` are the same value
(black/white at 0.5 alpha) — naming the placeholder one says which
of the two this is matched to.
A file on its own is a message. Dragging a spreadsheet in and pressing
Return should send it, not sit there waiting for a word to be typed.
Carries the typed message's rendered height out of the field so the box can
be sized from it.


## ChatPanelView+Header.swift

The header row: who is speaking, what state she is in, and the badges for
everything standing that can speak on its own — each with its own off
switch, because a turn arriving with nobody typing must have a visible
cause.
What the assistant is doing right now.

Note this is activity, not reasoning: Claude Code returns thinking
blocks with no text (the raw chain of thought isn't exposed on this
model family), so there is nothing to render for the thought itself.
Which tool it reached for, and with what, is the part that exists.
Which model is answering, beside the name that answers. Two
characters on one desktop can be on different models and efforts,
and until now the only way to tell was to open Settings for each.

Lowest layout priority in the row: the badge is the one thing
here that may be truncated, because everything else is either the
name or a control with an off switch on it.
Two Texts rather than the whole label from `characterStatusLabel`,
so the name keeps its weight and the state stays secondary — but
the same rule decides whether there is a state to show at all.
A top corner is taken by the widen/restore/close row, and can be taken
by the resize grip as well, so the title drops below them rather than
being inset past them. Inset was the first attempt and it moved the name
around as the bubble mirrored; the title now stays flush left at every
size, on either side, and whichever corner the grip is in.
What the standing badges sit on. Accent-tinted normally; neutral in
glass mode, where colour is reserved for content and state is not a
thing the chrome shouts (Liquid Glass rule #7 — the same swap
`PanelToggleStyle` makes for the open footer button).
What the sub-agent working on her behalf is doing, and whether it is
still answering.

Read-only, unlike its neighbours: there is no button because there is
nothing safe to press. Stopping the sub-agent alone is not something the
CLI offers — Stop ends the whole turn, and that button is already here.

`TimelineView` rather than a stored timer: the text has to age even when
nothing arrives, since silence is precisely what it reports, and a badge
that only redraws on the next event would freeze at "running" for exactly
the case it exists to show. Five seconds is finer than the 30s threshold
it has to cross, and it re-evaluates a Text rather than animating.
Truncates before anything with an off switch on it, the same rule
the model badge follows: this is the longest thing in the row and
the only one that is pure information.
Shows that the Secretary is on a timer, and stops it in one click.

Something that speaks without being spoken to has to be visible while it
is armed, not only in the message that announced it — that message
scrolls away, and then an answer arriving on its own has no explanation
anywhere on screen.
Shows that a file's steps are being worked through, and stops them in
one click. Same reasoning as `loopBadge`: turns that keep arriving
without anyone typing must have a visible cause and a visible off
switch, not just the message that announced them three screens ago.
Shows that a path is being watched, and stops it in one click. Third of
the three standing things that speak on their own; all three sit in the
header for the same reason.
Stops what is running. Only there while something is.

The running turn is one invocation of the CLI, so this is the only
interruption that exists for it — there is nothing to pause and resume.
Pausing belongs to the queue, on the badge beside this.
What is waiting, and whether it is being held.
Paused keeps `warningFill` in glass mode too — "held" is a
meaning, not chrome decoration, so #7 does not neutralise it.
Holding something for ever is not the same as changing your mind
about it. Without this, a message queued by mistake could only be
paused, never dropped.
The number only appears when there is more than one:
a "1" beside the eye reads as a badge count of unread
things rather than as how many are being watched.
Enough to clear the control row above, whose lowest point is ~29pt below
the bubble's top edge (10pt of padding plus an 18pt close button). The
title's own top already sits 18pt in, so this is the remainder — plus
breathing room, because merely not overlapping still read as crowded.


## ChatPanelView+Keys.swift

The keyboard's second meanings: the choice picker, history recall, and the
event monitors that see keys and wheels before the responder chain does —
which is the only reliable point, as the doc comments below record.
What you've sent this session, oldest first.

Read back out of the transcript rather than kept in a second list: the
transcript already is the record, and a copy of it would be one more
thing to keep in step. It also means recall covers exactly one session,
which is what was asked for.
Whether the arrows should act as history rather than move the caret.
The options the assistant is waiting on, if its latest message asked
something. Only the latest: an older question has been overtaken.
The question's answers, as a list you can walk with the arrow keys and
take with Return — or simply click, since a keyboard-only control in a
window you reach with the mouse would be a trap.
The caret marks the highlight for anyone who
can't tell the tint apart from the background.
Says who the arrows currently belong to, because a key that
silently means two things is the part people get wrong.
A new question replaces the old options in place, without the
list ever leaving the screen, so `onAppear` doesn't fire again.
Answering sends the option's own words, not "A" or "the second one":
the model reads it as an ordinary reply, and the transcript records what
was actually chosen.
Catches Up and Down before the text field turns them into caret
movement.

`.onKeyPress` was the obvious way and does not work here: Return
arrives, the arrows never do, because the field consumes them as
`moveUp:`/`moveDown:` first. Verified in the running app — the handler
was in place and the box stayed empty. A local event monitor sees the
key before the responder chain does, which is the only reliable point.
Escape is deliberately not handled here. It used to be, because
`.onExitCommand` never fired on this non-activating panel — but
this view is built once and never torn down, so the monitor
outlived the panel it was closing and swallowed Esc for the whole
app whether the chat was showing or not. Esc now has a single
owner in `AppDelegate`, over one ladder in `dismissDecision`,
because it means three different things depending on what is on
screen and a key that means three things needs one place to say
which.

126 is Up, 125 is Down. Which feature they belong to is decided
in one place — see `ArrowKeyOwner` — so the picker, history
recall and caret movement can never each take a turn at the same
keystroke.
Clamped at use: a second question can arrive while the list
is still up, and a highlight left pointing past a shorter
list would trap on Return.
Recall stays tied to the caret being in the box: it edits
what you are typing, so it needs you to be typing.
Notices the reader scrolling back through the conversation, so a reply
still arriving stops chasing them down the page.

From the event rather than from the scroll position, because a position
cannot say who moved it: the content growing under a reader who hasn't
touched anything looks exactly like the reader scrolling up. The event
only exists when they did it. Never consumed — it is passed straight
through and the view scrolls as usual.
Steps back towards older messages. Returns whether it took the key.
Already at the oldest. Take the key anyway, so it stops here
rather than jumping the caret somewhere unexpected.
Steps forward towards what you were typing.
A sent message ends the walk: the next Up starts again from the end,
the way a shell behaves.


## ChatPanelView+Panels.swift

The collapsible configuration sections and the footer that opens them:
Settings, Projects (with the browser switch), Skills, and the height cap
that makes the panel structurally incapable of overflowing.
Built from `ThemeChoice.allCases`, so adding a theme adds a button
without this row being touched.
A checkbox rather than a fourth theme button: glass is a surface the
bubble is drawn as, and it composes with all three theme choices — the
palette still decides every colour, glass only replaces the ground it
sits on. A fourth button would have made "Dark + glass" unsayable.
Built from `FontChoice.allCases`, the same way the theme row is.

Sits above Text size because the two are read together and the face is
the coarser choice of the pair: which font, then how big.
It was called "App size" while there was one character and every setting
was the app's. It only ever scaled the character, and now that each has
her own it scales exactly one of them, so the old name described neither
what it does nor who it does it to. (It sat in Profile before that,
which was wrong for the opposite reason: with one character at a time,
switching secretary would have resized the app under you.)
Shared by Theme and App size because they are the same row, and because
they sit next to each other: App size used to mark its current value by
disabling that button, so two adjacent rows said "this is the one you're
on" in two different ways, one of them indistinguishable from "you can't
have this".
Drawn here rather than left to the bordered style's own
tint, for the reason in `PanelToggleStyle`: this window is
never key, and AppKit greys out a tinted control in a
window that isn't.
See `PanelToggleStyle`: a bordered button's label follows
the tint, not the foreground style.
A button that can't do anything is disabled rather than silently
ignored, so reaching a limit reads as a limit.
Taking a project away is the same event as adding
one, and the half that matters more: the running
session keeps the working directory it was given
until something re-scopes it, so without this the
assistant goes on working in a folder that is no
longer approved.
Adding a project mid-conversation is almost always a
correction to the question already asked, so the Secretary
re-scopes the workspace and runs it again.
Under Projects rather than Settings: the browser is somewhere the
assistant is allowed to read, which is the same kind of thing as
a project folder. Settings is what the app looks like.
Two lines rather than one truncated one: the sentence about
reading signed-in sites is the part a person needs before they
switch this on, and "…" is where it was being cut.
A menu rather than a toggle switch, so this is a deliberate pick from a
list and not a switch brushed by accident.
Outside the menu on purpose. A menu label built from several
views renders as the chevron alone here, and the one thing this
row has to say is whether the browser is connected. Model and
Effort, over in Profile, are drawn the same way for the same
reason — see `settingControl` there.
Checkboxes rather than a menu: unlike Model/Effort, this is a
multi-select, and a `Menu` closes after every tap — wrong for checking
several boxes in one visit.
Says what checking does now, which is the opposite of what it used
to do: it asks for these to be preferred rather than shutting the
others off. The old wording promised a limit, which was both
unenforceable and not the thing anyone wanted from a checkbox.
Held to a share of the window and given its own scroll, which is what
makes the panel structurally incapable of overflowing.
The
surrounding `VStack` has exactly one flexible child — the transcript —
and once that has shrunk to nothing, any further content simply spills
past the bubble: the header goes off the top, the buttons off the
bottom. Adding a row used to be enough to cross that line, so the fix
cannot be a re-tuned constant. A section that can never be taller than
its share, and scrolls when it wants to be, can never cross it at all.

The share is a fraction of the real window height rather than "window
minus the header, input and footer": those three grow with the text
size, so any subtraction of them is a constant that goes stale the next
time ⌘+ is pressed.
A ScrollView takes every point it is offered, so a short panel —
Projects with nothing registered, Settings at a small text size —
claimed the whole allowance and left dead space between the box
and the buttons. Asking for the content's own height first, then
capping, makes the panel as tall as it needs and no taller, and
it still scrolls once the content passes the cap.
Leaves the rest of the window — header, transcript, input row and the
section buttons — the larger share at every text size.
The strip along the bottom of the window that belongs to the resize
grip, on the placements where the grip is down here at all.

The grip is 9pt of glyph inside 10pt of padding, and that padding is its
hit area, not just air: it reaches about 30pt up from the bottom edge.
The window's own 18pt sits under the row already, so this is the rest of
what holds the row above it — and the margin is only a few points, which
is why it is written down. Shrink either number and the corner of
Projects lands inside the grip, where a click resizes the window instead
of opening the pane and no screenshot shows it. Both bottom corners were
checked by clicking the outermost pixel of the button in them.
The section toggles grow with the text size like everything else in the
panel: left at a fixed caption size they became unreadable specks next to
32pt replies. `controlSize` follows suit, or the button's own padding
stays mini around text that isn't.
The one row in the window that doesn't follow the bubble: these
four stay put so they can be aimed at without looking.
Still a toggle each, and clicking the open one still
closes it — opening one closes whichever was open.
Both ends of this row hold a button, so the grip can't be dodged
sideways — it is given the strip underneath instead. Projects stays
against the left edge and Settings against the right, which is the
row as drawn; indenting whichever end the grip was in moved a button
every time the bubble flipped.

Only when the grip is actually down here: with it at a top corner the
strip would be a gap under the row holding nothing.
Not `.toggleStyle(.button)`: an accent-tinted control loses its colour
whenever the window isn't key, and this window is never key. See
`PanelToggleStyle`, which keeps the bordered metrics and changes only
how "this one is open" is drawn.


## ChatPanelView+Transcript.swift

The thread itself: the scroller and its follow-the-bottom rule, and how one
message becomes bubbles, tables, code blocks and activity lines.
The outer reader is only here for one number: where the bottom edge
of the visible area is, to compare the end of the content against.
Eager, and it has to stay eager. `LazyVStack` was tried here
— it would let the strip at the end report its own visibility
and it builds far less per token — and it puts the scroll bar
in the wrong place: parked at the very bottom of a reply, the
thumb sat half way down its track, because the height of a
list whose rows haven't been built is a guess.

Spacing wider than the gap between boxes of one turn, so the
eye groups a split answer together before it groups the
conversation.
Wrapped so a keystroke in the message box does not
rebuild every message in the conversation — see
`TranscriptRows`, which is where the measurement is.
Breathing room under the last line, and the thing that
reports whether the reader is at the bottom.

The room came first: scrolled to the bottom, the final
line sat flush against the edge and read as cut off — and
with a descender or a second line arriving mid-stream it
genuinely was. Scaled to the text size, because the amount
that goes missing scales with it too.

Where this strip is relative to the bottom edge is the
only input following has: it says both "the bottom is on
screen" — which is the only thing that may switch
following back on — and "the end has been pushed out of
sight", which is what asks for a scroll. What it must
never be read as is the reader scrolling away, since
content growing under a reader who hasn't moved looks
identical from here. Leaving is the scroll wheel's
business alone, in `startWatchingScroll`.
How far the end of the transcript sits below the bottom edge.

Measured in `.global` deliberately. The first version of this
asked for the content's frame in a *named* coordinate space on
the scroll view, and that preference was delivered exactly once,
at launch — not on a single token of a reply, not on a single
turn of the wheel. It read correctly and never ran; the same
reading in global coordinates fires throughout.
Assigned only when the answer changes: writing to `@State`
invalidates the view whether or not the value differs, and
this arrives on every token.
The one place following is decided, and it is decided from
where the end of the content actually is rather than from a
guess about what might have moved it. Scrolling changes this
measurement, which arrives here again — and converges, since
the end sitting at the bottom edge is `settled` and asks for
nothing further.

Unanimated: an animated scroll is still moving when the next
token arrives and asks for another one, and the two fight
each other into a visible judder.
A conversation only ever gets shorter by being replaced — started
again, or an older one loaded — and that is the moment the parses
of messages that are no longer on screen stop being worth
keeping. Pruning here rather than per message keeps the walk off
the token-by-token path.
The strip below the last message: what following scrolls to, and what
being at the bottom is measured against.

Scrolled to, rather than to the last message: the last message's bottom
is a line of text short of the end, which left the breathing room under
it permanently off screen and made "am I at the bottom?" a question
about a strip nobody could see.
Markers stripped, and pasted rows recognised as tables — someone
handing over data has it as CSV far more often than as pipes, and
a wall of commas is exactly what they can't check before it is
typed into a form.

Through the cache because this runs for every message in the
conversation on every token of the one still arriving.
Boxes within one turn sit closer together than turns do, but not
as close as they were: three boxes 5pt apart read as one striped
block rather than as three things.
Both speakers are named above their boxes, not inside them:
the name is about the turn, and a reply split into three
boxes has one speaker, not three. Each header sits against
its own speaker's edge, so they mirror.
One box, with its own copy button in the top-right corner.

Per box rather than per turn: a reply that split into prose, a table and
a command is three things you might want separately, and the command on
its own is the one you actually paste.
Its own message, with no bubble around it: a table and a
fenced block each already have a border, a fill and their own
sideways scroll, and a bubble around that is a second frame
that says nothing.
The `hover ==` test lives inside this leaf, deliberately —
see `hover`. Building the buttons is also deferred into it,
so a box nobody is pointing at costs a closure and no views.
Straddling the corner rather than sitting inside it:
over the text, the button hid the end of the first
line — and the one thing a copy button must not do is
cover the words you are deciding whether to copy. The
room it moves into is the gutter, which is empty by
construction.
Hover, not always: a button on every box at rest is three buttons in
a three-box answer, and none of them are what you came to read.
Which box the pointer is over. One value, not a flag per box: the pointer
is only ever in one place, and a flag each is a set of them that can all
be true at once after a fast drag.
One line of the thread, tucked against this speaker's edge.

The gutter is a minimum, not a fixed width: a short message keeps its
bubble small and a long one grows into the rest of the row, which is what
makes the thread read as a conversation rather than as two columns.
`secondaryFontSize`: the header is there to be found, not read, and at
message size it competes with the message.
Named as the app's own failure, not as something the persona
said. A warning in the persona's voice reads as the character
being unhelpful rather than as the tool being unreachable.
One hover target for both, so moving between them can't make the pair
flicker, and so the pointer leaving either one is the same event.
Pulls this box out into its own floating window, which then survives the
chat being closed and the conversation moving on.

The title is the speaker and the time, which is what tells two pinned
panes apart in the menu — the body is already visible in the window.
It sits over the corner of the box, so it is given the panel's own
background behind it — over a line of text with no backing, an icon is
unreadable and looks like a rendering fault.
A tick in place of the icon is fine *here*, unlike in the header:
the button only exists while the pointer is on the box, so it
can't be left looking as though it went away.
Shows the tick, then takes it away again. Held only briefly: it says
"that press worked", and a tick still sitting there ten minutes later
says something else.
The fill is the panel's own accent and secondary, not a new palette —
the point of the change is the shape of the conversation, not a different
look.
AppKit-backed: SwiftUI's Text draws links but doesn't
open them from a non-activating panel, and can't show
a pointer or a hover underline over them.
Capped at the width the text would take unwrapped, so
a short message keeps a short bubble. Without the cap
every bubble — "ok?" included — is as wide as the row
allows, and the two sides read as columns rather than
as a conversation. A long message asks for more than
the row has and simply gets the row.
How far a bubble's text sits in from the bubble's edge — and, because a
bubble starts at the edge of the thread, how far in from the thread the
Secretary's words begin. The activity line is indented by the same amount
so the two start in one column.
Yours is tinted with the accent, the Secretary's with the same neutral
the rest of the panel uses. Both are faint: the text has to stay the
loudest thing in the bubble.
Monospaced and scrolled sideways rather than wrapped: wrapping a line of
JSON or a shell command puts a break where none exists, and the reader
can no longer tell what would actually be typed. Same treatment as a
wide table — the block scrolls, the conversation doesn't.
Plain text, not `inlineMarkdown`: inside a code block an
asterisk is an asterisk, and a backtick is a backtick.
Cells use the body text size, not a smaller caption: a table is content,
so it has to grow with +/- like the rest of the answer. Only the table
scrolls sideways — the conversation itself must not, or every wide answer
would drag the whole thread off screen.
Cells size to their content; the scroll view provides the room.
Cells routinely contain `**bold**`, `` `code` `` and links. Shared with
the message body so a URL is clickable wherever it appears.
No box, no border, no fill — it still has to read as the app talking
about itself rather than as part
of an answer, and now that is carried by the type alone: dimmer, smaller,
with the "Working" label above it. A box did the same job louder, and
stacked a frame inside a thread that is already made of frames.

Left-aligned, and started at exactly the column the Secretary's words
start at — the bubble's own horizontal padding, shared as a constant so
the two can't drift a point apart and leave the thread looking ragged.

Everything about the conversation's *appearance* that is not carried by the
entries themselves.

Its whole job is to be compared. Anything that changes how a message is
drawn, and is not part of `TranscriptEntry`, has to be a field here or the
transcript will keep the look it last drew until the next message arrives.
The messages, rebuilt only when the messages or their look have changed.

**This is a performance fix with a measurement behind it** (2026-08-20, the
owner: "เวลาพิมพ์ใน text ของ chat window มันหน่วงๆ"). `draft` is `@State` on
`ChatPanelView`, so every keystroke re-evaluates that view's whole body —
and the body holds this list, eagerly, one view per message. Sampling the
app while typing put 1130 of ~1910 layout samples under
`ForEachChild.updateValue()`, laying the conversation out again from the
top: CoreText, `liblangid`, and `libThaiTokenizer` re-tokenising every Thai
message in the thread. It gets worse the longer the conversation, which is
exactly how it feels.

`.equatable()` is what stops it: when the parent re-renders and nothing here
has changed, the rows are left exactly as they are.

**What this does not put at risk.** An `@Observable` read *inside* a row
still invalidates that row directly — being skipped from above is not the
same as being detached — which is why hovering still works: `hover` is a
`BoxHover` object read only in the `WhenPointingAt` leaves. What would go
stale is a plain `@State` of the parent read inside a message; there is
none, and `partsCache` is keyed by the entry's id and text, both of which
are in `entries`.
The closure is deliberately not compared — it is rebuilt on every parent
render and would never be equal, which would defeat the whole thing. It
reads nothing that `entries` and `look` do not already carry.


## ChatPanelView.swift

The conversation panel, rendered as a manga-style speech bubble anchored to
the character. Shows the transcript, the input field, whatever decision the
Secretary is waiting on, and collapsible Settings/Profile/Projects sections.
Which maker this character works through. Only the Profile panel reads
it; it is carried here because that panel is mounted from this one.
Which character's window this is. Passed to the Profile panel, which
edits her and nobody else.
Pins one box into its own floating window. The same door the ```window
marker goes through, so a pane the user pins by hand behaves exactly
like one the assistant asked to pin.
The colours in force. Every colour in this file comes from a role on
this palette; there are no literals left, because a literal here cannot
be checked — `AISecretaryApp` is not linked into the test bundle.
One selection rather than three independent flags, because three
independent flags allow all three sections open at once — which is how
the panel came to be taller than the window it lives in, pushing the
transcript off the top and the Save button off the bottom. The state
simply isn't representable now.
The row's order lives in `FooterButton`, which knows nothing about
this view's state; this is the one place the two meet.
How tall the message being typed actually is, reported by the field
itself. The box is sized from this and capped at five lines.
How far back through sent messages the box is currently showing.
`nil` means it's showing what you were actually typing.
What you were typing before you started looking back, so walking
forward past the newest message returns it rather than losing it.
Watches for the arrow keys before the text field sees them.
Watches for the reader scrolling the transcript themselves.
How each message was last broken into boxes. A reference type on
purpose: it is a memo of a pure function, not state the view renders,
and writing to it must not invalidate anything.
Whether the pointer is over the transcript. A local monitor sees every
scroll in the app — the history window, the settings panel, a pinned
message — and only the ones aimed at the transcript say anything about
where the reader wants the transcript to be.
Which option is highlighted in the choice list, when one is showing.
Which box the pointer is over and which was last copied.

An object rather than two `@State` values, and this is a performance
decision with a rule attached: **nothing in `ChatPanelView.body` may
read `hover.pointingAt` or `hover.copied`.** Reading an `@Observable`
property is what subscribes a view to it, so a single read here puts the
whole transcript back on the hot path — and the symptom is invisible
until someone scrolls a long thread.

When they were `@State`, every box passing under the pointer during a
scroll rebuilt the entire panel: 19 rebuilds over a 120-tick scroll,
each one re-measuring all 60 messages through TextKit at ~0.2ms each.
That is the stutter. The reads now happen only inside `WhenPointingAt`,
which is a leaf, so a hover change repaints two buttons and nothing else.
Whether a file is being dragged over the composer, so there is an
outline to let go inside rather than a guess.
The default for anything that doesn't name a colour, so a `Text` added
later inherits the palette instead of the system label colour — which
is decided by the system's light/dark setting, not by ours, and would
be black text on a dark panel the moment the theme is overridden.
Not `onAppear`: this view is built once and then shown and hidden by
the window's alpha, so appearing happens exactly one time.

Only into an empty box. Taking focus selects whatever is already
there, so re-opening on a half-written message armed the next
keystroke to wipe it — the box is where their words live, and this
was meant to save a click, not cost a sentence.
The whole bubble takes the file, not the composer alone. A drop two
points outside a small target is a file the person believes they
handed over, and the composer is a strip at the bottom of a window
that is mostly conversation. Attached after the background so the
filled shape is the region, rather than only where content happens
to be; `dropArea` in the composer is what says so on screen.
Glass draws its own rim; a painted border on top of it reads as
a sticker stuck to the pane, so the stroke is solid-mode only.
The button row stays on the tail's side of the top edge; the grip goes
to the corner the bubble actually grows out of, which is not always a
top corner. Both follow the bubble as it mirrors and flips, and they
can never land in the same place.

Attached inside the body rather than to the outer frame: the outer
frame includes the strip reserved for the tail, and anything aligned
to the bottom of it would sit in the tail, outside the bubble.
The bubble's ground: Liquid Glass when the user has switched it on,
otherwise the palette's solid ground. Glass here is safe on this
never-key panel — checked by eye on 2026-08-20, frontmost and not,
before the sprint was allowed to start: unlike the accent tint that
`PanelToggleStyle` exists to work around, `glassEffect` does not go
dead when the window isn't key.

Content drawn on top keeps its solid palette fills either way — glass
is only ever the chrome underneath, never a wash over text.
Not decoration — this is what makes the bubble clickable.
A borderless window lets clicks fall through wherever its
pixels are fully transparent, and `Color.clear` under a
`glassEffect` IS transparent to that test even though the
eye sees frosted glass: with glass on, the resize grip and
every empty stretch of the bubble went dead (drag measured
2026-08-20 — five steps, window never moved). The faint
ground fill puts real pixels under the whole shape; 0.15 is
comfortably above the window server's ~5% click-through
threshold and invisible under the frosting. Do not "clean
this up" into Color.clear again.
Widen, restore, close — reversed when the row moves to the other corner,
so close stays on the outside and the two width buttons stay next to the
middle of the bubble. The width buttons are drawn smaller than the close
button (closing is the one people reach for) and are disabled rather than
hidden when they'd do nothing, so the row never changes shape and a greyed
button reads as "already there".
Which top corner the button row gets: the tail's side, so it follows the
bubble when it mirrors. The grip's corner is `gripCorner`, which is kept
clear of this one.

This only moves them. What the buttons *do* is decided elsewhere and
doesn't depend on where they are: widening still steps, restoring still
goes straight to the default, and the drag still follows the direction
the bubble grows rather than the grip's own corner.
Which corner the grip gets, and which way its glyph points there.

Horizontally it stays opposite the button row, on the side the bubble
grows into. Vertically it follows the edge that actually moves: the top
normally, the bottom once the bubble has been flipped below the character,
where the tail pins the top edge instead. Left at the top through a flip,
the grip asked you to drag downward — into the character — while the empty
half of the screen it was growing into lay past the other end of the box.
The filled circle behind the ✕ makes it read larger than its point size,
so it's set 10% down from the 18pt the other controls were measured
against.
30% smaller again than the close button's original 18pt.
Free resize in both axes at once, for when neither the widen button nor
the height steppers give the size the user wants.

Measured against the pointer's position on screen rather than the
gesture's own translation: the bubble is re-anchored to the character on
every size change, so it moves under the pointer mid-drag and a
translation reported in the window's own coordinates would drift.
The glyph flips with the corner, so the arrows always point out of it:
↖↘ at top-leading and bottom-trailing, ↗↙ at the other two.
Enough to sit clear of the bubble's rounded corner rather than
tucked into it. This is also the grip's hit area, and at a bottom
corner it is what the footer row has to stay above — so it is as
small as a corner target can be and no smaller, rather than sized
for looks alone.
Drag the grip the way you want the bubble to extend, on both axes at once.

The rule — which edges grow, why the directions are captured once at the
start of the drag, and the oscillation that reading them fresh caused —
is `ChatResizeDrag` in SecretaryCore, where it has tests. This only
feeds it the current layout and applies the answer.

Note the drag is keyed to the layout, not to the corner the grip happens
to be in — only the layout says which edges are free to move. The two
agree on all four axes now that `GripCorner` puts the grip on the
growing corner, so the drag reads both ways at once: "the way you want
the box to extend" and the usual corner-handle "away from the box".
MARK: - Sections

Shown only once detection has finished and found nothing. The two steps
are both required: a user can have the binary installed but not signed
in, and that failure would otherwise only surface on the first turn.
The answers, drawn in the order the rule hands them back.

Built from `secretary.offeredApprovalAnswers` rather than written out
here: which buttons exist is a decision — Always is off the card for a
folder outside the projects, for a tool outside the allowlist, and for
every class that must be asked about each time — and a decision in this
target is one no test can see.

Deny is the plain button at the end. It is the answer that costs
nothing, so it should not be the one the eye lands on.
Anything that isn't read-only leaves a mark somewhere — currently
that means sending a file off this Mac. Give it a louder colour so
it never looks like the routine local approval.
"Send to Claude?" is right for a file leaving the Mac and wrong
for a click inside the user's own browser — nothing is being
sent, something is being done, as them.
Says what Always costs before it is pressed. The button is
only on the card when a grant can actually be kept, so this
line appears with it and never on its own.
Says what it costs. The running turn is a CLI invocation
that can't be paused or resumed, so replacing it throws
away whatever it had done.
One per character who was free when this was drawn, and none
at all when nobody was — the empty list is the rule, so there
is no "is anyone free?" branch here to disagree with it.

Their own row rather than alongside the two above: those
answers are about this character's queue, these hand the work
somewhere else entirely, and a row of four buttons reads as
four shades of the same choice.

One menu, not one button each. Buttons were the first shape
and they cannot survive a roster: four characters already put
three rows under the two answers above, and the card would
grow a row per character with nothing to stop it — which is
the unbounded growth the charter forbids in the panels, for
the same reason. This is the same height whether two are free
or twenty, and a long list scrolls inside the menu, which is
AppKit's problem rather than this card's.

A plain string label, deliberately: a `Menu` whose label is
built from several views renders as a bare chevron in this
window — the bug that Model and Effort in Profile were fixed
for, and it would leave this control with no words at all.
Without this the menu takes the whole width of the card
and reads as a banner rather than as the third answer.
Says what the grant covers and how long it lasts. "This site"
is the unit that was approved, not this one page, and the
person should read that here rather than discover it later.
A new plan is a new decision: the acknowledgement inside must not
carry over from the last one the user waved through.


## CommandCenter.swift

One instruction file dropped on the command window, already read: the drop
is the moment the file exists for sure, and holding text rather than a URL
means nothing re-reads the disk at send time.
A file riding along as a real attachment — an image, a PDF, a CSV. Held as
a URL because each recipient's own Secretary stages it, exactly as the
chat's drop does; reading it here would only be a second copy.
One finished turn of a commanded character, as the results strip shows it.
When this answer reached the window.

Stamped on arrival rather than derived from anything on screen: the
strip holds answers from four characters that finished minutes apart,
and without the time it reads as one conversation that all happened at
once (the owner asked for it, 2026-08-20).
The reply's own question, offered as buttons. Emptied once picked —
the question has been answered, and a second click would answer it
again.
A commanded character's permission card, waiting for an answer here rather
than in her chat.

Keyed by the character, because she holds at most one `pendingDecision` at a
time: a second card from the same character replaces the first rather than
stacking, which is exactly what her own panel shows.
What the command window is holding: who is ticked, what is waiting to go,
who has been commanded, and what has come back.

Gathering and applying only. Every decision — who a command reaches, what
each copy says, how files merge and route — is a pure function in
`SecretaryCore`, because this target is never linked into the test bundle.
Everyone on the desktop, asked for rather than held — the same rule as
`CharacterBus`, so a character added or deleted needs nothing rewired.
Hands one character her copy of the command, with the files that ride
along as attachments.
Ends the sessions of everyone in the set.
Answers one character's waiting permission card.

Its own door rather than another `deliver` of the answer's words:
`submit` opens by dropping whatever card is pending, so sending "Once"
as a message would throw the question away and then ask her to do
something called "Once".
Who is ticked. Commands only ever reach ticked characters; the set can
change at any time and takes effect on the next send.
The message being written. In the model rather than the view so the
arrow-key monitor can consult it and recall can rewrite it — and so it
survives the view being rebuilt when the borrowed look changes.
The red line under the box, when there is one.
Instruction files waiting to go with the next send, in drop order —
the order they merge in.
Files waiting to go as attachments.
Everyone this window has sent a command to since the last
"End all". Hiding the window does not touch it — hiding keeps
sessions alive by design.
Bumped by the controller when the window comes up, so the caret lands
in the box — the same counter idiom as `ChatBubbleLayout`.
The slab's width. The controller owns changing it — edge resizes and
the saved value both land here, and the view only draws it.
Height the person granted beyond the minimum, all of it given to the
message box — the owner's rule (2026-08-19): resizing taller grows the
box, everything else keeps its place. Zero is the default, which is
also the minimum.
The box's own text size, moved by ⌘+/⌘− while the box holds the caret.
What commanded characters have answered, newest first, capped so a
long day of commands cannot grow the window without bound.
The results strip folds — the owner asked for it closable.
Cards waiting on the person, oldest first. Never folded away with the
results: a question nobody can see is the bug this exists to fix.
What was sent from this box, for ↑↓ recall — this window's own, not
any character's, and this session's only, same as the chat's.
The line said "tick somebody"; they just did. Leaving it up would
scold a state that no longer exists.
One door for the drop and the picker both; the role rule decides what
the file becomes.
The "Clear" link: everything composed but not yet sent. Not the
results, and never the sessions.
Sends the draft and the waiting files. Returns whether they went.
MARK: - ↑↓ recall — the same walk the chat box does

Up: step back through what was sent, stashing the unsent draft first
so stepping past the oldest and back down returns it intact.
Down: forward again, ending on the stashed draft.
MARK: - Results

A commanded character's turn came to rest. Anything she finishes while
commanded lands here — hand-offs between recipients included, which is
how divided work stays visible without opening her chat.
Parsed again for the body: `FinishedTurn.text` still carries
the ```choices fence (driven 2026-08-19 — the strip showed
it as literal text under the buttons made from it).
Newest first, oldest off the end — 20 is a strip, not an archive.
Answers one result's question with the option's own words, exactly as
the chat's picker does — never a bare letter.
The question has been answered; the buttons would answer it twice.
The strip as one document — what Save writes and what Copy puts on the
clipboard, so the two can never disagree about what "the results" are.
MARK: - Permission cards

A commanded character is blocked and is asking. Same rule as `record`:
only characters this window commanded, because a card raised in a chat
the person opened themselves belongs in that chat.
Her card is gone — she may have been answered in her own chat, or have
dropped it. Either way the buttons here would answer nothing.
The person pressed Once / Always / Deny here. Taken off the strip
immediately rather than waiting to be told it settled: she may go
straight back to work, and buttons that linger read as unanswered.
MARK: - Text size

⌘+ / ⌘−. Persisted like the window's frame — a size chosen once is a
preference, not a session whim.
"End all": every session this window commanded is ended, whether or
not it is still mid-turn — ending the stuck ones is the button's job.
The sessions those cards belonged to are gone.


## CommandWindowController.swift

The command window's panel: a `FloatingPanel` that can also be resized by
its edges. `.resizable` in the style mask is not enough — a *borderless*
window gets no resize bands from AppKit at all (driven 2026-08-19: drags
on and just outside every edge either moved the window or did nothing).
So the edges are tracked by hand, in `sendEvent`, which is also what keeps
it smooth: the frame moves synchronously with each dragged event instead
of round-tripping through a SwiftUI gesture.
How far from an edge still counts as grabbing it.
True while the person is holding an edge. The content-height follow
must not re-anchor the frame during that — two writers re-anchoring
against each other walked the window down the screen by exactly the
resize amount (driven 2026-08-19).
An event that arrives while this window is not key carries no
window, and `locationInWindow` is then screen coordinates — the
edge test read those against the window's size and never
matched (driven 2026-08-19: the same grab resized when the
window was key and moved it when it was not).
A synchronous tracking loop, not passive event watching: a swallowed
mouseDown starts no AppKit drag session, so the dragged events that
follow it are never routed back to this window (driven 2026-08-19 —
the grab armed and then nothing arrived). Pulling them with
`nextEvent` is the pattern every borderless window resize uses.
The top edge is the one that grows upward; every other change keeps
the top still, matching how the content-height follow behaves.
The one command window: a borderless floating slab, remembered where it was
left, hidden — never torn down — by Esc and the menu row.

Belongs to the app, not to a character, so like Token Usage it borrows the
focused character's look and has to notice when that character changes.
The ↑↓ recall monitor — see `watchArrowKeys`.
The slab's height with no granted extra — what the window may never
shrink below, and the zero point the extra is measured from.
Whose look the contents were built from — the same staleness check as
`UsageWindow.follow`, for the same reason.
Whether Esc typed here is this window's to answer.
Nothing in this app takes focus by itself; without activating, the
window opens behind whatever is in front and reads as "nothing
happened" — and the whole point of opening it is to type.
Esc and the menu row: off the screen, sessions untouched. What was
ticked, the files waiting, and who has been commanded all survive.
The window is sized by this controller alone, from the slab-height
preference. Left at its default, the hosting view re-fits the
window to the content after every edge-resize — the person drags
the bottom edge down and the window snaps back up (driven
2026-08-19, a 53pt resize that ended as a 53pt slide instead).
Typing is what this window is for; a click anywhere in it should
hand over the keyboard, same as the chat.
Off, deliberately, though every other FloatingPanel has it on: the
window server honours it *beside* our own edge tracking and the
performDrag move, and the two moved the window a second time after
every resize (driven 2026-08-19 — each grow slid the window by the
same distance). All dragging goes through the SwiftUI gesture.
↑↓ recall what this box has sent, exactly as the chat box does — and
through the same door: a local `NSEvent` monitor, because `TextField`
eats the arrow keys before `.onKeyPress` ever sees them (the chat's
receipt for this is in `ChatPanelView+Keys`). Who owns the arrows is
`ArrowKeyOwner`'s decision, not an `if` chain here: a multi-line draft
keeps them for the caret. No choices are passed — the results strip's
picker is clicked, not steered, so the arrows never mean three things
in this window.
The view, wired back to the window it lives in for the background drag
— the gesture and the reason it exists are `CommandWindowView`'s.
The person dragged an edge. Width is taken as it is (clamped);
anything above the natural height becomes the box's granted extra —
the owner's rule: a taller window is a taller text box, everything
else keeps its place. Both are remembered, like the origin.
The window's height follows the slab — the box grows to ten lines,
files and the error line come and go — with the *top* edge held still,
because AppKit grows a frame upward and a window that jumps up when an
error line appears reads as broken. Not `sizingOptions`: see the
warning on `contentHeightChanged` in the view.

`height` arrives as natural height plus the granted extra, because the
box already draws the extra; the minimum the window may shrink to is
the natural part alone.
While an edge is held, the person's hand owns the frame — the
resize loop is already applying it, and a second writer here
re-anchors against a frame mid-change and walks the window.
Puts this window in one character's look — appearance and contents move
together or the window wears half of each (see `UsageWindow.follow`).


## CommandWindowView.swift

The command window: tick who should listen, type once, everyone ticked
gets it. Spotlight-shaped — one borderless rounded slab — with the
character list above the box, the same growing message box the chat uses,
the red line under it when nothing can go, and a foldable strip of what
the commanded characters have answered.
Starts the native window drag. The *detection* lives here as a gesture
because neither AppKit route sees the click on this window —
`isMovableByWindowBackground` never fires (the hosting view answers the
background hit-test for every point) and the window's own `mouseDown`
never runs (SwiftUI consumes the click first); both driven 2026-08-19.
The *movement* is `performDrag`, not per-event `setFrameOrigin`: moving
the window from gesture callbacks stuttered visibly — the owner called
it out the moment they tried it — while the native drag loop is the
same one every title bar uses.
Hides the window — the ✕, same meaning as Esc: sessions keep running.
Told the slab's rendered height, so the window can follow it. Sizing
the hosting view by `preferredContentSize` instead left every
`DragGesture` in the window dead — driven 2026-08-19: chips clicked
fine, the drag never fired once, and the chat panel's grip (a plain
framed hosting view) dragged fine under the same synthetic events.
Whether Copy has just run, so the glyph can say so.
Every size on the slab, from *this box's* text size rather than the
chat's. They came off `appearance.settings` before, so ⌘+ grew the words
being typed and left the chips, the results and the rhythm where they
were — the owner's report opening Sprint 21.2.
The gesture rides on the fill itself, the way the resize grip
rides on its glyph: hit-testing reaches the background exactly
where no control in front claims the point, which is what "drag
by the background" means.
The whole slab takes the drop, same as the chat bubble — naming one
rectangle as the target is the belief the chat's drop area undid.
Who is listening. Every character on the desktop, tick by click; a
command only ever reaches the ticked.
Everything waiting to go with the next send: instruction files in
merge order, then the attachments.
The controls live *in* the box since 20.1 — the owner asked for
Clear at its bottom-left corner drawn like the send affordance, and
the paperclip beside ↵ rather than out in the footer.
Return sends, Shift/Option-Return breaks the line — the same
contract as the chat box, for the same `onSubmit` reason.
The control row's strip: text scrolls above Clear/📎/↵
instead of running underneath them.
Below the measurement, so the box's own height keeps coming
from the text: in a stretched box the caret belongs at the
top, not floating at the bottom of the granted space.
The granted extra rides on top of the draft-driven height, so a
taller window is a taller writing area and nothing else moves.
The field is top-aligned and only as tall as its text, so in a
stretched box most of the writing area is empty scroll space — a
click there must still land the caret, or the box reads as dead
(driven 2026-08-19: a click mid-box typed nowhere).
MARK: - Permission cards

What a commanded character is blocked on, asked here.

Never foldable, unlike the results: this is the one thing on the slab
that is waiting on the person, and a question tucked behind a chevron is
the bug this was written to fix.
Capped and scrolling inside itself, exactly like the results strip
and for a stronger reason. Four characters commanded at once raise
four cards, and uncapped they grew the window to 921pt on a 1030pt
screen — driven 2026-08-21 — which pushed the later cards and the
whole results strip off the bottom of the display. **A card nobody
can reach is the bug this section was written to fix**, so it must
not be able to come back by the window simply getting too tall.

Measured-then-capped rather than a bare `maxHeight`: a `ScrollView`
with an unbounded max collapses to nothing, which is how the results
strip once showed its header and not one row.
Room for two cards at a comfortable size; the rest scroll. Questions
outrank answers, so this is given more of the slab than the results.
The card's own answers, so the buttons here and the buttons in
her chat can never come apart — `offeredApprovalAnswers` decides
whether Always is on offer at all.
MARK: - Results

What has come back, foldable like the usage window's sections — the
whole header row is the target, not a 10pt chevron.
copy, Save, clear — the owner's order (2026-08-20).
Sized from the measured rows, capped: a bare `maxHeight`
lets a ScrollView collapse to nothing — driven 2026-08-19,
where the strip showed its header and not one row. A strip,
not a transcript: a few answers, its own scroll for the
rest, so results can never crowd out the box.
Writes the strip to a file the person names. Markdown by default —
the answers are Markdown, and the owner named the extension.
The same document, on the clipboard. The glyph turns into a tick for a
moment: a copy that changes nothing on screen is indistinguishable from
a button that did nothing.
Same words the chat puts beside a name, so the two windows
never disagree about what time something happened.
The reply asked something. Answering sends the option's own
words to that character — the chat picker's rule, because a
bare letter is ambiguous for the next turn.
Two glyphs share the lane now — ↵ and the paperclip beside it.
"Clear", drawn exactly like the send affordance — a word, not a border
— at the box's bottom-left, per the 20.1 spec.
Hands the drag to the native loop the moment it starts. `performDrag`
blocks until the mouse goes up, so this fires effectively once.
The ✕. Hiding, not closing: the hint beside จบการทำงาน says so, and
Esc does the same thing.
A dropped file on its own is a command, same as an attachment in chat.
Shift/Option-Return breaks the line where the caret is, through the
field editor — the append-at-the-end version already shipped as a bug
in the chat box (2026-08-17), and this box must not re-ship it.
Never shorter than 2.5 lines — the owner's number (20.1), room for the
control row without the box reading as a single cramped line.
Choice buttons that wrap to the strip's width instead of forcing it wider —
the same must-not-decide-the-window-size rule every panel here lives by.
Rows of subviews, wrapping when the line is full. A `Layout` because
HStacks cannot wrap and a `Grid` would make every column as wide as the
longest option.
Carries the waiting cards' height out to the strip that has to cap it, so
four of them cannot push the window past the bottom of the screen.
Carries the result rows' height out to the strip that has to cap it.
Carries the slab's rendered height out to the window that has to match it.


## CompletionNotifier.swift

Puts a macOS banner up when a character finishes work nobody was watching,
and opens her chat when it is clicked.

**Nothing here works without a bundle.** `UNUserNotificationCenter.current()`
looks the process up by bundle identifier and raises an ObjC exception when
there isn't one — which cannot be caught from Swift, so it is a crash, not an
error. `swift run AISecretaryApp` has no bundle, and that is the command the
charter's "drive it before committing" step uses, so every entry point here
checks `isAvailable` first and does nothing when the answer is no. Under
`swift run` the decision still runs and is logged; the banner itself can
only be checked from the packaged `.app`.

There is no setting for any of this on purpose: the backlog asks for
"notification settings ตาม macOS", so System Settings → Notifications is the
control surface, and a second switch inside the app would only be a way for
the two to disagree.
Which character a click should open. The id travels in the
notification's `userInfo` rather than being remembered here, because the
click that matters most arrives at a process that has only just
launched and remembers nothing.
Whether this process can talk to the notification centre at all — see
the note on the type.
Read from the delegate callback, which the system calls off the main
actor — hence `nonisolated`, without which Swift 6 rejects it.
Claims the delegate and asks, once, for permission.

**Must be called from `applicationDidFinishLaunching` before it
returns.** A click on a banner is allowed to launch the app, and the
system delivers that click as soon as the delegate exists; installed any
later, the launch-by-click path silently does nothing.
Posts one banner for one character.

The identifier is the character's, so a second answer from the same
character replaces her own waiting banner instead of stacking — ten
loop checks while you are out should leave the latest, not a column.

- Parameter picture: her own portrait, when she has one. It becomes the
  image on the right of the banner — **not** the small icon on the left,
  which is the app's and cannot be set per notification: macOS reads that
  one from the bundle. With four characters answering, the portrait is
  what says which of them this is before you read the name.
nil means "now" — a trigger would schedule it.
Her portrait, wrapped for the notification centre.

**Attaches a copy, never the original.** `UNNotificationAttachment`
takes ownership of the file it is given and moves it into its own store,
so handing it `ProfileArtwork`'s URL would take the character's picture
off disk — she would lose her face the first time she finished something
unwatched. The copy goes to the temporary directory, which the system
empties by itself; if the attachment can't be made, the copy is removed
here rather than left behind.
MARK: - UNUserNotificationCenterDelegate

What to do when one arrives while the app is frontmost.

It can: `completionNotice` refuses only while *her* chat is on screen, so
somebody typing to another character still gets one. There the banner is
the whole point, and it is shown rather than swallowed, which is what the
system does by default with the app in front.


## DomainBridge.swift

MARK: - The view edge

SwiftUI views MUST NOT import FunctionalCore. Bow exports its own `State`
type, which shadows SwiftUI's `@State` property wrapper and makes every
`@State var` in the file fail with "'State' is ambiguous for type lookup".

So the conversion happens here instead: this file speaks Bow on one side and
plain Swift on the other, and it contains no views. Everything a view needs
from a domain type arrives as `String?`, `Bool`, or a plain value.

Registers a project. Returns the note to show the user, or `nil` when
it was added cleanly — both "already registered" and a failed write are
things the user should see, and neither should be a silent `try?`.

The active profile's picture as a plain optional, for the character view.
One character's own picture. Two on the desktop drawing the same face
would be two characters nobody can tell apart.
Stores a chosen picture. Returns the note to show, or `nil` on success.
The chosen model, or `nil` while inheriting the backend's own — the
shape the settings menu's checkmarks compare against.
`nil` means "go back to inheriting".
The three pieces of "something is in flight" the panel draws: a question
waiting on the user, a standing check-back, and an instruction file being
worked through. Each is an `Option` on the Secretary and a plain optional
here, for the same reason as the two above — the views that read them are
full of `@State`, so they can never see Bow's `Option`.
The sub-agent working on her behalf, when one is.
What the assistant has asked for a file for, when it has.
Which of the three states the panel is looking at, as a value the hint
can be asked for. The order matters: not-found is a finished answer,
while a missing installation with no answer yet is still the search.


## FloatingPanel.swift

A plain container that also acts on the first click, for the cases where
AppKit hit-tests it rather than the SwiftUI view inside it.
A SwiftUI host that acts on the very first click.

These panels deliberately never become the active app, so by default AppKit
treats a click on them as "bring this window forward" and swallows it. That
cost a click everywhere: opening the chat from the character took two, a
button in the panel took two, and a link took two.
A transparent, floating, non-activating panel used for both the desktop
character and its chat panel. Stays above normal windows without stealing
focus from the frontmost app, and can be dragged by its background.

Not `final` since Sprint 20: the command window subclasses it for edge
resizing, which a borderless window has to do by hand.
Whether a click anywhere in this panel should hand it the keyboard.

Off for the character, on for the chat — see `sendEvent`.
Without this the window is never told the pointer moved, so hover
effects inside it (the link underline and pointer) never fire.
Don't take key status just because someone clicked: otherwise the
first click on the character only focuses the window and is thrown
away, and opening then closing the chat costs three clicks instead of
two. Controls that genuinely need focus — the text field — still get
it, because AppKit asks the view first.
The app decides what is on screen, not AppKit's saved state. Left
restorable, a panel hidden when the app was last quit can be ordered
out again after launch — undoing the `orderFrontRegardless` in
`applicationDidFinishLaunching` and leaving a running app with no way
to reach it except the status bar.
Takes the keyboard when clicked, for the panel that asked for it.

`becomesKeyOnlyIfNeeded` above means a click only hands over the keyboard
when the clicked view insists — which the text field does and nothing else
in the chat does. So clicking the transcript, a message, or a button left
the keyboard wherever it was, and ⌘H went to the app behind and hid *that*.
The chat looked focused and wasn't; the only tell was whether a caret was
blinking.

Driven check behind this: with the field clicked (panel key) but the app
inactive, ⌘H already hid our own windows and left Finder frontmost — so
key status while inactive is enough, and this only widens which clicks
grant it.

In `sendEvent` rather than in a view or the flag above, for two reasons:
the window sees every click regardless of which view swallows it, and
leaving `becomesKeyOnlyIfNeeded` alone means this can't bring back the
regression that flag prevents — a first click spent on focusing the window
instead of pressing the button under the pointer.


## GlobalHotKeys.swift

Claims a key from the whole system, so it reaches this app even when another
one is frontmost.

Carbon's `RegisterEventHotKey` is the only way to do this without the
Accessibility permission a `CGEventTap` demands, and it is the only one that
*consumes* the keystroke: `NSEvent.addGlobalMonitorForEvents` can watch but
not swallow, so the frontmost app would act on the key too.

Why any of this is needed: a local monitor and a menu key equivalent both
only ever see events the system already decided to deliver here. With the
chat bubble floating above another app, Esc went to that app and the bubble
stayed — the handler was correct and the key never arrived.
Actions by shortcut, set once by the delegate.
Carbon calls back into a C function that cannot capture context, so the
live instance is reached through this.
Brings the claimed set in line with `claimedShortcuts`. Safe to call on
every visibility change: already-claimed keys are left alone.
Runs `body` with every claimed key handed back, then claims the same set
again.

For modal panels. A Carbon hot key fires no matter what is on screen, so
with the chat open behind an open panel, Esc closed the chat and left the
dialog sitting there — the one key everybody presses to cancel a dialog,
swallowed by a window in the background. Suspending rather than ignoring
the key matters: an ignored hot key is still consumed, so Esc would do
nothing at all.
A refusal is not fatal: another app may already hold the combination,
in which case this one simply keeps working from its own windows.
MARK: - Carbon plumbing

`'AISC'`, so our hot key ids can't be confused with another app's.
Carbon delivers on the main thread, but the callback itself is
outside the actor, so hop rather than assert.
Stable per-case id for Carbon, which identifies hot keys by number.


## ImagePicker.swift

Picks a picture for a profile through a system panel, so the file always
comes from an explicit human choice rather than a path the app derived — the
same rule the project picker follows, and what a sandboxed build would need.
Same reason as `ProjectPicker`: an open panel owned by an inactive app
is not key, and its file list ignores clicks until something activates
the app. This one is reached from the Profile panel, which is inside
the same non-activating chat window.
Esc has to cancel this dialog, not the chat window behind it.


## InfoWindows.swift

Panes of the conversation that have been pulled out to stay on screen.

One floating window each, all of them independent of the chat: the point is
to keep a table in view while the conversation moves on, so closing the
bubble must not take them with it.

Nothing here throws a pane away except the user saying so. The close button
and Esc both only put a window away; the pane stays in the menu and comes
back from it. Losing pinned text to a stray click on a red dot was the wrong
trade — the whole point of pinning is that the text survives.

`Clear all`, and dropping the oldest past the limit, are the only ways a
pane is destroyed.
What exists, whether or not it is on screen — a pane put away is still
here, which is what the menu is built from.
Told whenever the number of panes *on screen* changes, so Esc is claimed
while a pane is up even with the chat closed, and released the moment the
last one is put away.

Every hide and every show has to report, not just open and remove: a pane
put away leaves the screen while staying in the set, and that is exactly
the difference `hasSomethingToDismiss` was rewritten to notice. Firing
only on the set's count is what left Esc claimed with an empty desktop.
How many panes are actually on screen. The set's count answers a
different question — see `hasSomethingToDismiss`.
Everything about a pinned window that AppKit draws rather than SwiftUI.

The owner (2026-08-20): a pinned window came up in the *system's* theme
rather than the character's. Her palette was reaching the content —
`InfoWindowView` sets it — so what was left showing was the window
itself: the title bar, and the ground behind the hosting view. Those are
AppKit's, and `appearance` alone was evidently not enough to move them.

So the surface is painted from her palette outright, in her own sRGB
values, and the title bar is made transparent so it takes that colour
instead of drawing its own. Nothing here can resolve against the
system's setting, because nothing here asks the system anything.
Still set: it decides the caret, the scroller and the title text,
which are drawn by AppKit and are not colours we can hand it.
Glass frosts what is *behind the window*, so an opaque window gives
it nothing to work with and the surface comes out a flat slab. The
ground colour painted above is exactly what has to go.
Left to AppKit here, deliberately, and it is the one place this
window differs from the bubble: a `.titled` window's bar is already a
translucent material lit by `panel.appearance`, which is hers.
Making it transparent instead would leave a strip of bare desktop
across the top, because the content view does not reach under the bar
without `.fullSizeContentView`.
The same lesson as the chat bubble at 0.21.323: the window's own
shadow is invisible behind a solid ground and shows through a frosted
one as a dark smear. AppKit caches the shape, so switching it off is
not enough on its own.
Also the door a ` ```window ` block in a reply comes through, so a pane
the assistant asks for behaves exactly like one pinned by hand.
Already pinned: bring that one forward rather than making a second
copy of it. See `InfoWindowSet.matching` for why this is on content
and not on a timer.
Dropping the oldest is the set's rule; its window has to go with it.
A pane coming back from the menu with the chat closed is the whole
reason this reports: it is the moment Esc has something to put away
again, and nothing else would say so.
The rule is infoWindowSize, in SecretaryCore where it has tests.
What is on screen is this app's decision, not AppKit's saved state.
Every pane back on screen, in the order they were pinned so the newest
ends up in front.
Esc: off the screen, still in the menu.
⌘H: all of them off the screen, all still in the menu. The counterpart
of `showAll`.
Whether one of these panes is the window being typed in — asked by the
character who owns them, so Esc goes to her.
Hides whichever pane is being typed in, and says whether it did. The Esc
ladder asks this first so that Esc means "put this away" when a pane has
the keyboard, and "close the chat" otherwise.
The frontmost pane that is on screen, put away, whether or not it holds
the keyboard — and whether it did.

The rung between `hideKeyWindow` and the chat. Esc is claimed from the
whole system while a pane is up, so it arrives while the person is typing
in another app entirely: no pane of ours holds the keyboard then, and
without this the claim was spent on nothing while a pane sat there in
plain sight refusing to go away.
Explicit removal, from `Clear all` or from the limit being reached.
Cascade, so a second window doesn't land exactly on the first. The rule
is infoWindowOrigin, in SecretaryCore where it has tests.
MARK: - NSWindowDelegate

The window's own close button, which puts the pane away without
destroying it — the same thing Esc does. It stays in the status bar menu
and one click brings it back, text and all.
One pane's contents: the same renderer the chat uses, scrolled.
This window sets the palette rather than inheriting one: it is a root,
not a view inside the chat panel.
The pane's ground: Liquid Glass when the character has switched it on,
otherwise her solid ground — the same rule, and the same shape of code,
as the chat bubble's `bubbleSurface`.
Not decoration. A window is click-through wherever its pixels
are fully transparent, and `Color.clear` under a
`glassEffect` counts as transparent however frosted it looks
— that is what killed the chat bubble's resize grip at
0.21.322. 0.15 is above the window server's ~5% threshold and
invisible under the frosting. Do not "clean this up" into
`Color.clear`.
Only while the pointer is on the window, the same rule as in the
chat: a pane is pinned to be looked at, and a button sitting on it
permanently is in the way of the one thing it holds.
`themedWindow` is deliberately taken apart here. Its `.background`
is a solid ground, and a solid ground behind glass is the one thing
glass must not have — it would frost that instead of the desktop and
come out flat. Everything else it does is wanted.


## InstructionPlanCard.swift

The steps read out of an instruction file, shown in full before any of them
runs.

This card *is* the safety of the feature. Everything else — the untrusted
framing in the prompt, the pattern scan, the per-action permission cards —
supports it; none of it replaces someone reading the list and saying yes.
So the steps are shown verbatim, in order, with no summarising and no
scrolling past: what the app is about to do fits on the screen or the file
is too big to run blind.

It decides nothing. Whether there are risks, and whether the file changed,
are answered in `SecretaryCore`; this only renders the answers and calls
back.
The colours in force, set by whichever window this view is inside.
Sizes come from the app's text setting, like everything else the
person reads — a card pinned at 11pt beside 28pt replies is the same
bug the panels had.
Ticked by hand when something was flagged. The extra click is the whole
point: a warning that sits beside an already-enabled button is a warning
nobody has to have read.
The words that triggered it, not just the verdict:
a warning you can check is a warning you can weigh.


## MarkdownBodyView.swift

Renders a markdown body the way the chat does: prose, real tables, and code
blocks that scroll sideways instead of wrapping.

Extracted so an info window shows exactly what the chat showed. A second
renderer would drift — the first thing to go would be the rule that a table
scrolls inside its own box rather than widening the window.
The colours in force, set by whichever window this view is inside.
Which face the prose and the table cells are set in. Code blocks ignore
it — a fenced block is monospaced because its alignment carries meaning,
whatever the conversation around it is set in.
For the language label above a code block, which is a caption rather than
part of the content.
AppKit-backed: SwiftUI's Text draws links but doesn't open
them from a non-activating panel, and can't show a pointer
or a hover underline over them.
Cells size to their content; the scroll view provides the room.
Plain text, not markdown: inside a code block an asterisk is
an asterisk, and a backtick is a backtick.


## MessageTextView.swift

A message body, rendered by AppKit so its links actually behave like links.

SwiftUI's `Text` draws link attributes but doesn't act on them inside a
non-activating panel — the click falls through to whatever window is behind
the bubble, and the pointer never changes. `NSTextView` handles all three
things a link needs: it opens on click without stealing focus, it shows the
pointing-hand cursor, and it gives us somewhere to hang the hover underline.
Text selection comes along with it.
Which face the conversation is set in. Passed alongside the size for the
same reason the size is passed at all: this is AppKit, so it needs a
concrete `NSFont` at the moment the storage is built, not a SwiftUI
modifier applied to it afterwards.
Passed in rather than read from the environment: the text is drawn by
AppKit into an `NSTextStorage`, so it needs `NSColor` values at the
moment the storage is built — `labelColor` and `linkColor` follow the
*system's* light/dark setting, which is not ours to assume.
Stands in for "as much room as you like" when measuring. A finite number
rather than `.greatestFiniteMagnitude`: TextKit lays out against this
value, and the infinities produce degenerate line fragments.
Underlining is left to hover, so the resting state stays quiet.
Re-applied on every update, not only in `makeNSView`: the theme can
change while the window is open, and the link colour lives on the
view rather than in the storage.
SwiftUI needs a height for the width it's offering; ask the layout
manager rather than guessing, or long replies get clipped.

The width reported back is the width the text *used*, which is narrower
than the offer for anything short. That is what lets a bubble hug a
two-word message; returning the offered width made every bubble as wide
as the row.
Every proposal is answered, including the two SwiftUI uses to learn
how flexible this view is. Returning nil for those — which is what
the zero-width and unspecified cases used to do — leaves the layout
treating the text as infinitely stretchy, and inside a bubble that
showed up as a two-word message filling the whole row.

Answered properly, the range is: at its narrowest, the longest single
word; at its widest, the text set on one line.
A container of 1pt can't break a word, so what comes back is the
width of the longest one — the narrowest this text can ever be.
Rounded up, and never wider than the offer: `usedRect` can come back a
fraction over the container's own width, which would re-wrap the last
word on the next pass.
The width this text would take if nothing made it wrap.

Used as a cap on the view, not as its size: a short message is held to
its own width so the bubble hugs it, and a long one asks for more than
the row has and gets the row. Measuring here rather than leaving it to
`sizeThatFits` is deliberate — a representable is treated as fully
stretchy by the surrounding layout no matter what it answers, which is
why "ok?" was drawn in a bubble the full width of the panel.

Measured in one pass, deliberately. A reply with newlines in it should be
as wide as its widest line — which is what this returns, because a hard
newline still breaks the line when nothing else does. Splitting the text
up and measuring each line separately gives the same answer and costs a
scan of the whole message per line, on every streamed token.

Measured with a fixed palette, which is not a shortcut: colour has no
effect on line breaking or on the width of a glyph, and threading the
live theme through a pure measurement would suggest it did.
Markdown emphasis keeps the chosen face and only changes weight and
slant, so a bold word doesn't jump to a different font.
Weight and slant resolved together, in one write per run. They used to
be two independent `if`s writing the whole font each time, and the
second overwrote the first: `***bold italic***` carries both intents,
so it came out italic and lost its weight entirely.
A family with no italic face is left upright rather than faked —
`convert(_:toHaveTrait:)` hands back the font unchanged, which is
the honest outcome.
Link colour is applied by `linkTextAttributes`, but the foreground
pass above would otherwise have overwritten it in the storage.
The `NSFont` for a choice, built from the system face rather than from a
family name.

This is the whole reason the setting exists. The transcript used to ask
for `monospacedSystemFont`, and SF Mono has no Thai glyphs, so every Thai
word fell out of it into whatever the system reached for next — Ayuthaya,
measured on 2026-08-14, which is wide and heavy enough that it was
reported as the chat being bold. Nothing was bold. A design asked for
this way is resolved per script, so each language gets that design's own
face instead of a fallback nobody chose.

Falls back to the plain system font at every step: an unavailable design
should cost the shape, never the text.
Kept out of `SecretaryCore`, where the type lives: the enum is the
choice, and this is AppKit's name for it.
The same choice for the parts of a message SwiftUI draws itself — table
cells, and the options under a question. They are the conversation too,
and a table set in a different face from the paragraph above it reads as
a rendering bug.
Underlines whichever link the pointer is over, and nothing else.

The underline is a temporary attribute rather than an edit to the text, so
hovering never touches the message itself.
The panel doesn't take focus, so without this the first click on a link
would only serve to activate the window.
`activeAlways`: the bubble floats over other apps, so the
pointer is often here while this app isn't the active one.
Where AppKit actually decides which cursor to show. The `.cursor` link
attribute isn't enough here: that runs off cursor rects, which are only
maintained for the key window, and this panel never becomes key.
Past the end of a line the nearest glyph is still "hit"; the fraction
is what tells us the pointer is actually beyond it.


## MikuAvatarView.swift

Original placeholder character: a friendly chibi avatar with teal
twin-tails, big eyes, and a hint of a sailor-style collar — evoking a
generic anime-companion look. This is original vector art, not licensed
character art (e.g. not Hatsune Miku) — swap in a real/licensed asset
later behind the same `CharacterView` seam.
Twin tails, behind the head, with a lighter inner highlight.
Collar hint at the base of the neck.
Head.
Side hair tufts framing the face.
Full bangs with a center part.
Eyes: large, expressive, with lashes and double highlight.
Open, smiling mouth.
Small state badge overlaid on the avatar so the assistant lifecycle
stays legible regardless of character art.
Read off the clock rather than animated from a stored flag. See
`pulseProgress` for why: the flag version kept breathing after the
work was finished, and `paused:` here is also what stops the redraw
dead when there is nothing to show.
Grey at rest, the state's own colour at full stretch. While
she is still, `progress` is 0 for ever and the base colour
is the state's — so success stays green and error stays red
rather than everything settling to grey.
The ring and the glyph keep their full strength: they are the
badge's outline against the character art, and fading them
read as the badge switching off rather than breathing.


## PanelToggleStyle.swift

The Projects / Profile / Skills / Settings buttons: how big they are, and
which one is open.

Two things `.toggleStyle(.button)` got wrong, both of them quiet.

**The colour.** AppKit strips the accent from a tinted control whenever its
window isn't key. Reasonable for an ordinary app, wrong for this one, whose
window is *designed* never to take focus — so an open pane had nothing in
the footer saying so. Open Projects, then click the Add Project dialog, or
Finder, or a browser, and the button went grey while the pane stayed
exactly where it was. The fill is drawn here instead, and stays put whether
or not the app is frontmost, which is the only honest answer in a window
that spends its life in the background.

**The size.** That style also ignores the surrounding `.font`, so the
footer never actually grew with the app's text size — the row looked the
same at 10pt as at 28pt, which is what the old comment about "unreadable
specks next to 32pt replies" was trying to prevent and didn't. The label's
size is set explicitly here.

Growing has a limit the window imposes rather than a number picked here:
four labels plus their padding stop fitting a narrow panel somewhere above
20pt, and the first attempt at this wrapped them mid-word — "Projec / ts".
So each label stays on one line and shrinks to fit instead. Widen the
window and they grow back.
Passed in, not read from the environment: a `ToggleStyle` is not a
`View`, so `@Environment` in one is never populated.
Glass mode swaps the accent fill for a neutral one: on glass chrome the
state is said by the surface, not by colour (Liquid Glass rule #7), and
`chipFill` stands off the glass in both palettes.
Never a broken word. Below this the label would be smaller
than the secondary text around it, at which point the row is
too cramped to read at all and shrinking further doesn't
help.
Glass buttons at the owner's request — but built on
`glassEffect`, NOT on `.buttonStyle(.glass)`/`.glassProminent`.
The system styles were tried first and failed this window's
founding test: with Finder frontmost their labels dim and the
prominent tint washes out to grey, exactly the non-key de-tint
this type exists to work around. The `glassEffect` *surface* was
proven alive on a non-key window by the sprint's gate spike, and
a drawn label colour stays put. (One deliberate breach of "no
glass on glass": these sit on the bubble's sheet, and the owner
asked for them anyway.)

`.plain` with hand-drawn padding, not `.bordered`: the bordered
bezel is a rounded *rectangle*, and its corners showed through
the capsule's ends as a second, squarer outline — the owner
spotted the double edge in a screenshot before anyone here did.
The glass capsule is the whole surface now, so it must also be
the hit area, hence the `contentShape`.
Behind the bezel rather than instead of it, so the corner
radius and hit area stay whatever the bordered style gives
every other button in the row.
`.tint`, not only `.foregroundStyle`: a bordered button takes
its label colour from the tint, so the foreground style alone
left the selected button's label the same blue as the fill
drawn behind it — a solid blue block with the word invisible
inside it. Seen in the running app; nothing about the code
read wrong.
Solid mode only — in glass mode the state lives in the glass itself.


## PlanUsageModel.swift

Keeps the plan-limit figures current while the usage window is open.

Each refresh is a short-lived `claude -p -- /usage`, so it is polled rather
than streamed, and only while someone is looking: the timer starts when the
window opens and stops when it closes. A companion that shells out every two
minutes forever, to draw a bar nobody is watching, is not a companion.
Set when the figures could not be read. Shown instead of a number,
never in place of one — a stale percentage presented as current is the
failure this whole class is trying to avoid.
Read once. The subscription tier does not change while the app is open,
and asking on every poll would run a second process for a fixed string.
Often enough that the bar is not misleading, rarely enough that it is not
a background job. The windows it tracks are five hours and a week long.
Single-flight: the poll and the refresh button can land together, and
two processes would race to set the same numbers.
Recognising nothing usually means Claude Code changed
its wording. Say so rather than showing the last
reading as if it were new.
Carried over so the tier does not blink out on a refresh
whose identity lookup happened to fail.


## ProfileSettingsView.swift

The Profile section of the settings panel: which secretary the app is
wearing, her details, her picture, and the brain she thinks with.

Model and Effort live here rather than in Settings because they are part of
who is answering, not part of how the window looks. Settings keeps the
things that change the app's appearance; this panel keeps the things that
change the secretary.

Selecting a profile takes effect immediately; the detail fields are edited in
a draft and committed with Save, because a text field that applied per
keystroke would announce a change in the conversation for every letter typed.
The colours in force, set by whichever window this view is inside.
Whose panel this is. One character, one chat window, one Profile panel
that edits her and nobody else — so there is no picker at the top any
more. Making another character is `New Character…` in the status bar
menu, which is the one place that creates one.
Which maker she works through, where its tool is, and whether it can be
reached. Only this panel asks: the maker belongs with the brain she
thinks with, not with the window's appearance.
Only for the Model and Effort rows. They are settings of the running
assistant rather than fields of the stored profile, which is why they
take effect on click while everything above them waits for Save.
The path box's own text. Applied by Test, not by Save — see `cliPathRow`.
Who this panel is about, read fresh so a rename from anywhere else shows.
A Grid, not a stack of HStacks with a fixed label column: the
labels have to line up, and the width they need changes with the
longest word and with the app size. "Personality" broke a 52pt
column the day it replaced "Style" — it wrapped mid-word — and
any number picked to fit it would break again at size L.
Hidden rather than shown and inert. opencode's own effort
setting is provider-specific and a local model ignores it, so
a row here would be a control that does nothing.
Keeps the fields in step when this character is edited from anywhere
else. Keyed on the revision rather than on the id, which no longer
changes: this panel is about one character for its whole life.
MARK: - Rows

Free text, as specified — anything beyond male and female is
the user's own words rather than a list they have to fit into.
Beside two lines of content, a centred label floats between them
and stops reading as the name of the field above it. The grid's
first-baseline alignment is what holds it against the first line
now; `.gridCellAnchor(.topLeading)` did it before and cannot,
because an anchored cell leaves the alignment system altogether
and sat a baseline off from the control beside it.
One picture per profile. The same menu shape as the Model and Effort
pickers, so choosing and clearing work the way the rest of the panel does.
Read from disk, so a change has to invalidate the label.
Clicking the name opens a real picker. The same entry point the slash
commands use, so a change here is announced in the transcript too — the
conversation is where the change takes effect, so that's where it should
be visible.
Which maker the work runs through, and whether the app can reach it.

The tick is the point. Finding the tool on disk used to be reported as
"Ready", which is true of a Claude Code that is installed and signed out
— and the user only discovered otherwise when a turn came back refused.
This row asks, and says what came back.
Coloured only when it failed. A green line of prose under
every healthy row is noise; the tick already said so.
Warning-coloured rather than muted: choosing between these
two makers is choosing between two safety models, and only
one of them stops to ask.
Asked when the panel opens, so the answer is about the configuration
in front of the user rather than whatever was true at launch.
Where the maker's tool is, for one the user installs themselves.

Unlike the other text fields in this panel it does not wait for Save:
Test *is* the Save for this row, and a path typed but never tested is the
one state nobody wants to be left in.
Follows a switch of maker, which replaces what the box should show.
Paints the answer and decides nothing — which of the three it is was
settled by `vendorConnection`, in a target the tests can see.
One hint for both rows, under the second of them, the way
Personality and Picture carry theirs in the content column.
The inherited marker sits beside the menu, not inside it, on purpose: a `Menu` label built from several views
renders as the chevron alone here, which is why these two rows used to
show their title and no value at all. The value is the one thing the row
exists to say, so it is the only thing in the label.
The grid gives the column the width of the widest label; this
only says the label itself must not be the thing that wraps.

Two measured insets, because the panel's left column is drawn by three
different controls and each one indents its own text by a different amount.
`.borderlessButton` draws a menu label about 4pt inside its own frame,
`.roundedBorder` draws a field's text about 6pt inside, and a caption draws at
its frame edge — so with every frame at the same x (confirmed through
Accessibility: all of them report 1243.5), the text still reads as three ragged
columns. `borderlessMenuLabelInset` and `roundedFieldTextInset` name those two
amounts, and everything that is not a bordered field is shifted right to meet
the field's text, which is the column the owner asked for: text against text,
the box edges allowed to hang left of it.

The shift goes that way round, and not the shorter way of pulling the boxes
left, because the gap between the label column and the content column is
`panelSpacing` — about 6pt at the default size — and pulling a box 6pt left sets
it against "Personality". Neither number is font-derived: both are properties of
the control style, so they stay constant while the panel scales.
A rule across both columns. `Divider()` on its own would sit inside the
label column and draw a stub.
MARK: - Actions

Takes this character off the desktop. The window goes with her, so there
is nothing left here to report into — the delegate owns what happens
next.
Re-encoded to PNG so the stored file matches its name whatever the
user picked, and so an unreadable file is reported now rather than
showing up later as a blank character.
The editable copy of a profile. The menus need a plain choice plus its free
text, which the model's enums deliberately don't carry separately.
An unparseable exact age falls back to a life stage rather than refusing
the save — the field is a convenience, not a gate.


## ProjectPicker.swift

Adds a project by having the user physically choose the folder in a system
panel. The path therefore always comes from an explicit human action — it is
never derived from typed text — which is also what a sandboxed build would
require later.
`runModal()` shows the panel but does not bring the app forward, and
this app is usually not the active one when the button is pressed: the
chat is a non-activating panel, so clicking Projects → Add Project
never made it active. An open panel belonging to an inactive app is
not key — the folder list stops answering clicks, and the first click
is spent activating instead of selecting. That is the "sometimes":
it worked right after the chat opened, because opening it activates.
Esc has to cancel this dialog, not the chat window behind it.


## SavePanel.swift

Hands a finished file to the person through the system save panel.

The mirror of `AttachmentPicker`, and the same rule read backwards: the file
goes exactly where an explicit human choice puts it, never to a path the app
picked. That is also what makes this safe without a permission card — the
panel *is* the consent, and a sandboxed build gets the write grant from it
rather than from anything we could grant ourselves.
Where the panel opens. Downloads is where a file that arrived from
somewhere else belongs, and it is the one folder people empty without
thinking about it — the Desktop, the other candidate, is somewhere
things go to stay.
Copies `file` wherever the person says. Returns where it landed, or
nothing if they cancelled.

**Copies rather than moves.** The conversation still refers to the file
in the working folder — "add a column to that spreadsheet" has to keep
working after they save it — and a save that quietly emptied the folder
the assistant is standing in would break the next turn.
The panel already asked about replacing, so an existing file here
is one the person chose to overwrite — but `copyItem` refuses
rather than replacing, so the old one goes first.
Writes text the app made up itself — the command window's results
strip — wherever the person says.

A write, not the copy above: there is no file yet. The panel is still
the consent, so this needs no permission card for the same reason.
The panel itself, asked the same way for both kinds of save.
A panel owned by an inactive app is not key and ignores clicks until
something activates the app — the same reason `AttachmentPicker`,
`ProjectPicker` and `ImagePicker` all do this. The character's window
never takes focus on its own, so this app is very often the inactive
one when a button in it is pressed.
Says so when the copy fails. Rare — the panel has already settled the
permission and the folder — but a Save button that does nothing at all
is the worst of the possible outcomes.


## SpeechBubbleShape.swift

A comic/manga-style speech bubble: a single continuous outline — rounded
rectangle body plus a curved, tapered tail — so the tail reads as part of
the bubble rather than a shape pasted on top.

`isMirrored` flips the shape horizontally so the tail can switch from the
left side to the right side as the bubble is repositioned to stay
on-screen. `isFlippedVertically` flips it so the tail points up from the
top edge instead of down from the bottom, for when the bubble has to sit
below the character instead of above it. Both keep the tail's base
anchored at the same fraction of the edge, so it always aligns with the
character regardless of which side/orientation is chosen.
Shared so layout code can reserve exactly this much room for the tail.
The drawn tail stops slightly short of the reserved strip so the tip
hovers next to the character instead of poking into it.
How far along the tail-bearing edge the tail's base is centred, in
points from the near corner — an absolute distance, not a fraction of
the width. A fraction moved the tail into the middle of the bubble as it
was widened, dragging the tip away from the character; a fixed distance
leaves the tip where it is and grows the bubble out to the other side.
How far the tip drifts sideways from the base, giving the long
diagonal comic-tail slant that points toward the character (which the
window layout aligns near the 0.22 width fraction).
Where the tail tip lands, in points from the bubble's leading edge, for
the un-mirrored shape. Window placement uses this to line the tip up with
the character instead of duplicating the geometry as a magic number.
Independent of the width, which is the point: resizing the bubble must
not move the tip.
Right side of the tail: gentle concave curve down to the tip.
Left side of the tail: smooth convex curve back up to the bubble.


## StatusBarController.swift

Gives the accessory app a real, native presence: a menu bar icon whose menu
reaches every character, the usage figures, the version, and — crucially —
a normal way to quit. Without a Dock icon or main menu, this is the standard
macOS control surface for a floating companion.

This type decides nothing. What the menu contains is `statusBarMenu(...)` in
`SecretaryCore`, where it is a value with tests; here it is turned into
`NSMenuItem`s and the clicks are handed back as actions. The split is the
charter's rule about `AISecretaryApp` being invisible to coverage, applied
to the one part of the app that was entirely decision and entirely untested.
Read fresh every time the menu opens rather than kept in step with every
change. A menu only has to be right at the moment it is shown, and the
things it lists — conversations, pinned panes, whether a character is
showing — all change from elsewhere.
Retained so the menu items' target isn't deallocated.
Not `perform(_:)`: `NSObject` already has one — `performSelector:`
— so `#selector(Target.perform(_:))` resolves to *that*, every row
in the menu goes dead, and nothing crashes or warns. Cost half an
hour of clicking a menu that drew perfectly and did nothing.
macOS 26 draws an ⓘ beside anything it recognises as an About
command. Nothing here asked for it, and one icon in a menu of plain
rows reserves an icon column that indents every other title — so the
glyph is refused on every row, at every level.

An empty image rather than `nil`: `nil` means "decide for me", which
is how the ⓘ arrived.
Last, and after the submenu: AppKit re-enables a parent when it is
given one, and `isEnabled` is how an empty Chat History is greyed.
Set before, it would be undone.
Actions are enums, and `representedObject` is `Any?` — which an enum
with associated values cannot cross as itself under the Objective-C
bridge without being boxed.
Objective-C selector target. `StatusBarController` isn't an `NSObject`, so
this thin class receives the menu actions and forwards them.
Only the root: a submenu's contents were built with its parent a
moment ago and rebuilding them here would replace the items
AppKit is in the middle of showing.


## ThemeColors.swift

The one place a `ThemeColor` becomes something AppKit or SwiftUI can draw.

The palette is components rather than `Color` so the test bundle can measure
it — `AISecretaryApp` is never linked into it, so a colour decided here
could not be checked at all. This file is the conversion and nothing else:
it makes no choices, so there is nothing in it to test.
Explicitly sRGB. The default `Color(red:green:blue:)` is device RGB,
which is not the space the contrast numbers were computed in.
The same colour for the parts of a window SwiftUI does not paint — the
title bar, and the ground behind a hosting view.

Built from the stored sRGB components rather than from a system colour,
and that is load-bearing: a dynamic `NSColor` resolves against the
window's effective appearance, and resolving is how the system's
light/dark setting gets back in after a character has chosen otherwise.
How the palette reaches a view that isn't handed the `Appearance` object.

The environment rather than a parameter threaded down: the colours are the
same for every view in a window, and a parameter on each of a dozen small
structs is a dozen chances to forget one — which shows up as a single row
still lit by the system's setting while everything around it is not.

Every window root sets it. The default is only there because
`EnvironmentKey` requires one.
Paints a window: the palette for everything inside it, an opaque ground,
and the default text and control tints so an unstyled `Text` added later
still comes from the theme.
What the window should ask AppKit for, so the caret, the scroller and
the selection tint are lit the same way as everything drawn around them.

The ground under an opened Settings/Profile/Projects/Skills box — one view
so the four boxes cannot drift apart. Solid `chipFill` normally; in glass
mode the same colour as a `glassEffect` tint, which keeps the surface
defined enough for the small `mutedText` hints while letting the desktop
glow through. Tinted, not plain `.regular`: these boxes carry the smallest
text in the app, and an untinted pane's brightness is whatever the
wallpaper says it is.


## UsageWindow.swift

Who is on the desktop, for the one usage window.

Observable rather than a snapshot taken when the window opens: the window is
built once and kept, so a character created while it is up would otherwise
never appear in it.
A real titled window rather than a panel inside the chat, for two reasons:
the chat bubble is anchored to the character and closing it must not take
the figures away, and a number you are watching should be somewhere you can
park it. It floats above other apps like the rest of this app's windows, and
it follows the conversation live — `Secretary.sessionUsage` is observed, so a
window opened before the first question fills in as answers arrive.
Whose look the contents were built from. This window belongs to the app
rather than to a character, so it borrows one — and has to notice when
the character it borrowed from is no longer the one being worked with.
Puts this window in one character's look and keeps it there.

Two things have to move together and were split before, which showed as
a window wearing half of each: the AppKit control appearance, which a
SwiftUI body cannot return, and the hosting view, which observes the
`Appearance` it was built with and so never notices a *different*
character being focused. Re-lighting one without rebuilding the other
gave a light title bar over a dark body.

Cheap to call often: the rebuild only happens when the character has
actually changed.
Nothing in this app takes focus by itself, so without activating, the
window opens behind whatever is in front and reads as "nothing
happened" — the same trap the About window and the pickers hit.
Resizable as well: the content is scrolled, but someone with room
on screen should be able to see all of it at once.
Left restorable, AppKit can reopen it on launch on its own; what is on
screen is this app's decision. Same rule as the character panel.
Closing by the window's own button goes through here, not `close()`.
The contents. Deliberately plain: four counts, a context bar and the caveat
about what the dollar figure is.
This window sets the palette rather than inheriting one: it is a root,
not a view inside the chat panel.
Re-read every half minute so the relative times move on their own. The
figures behind them are polled far less often; this only re-renders the
words, which would otherwise sit at "Resets in 18 min" for an hour.
Which sections are open. Held here rather than persisted: the window is
built once and kept, so a fold survives closing and reopening within a
run, which is as long as anyone is watching a live gauge.
Everybody's figures added together. The window is at the root of the
menu because the bill is the machine's, but each character keeps her own
session, so the total is made here rather than read off one of them.
Who spent what, shown only when there is more than one of them —
a breakdown of one row is just the total again.
Scrolled, because the content grows: plan limits, however many weekly
windows the account has, the activity block, and the token table. A
fixed height that fits today gets cut off the next time Claude Code
adds a line — which it did, and the last row went off the bottom.
Named for what it now adds up. It was "This conversation" while
there was one; with several characters the figures are every
live session together, and calling that a conversation would be
a number that matches nothing on screen.
What is left of the subscription's allowance, laid out like the Usage
panel in the Claude app — session first, then the weekly windows — since
that is the arrangement the user already reads.
A heading that folds what is under it. The whole row is the target, not
just the chevron — a 10pt triangle is a poor thing to have to hit, and
the title is right there.
How much work went through this machine in a stretch, and what shape it
had. The counts answer "why is the bar there"; the notes say what kind of
work drove it.
One limit: name, bar, percentage, and when it rolls over. A model-specific
window at zero says so in words rather than showing an empty bar and a
reset time it does not have.
The one figure worth watching while working: how close this conversation
is to filling the model's context.
Label left, number hard against the right edge — a `Grid` sizes itself to
its contents, so its right column floated in the middle of the window
instead of lining up with the percentages above it.


## VendorStatus.swift

One character's maker: which one she works through, where its tool is,
whether it can be reached, and what it can run.

Per character, because the panel that chooses it is her Profile. The app-wide
search for Claude Code stays in `BackendStatus` — that question really is the
machine's, and asking it once is the whole point of the shared detector.

Decides nothing itself. Which of the four connection states applies is
`vendorConnection`'s answer, in a library target the tests can see; this
gathers the two inputs and applies it.
Where Claude Code was found, which is the machine's answer rather than
this character's — so it is read from the shared search instead of
repeating it per character.
Reads and writes the character's chosen model, so a model that belongs to
the maker she just left can be dropped. Closures rather than the whole
orchestrator: this needs two questions answered, not a collaborator.
Whether a real turn is running. The warm-up must not queue behind the
person's own question on the same model — both come back slower than if
neither had run.
Where the next turn would run. The warm-up has to use it, or it prefills
a prompt no real turn will send.
What has already been paid for this run. Not persisted: the cache it
warms lives in whatever is serving the model, and that does not survive
a restart either.
What the model picker should offer. Discovered for a maker whose list
belongs to the machine, and the maker's own fixed list otherwise.
What the user typed, or empty for "look in the usual places".
Switches maker. Saved and applied immediately, like the model and effort
rows beside it — the fields that wait for Save are the ones describing
who she is, not what she runs on.
The Test button, and Return in the path field. Both do the same thing:
take what is in the box, keep it, and go and look.
A chosen model belongs to the maker that offered it. Whether it
survives is decided by `modelSurviving`, in a library target the tests
can see; this only applies the answer.
Asks whether the maker can be reached, then hands the backend the tool it
found — so the next turn runs on what the row is reporting, rather than
on whatever was set up at launch.
Reads the maker's system prompt into the model's cache now, so the
person's first question doesn't pay for it.

Whether it is worth doing is `shouldWarmUp`'s answer, in a library target
the tests can see. Detached and never awaited: this takes minutes on a
local model, and nothing on screen should wait for it.
Marked before it finishes, on purpose: two panel openings a second
apart would otherwise both start one, and the second would sit behind
the first on the same model for no gain.
Off the main actor: checking a path means running the tool to ask its
version, and that is a process launch.
The shared search already ran, or is still running — `nil` is
"looking", which is why it is not treated as "missing".


## main.swift

Top-level startup runs on the main thread; assert that to the compiler so the
@MainActor AppDelegate can be constructed here.
An agent app draws no menu bar, but NSApplication still dispatches
command-key equivalents through mainMenu — this is what makes ⌘Q (and the
editing shortcuts in the chat field) work. See AppMenu.
The delegate is the target for ⌘+/⌘−/⌘H and About, and is retained by
the application.

