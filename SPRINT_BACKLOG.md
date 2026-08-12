# Product Backlog — AI Desktop Companion / AI Secretary

Feature list by phase, extracted out of `CLAUDE.md` so the charter (architecture,
principles, engineering rules) stays separate from the backlog (what's built vs.
what's left). Checked items are shipped; unchecked items are still open.

The phase digit in `AppVersion.swift` (`major.phase.change`) is **not** derived
from anything in this file — the highest heading here has never been the current
phase. It is stated once, in `CLAUDE.md` → Engineering expectations. A copy kept
here said **9** while the charter said **10**, so the copy is gone rather than
corrected.

## Phase 12: ปรับ setting ให้อยู่ถูกที่ถูกทาง
- [ ] ย้าย App size จาก Profile -> Settings
- [ ] ย้าย Model, Effort จาก Settings -> Profile
- [ ] ย้าย Browser จาก Settings -> Project