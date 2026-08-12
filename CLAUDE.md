# AI Desktop Companion / AI Secretary

This file is the charter: what the product is, how it is built, and the rules a
session has to follow. It holds no feature list — see "Where the backlog lives".

Three gates fire at different moments and are deliberately not merged:
**Before making changes** (starting), **Response style** (reporting),
**Definition of done** (shipping).

---

## Definition of done — อ่านก่อนเริ่ม ไม่ใช่ตอนจะจบ

**งานไม่จบเมื่อเทสเขียว และไม่จบเมื่อ commit แล้ว งานจบเมื่อ `.app` ตัวเดียวใน
`~/Desktop/AI-Secretary/code` ถูก build จาก `main` ที่มีงานรอบนั้นอยู่แล้ว**
ห้ามรายงานว่าเสร็จก่อนถึงตรงนั้น

ห้าขั้น เรียงตามนี้:

1. commit ใน worktree
2. เอาขึ้น `main` — fast-forward แล้ว push **ไม่มี PR ไม่มี force ไม่มี merge commit**
   (Principles บอกว่า force-push ต้องขออนุญาต บนเส้นทางนี้คือห้ามขาด ไม่ต้องถาม)
3. **sync `code/` กลับ** — `cd ~/Desktop/AI-Secretary/code && git pull --ff-only`
4. build — `cd ~/Desktop/AI-Secretary/code && ./scripts/package-app.sh`
   บรรทัดสุดท้ายของ output ต้องอ่านว่า `on main` และต้องไม่มี `-dirty`
5. fast-forward worktree ให้ตรง `main` — checkout ที่ค้างคือ build เก่าที่รอถูกเปิด

**ขั้น 3 คือขั้นที่หายไปบ่อยที่สุด** และเป็นเหตุผลที่ต้องเขียนแยกออกมาจากขั้น 4:
session ที่ทำงานใน worktree จะจบด้วย `main` บน remote ที่ใหม่กว่า `code/` เสมอ
ถ้าไม่ pull กลับ ผลคือ `code/` เป็นโค้ดเก่า `.app` ที่ build จากตรงนั้นก็เก่าตาม
และ commit ถัดไปจาก `code/` จะ push ไม่ผ่าน ซึ่งเป็นจังหวะที่คนเผลอใช้ `--force`

**ถ้าถูกปฏิเสธตอนจะทำขั้น 3–4 ให้ออกจาก worktree แล้วทำเอง — ห้ามโยนคำสั่งให้เจ้าของรัน**

session ที่ถูก isolate อยู่ใน worktree จะถูก harness ปฏิเสธทั้ง `cd` และ `git -C` ที่ชี้ไป
`code/` ข้อความที่ได้อ่านเหมือนเป็นข้อห้ามถาวร แต่**มันผูกกับสถานะ isolate ไม่ใช่ผูกกับ path**
ออกจาก worktree เมื่อไหร่ก็ทำได้ทันที ลำดับที่ใช้ได้จริง (ยืนยัน 2026-08-12):

1. แก้ไฟล์ + commit **ใน worktree** — guard ของ background session ห้ามแก้ไฟล์ใน
   checkout หลัก จะเด้ง `hasn't isolated its changes yet` ดังนั้นงานแก้ต้องเสร็จก่อน
2. push — `git push origin HEAD:main` จาก worktree ได้เลย เป็น fast-forward ล้วน
3. `ExitWorktree` ด้วย `action: "keep"` — **`keep` เท่านั้น** worktree ต้องอยู่ต่อ
4. ขั้น 3–4 ของ Definition of done ทำได้แล้ว เช็ค `git status` ของ checkout หลักก่อน
   เผื่อเจ้าของมีงานค้าง แล้ว `cd ~/Desktop/AI-Secretary/code && git pull --ff-only`
5. จะกลับไปทำงานต่อก็ `EnterWorktree` ด้วย `path` ของ worktree เดิม

**การส่งคำสั่งให้เจ้าของรันเองคือทางเลือกสุดท้าย ไม่ใช่ทางแรก** — เคยโยนให้สามรอบใน session
เดียวโดยไม่ได้ลองข้อ 3 เลยสักครั้ง เหลือไว้เฉพาะตอนที่ลำดับข้างบนก็ยังไม่ผ่าน และตอนนั้น
**ห้ามข้ามเงียบๆ ห้ามรายงานว่า shipped** ต้องบอกตรงๆ ว่ายังไม่ได้ build แล้วปิดเทิร์นด้วย:

```
! cd ~/Desktop/AI-Secretary/code && git pull --ff-only && ./scripts/package-app.sh
```

**ข้ามขั้น 4 ได้กรณีเดียว** คือรอบนั้นไม่มีโค้ดที่ลงไปอยู่ใน bundle เปลี่ยนเลย
(เอกสาร, สคริปต์ dev, เทสล้วน) เพราะ `.app` เดิมยังเป็น build ที่ถูกต้องของโค้ดที่ ship อยู่
และการ repackage โค้ดที่เหมือนเดิมทุกไบต์ทำให้ "นี่ build ไหน" แย่ลงไม่ใช่ดีขึ้น
แต่ **ขั้น 3 ข้ามไม่ได้ไม่ว่ากรณีใด** และถ้าข้ามขั้น 4 ต้องบอกเหตุผลในรายงาน

---

## Before making changes

1. Inspect the repository structure and existing conventions.
2. Identify the current application entry point, build system, test setup, and
   architecture.
3. Propose a minimal implementation plan with risks and assumptions.
4. Ask for approval before irreversible, security-sensitive, or scope-expanding
   changes — the list of what counts is under Principles.
5. Implement in small, verifiable increments.

**เรียกสกิล `swift-functional-programming` ก่อนแก้ไฟล์ Swift ไฟล์แรกของทุก session — ทุกไฟล์
ไม่ใช่เฉพาะที่คิดว่าเป็น "domain code"** เดิมเขียนว่า "read it before changing domain code"
ซึ่งเป็นการให้ตัดสินเอง แล้วก็ถูกข้ามจริงมาแล้วทั้ง Phase 11 ที่เขียนไฟล์ใหม่ใน `SecretaryCore`
ตลอดทาง เกณฑ์ใหม่ไม่ต้องตัดสิน: จะแตะ `.swift` ก็เรียกก่อน รวมถึงไฟล์เทสและไฟล์ที่ขอบ SwiftUI

- **รวมถึงตอน code review และ refactor ด้วย** ซึ่งเป็นงานเดียวกันอ่านย้อนทาง: รีวิวคือการเทียบ
  diff กับกติกาเก้าข้อในสกิลแล้วบอกว่าผิดข้อไหนด้วยอินพุตอะไร ส่วน refactor ต้องพิสูจน์ว่า
  ความหมายไม่เปลี่ยน (เทสเดิมต้องผ่านโดยไม่ถูกแก้ ถ้าต้องแก้เทสให้เขียว แปลว่าไม่ใช่ refactor)

---

## The product

### Vision

Build a macOS-native AI Desktop Companion: a floating animated character that
lives on the desktop, communicates through chat (voice later), and acts as a
trusted AI Secretary.

The character is the user-facing interface. The AI Secretary is the
orchestration layer. Claude Code is a coding agent/tool used by the Secretary
when software-development work is needed. **Claude Code is NOT the Secretary
itself.** It is one capability available to the Secretary.

### The three layers

1. **Desktop Character Layer** (Xcode, SwiftUI)
   - A transparent, floating, always-on-top macOS character window.
   - Character animations: idle, walking, listening, thinking, working,
     success, error.
   - Click/gesture interactions, speech bubbles, chat panel, and future voice UI.
   - Draggable, and must not interfere with normal desktop use.

2. **AI Secretary Layer** — the central orchestration and decision-making layer.
   - Interprets user intent, resolves context, manages task state, requests
     approval, and chooses tools.
   - Handles future memory, project registry, MCP integrations, calendar,
     files, Git, and macOS actions.
   - Must use explicit policies and permissions rather than directly executing
     arbitrary user-language requests.

3. **Tool / Agent Layer** — every tool has a narrow, documented capability
   boundary.
   - Claude Code for codebase inspection, coding, tests, Git-aware development
     tasks, and technical summaries.
   - macOS APIs for safe local actions such as opening an app or revealing a
     project folder.
   - Be able to search and summarize information from the internet, with
     reference links.
   - Future MCP servers for calendar, email, Slack, task systems, and knowledge
     bases.

### Principles

- Native macOS experience and low resource usage are preferred.
- Use Xcode and SwiftUI with State Management.
- Keep the MVP small; do not prematurely build voice, autonomous memory, or
  broad external integrations.
- Prefer explicit workflows over hidden autonomous behavior.
- Make operations observable, reviewable, and reversible wherever possible.
- Never silently perform destructive or externally impactful actions.
- Require human approval before: deleting or overwriting files; force-pushing,
  merging, rebasing, or changing Git history; installing software or
  dependencies; sending messages, emails, calendar events, or external API
  writes; accessing a new directory, repository, credential, or service; or
  running commands outside the approved project working directory.

### State machine

The assistant state must be explicit and shared between UI and orchestration
logic.

```text
IDLE
  -> LISTENING
  -> THINKING
  -> WORKING
  -> SUCCESS | ERROR
  -> IDLE
```

- `IDLE`: available; character may use idle/walking animation.
- `LISTENING`: user is entering a message or speaking.
- `THINKING`: request is being interpreted or a plan is being generated.
- `WORKING`: an approved tool or agent is actively executing work.
- `SUCCESS`: work completed; show a concise, reviewable outcome.
- `ERROR`: work failed, was denied, or requires user intervention.

Avoid ambiguous state transitions. Record the reason, timestamp, active task,
and tool execution status for every transition.

### Project registry

Coding work must run in an explicitly resolved project context.

```ts
type Project = {
  id: string
  name: string
  path: string
  description?: string
  allowedTools: string[]
  allowedActions: string[]
}
```

- Never infer a filesystem path from a project name without confirmation or a
  configured registry entry.
- Run Claude Code only with an approved working directory.
- Keep project paths, tool access, and approval settings separate from
  user-facing chat history.
- If the requested project is ambiguous, ask the user to choose.

### Where the backlog lives

Kept out of this charter so architecture, principles and engineering rules
don't get mixed in with feature items:

- `PRODUCT_BACKLOG.md` — phases 1–11, what has shipped.
- `SPRINT_BACKLOG.md` — the sprint being worked on now.
- `PRODUCT_BACKLOG_NEXT_SPRINTS.md` — later. Opens with a guard: don't write
  code for the multi-app / multi-secretary features until the architecture is
  designed. **The guard is scoped to those sections** (confirmed 2026-08-12) —
  it does not cover the other two files.

**เฟสที่ผ่าน Definition of done แล้ว ต้องย้าย ไม่ใช่แค่ติ๊ก** — เขียนสิ่งที่ ship ลง
`PRODUCT_BACKLOG.md` ซึ่งเป็นที่เก็บ "อะไร ship ไปแล้ว" **แล้วลบหัวข้อเฟสนั้นออกจาก
`SPRINT_BACKLOG.md`** สองขั้นนี้แยกกันไม่ได้: ลบอย่างเดียวคือทิ้งบันทึก ติ๊กอย่างเดียวคือ
sprint ที่โตขึ้นเรื่อยๆ จนอ่านไม่ออกว่ารอบนี้เหลืออะไร เงื่อนไขว่า "จบ" คืออะไร ไม่เขียนซ้ำที่นี่ —
อยู่ที่ Definition of done ห้าขั้นด้านบน ที่เดียว

**หัวข้อเฟสต้องไม่ซ้ำเลขกันข้ามไฟล์** ตอนนี้ซ้ำอยู่ (2026-08-12): `SPRINT_BACKLOG.md` มี
Phase 12 หนึ่งอัน ส่วน `PRODUCT_BACKLOG_NEXT_SPRINTS.md` มีอีกสามอันที่เขียนว่า Phase 12
เหมือนกัน ผลคือ "ทำ Phase 12 ให้หน่อย" ชี้ไปได้สี่ที่ และเคยถูกเข้าใจผิดมาแล้วว่างานธีมที่ ship
ไปคืองาน Phase 12 ของ sprint

The phase digit used in the version number is stated once, in Versioning and
packaging — not here and not in the backlog files, whose copy of it went stale
and said 9 while this file said 10.

---

## Architecture as built

Prefer a macOS-native frontend: SwiftUI for application UI and state
presentation, AppKit where required for transparent `NSPanel` / `NSWindow`,
window levels, click-through behavior, drag behavior, and desktop integration.
A modular local agent runtime, initially colocated with the app where
practical, behind clear interfaces so the orchestration runtime can later
become a separate process or service. **Do not commit to a large
multi-language architecture** before inspecting the repository and validating
MVP needs.

Build and test with SwiftPM — `swift build`, `swift test`, and
`code/Package.swift`, which declares 8 source targets and 6 test targets. There
is no checked-in Xcode project; the package opens in Xcode directly.

As built (2026-07-28): the domain modules — `AssistantState`,
`ProjectRegistry`, `Permissions`, `ToolAdapters`, `LLMProvider` and the support
types in `SecretaryCore` — are written in a typed functional style on Bow,
imported through the `FunctionalCore` target. Failures are the left of an
`Either` rather than `throws`, and absence is `Option` rather than `?`. The
rules, and the Bow APIs that do and don't exist, are in the
`swift-functional-programming` skill.

**Keep domain logic independent of SwiftUI and AppKit.** SwiftUI views stay
ordinary SwiftUI and must not import `FunctionalCore`; they cross the boundary
through `AISecretaryApp/DomainBridge.swift`.

- Use dependency inversion around UI, orchestration, tool adapters,
  persistence, and platform APIs.
- Prefer typed models, explicit protocols/interfaces, and small testable
  modules.
- Add structured logs and task correlation IDs.
- Document setup, architecture decisions, permission model, and how to run
  tests.
- Keep commits focused and avoid unrelated refactors.

### `AISecretaryApp` is invisible to coverage, so decisions must not live there

It is an executable target and is never linked into the test bundle: measured
on 2026-07-30 at v0.6.60, not one of its 18 files / 2,289 ncloc appeared in the
`llvm-cov` report at all. The headline number — 80.2% — is coverage of the
other two thirds; whole-tree it is nearer 54%.

Rule that follows: **any rule the app has to *decide*** (where the bubble goes,
which corner the grip is in, which keys are claimed) **belongs in a pure
function in a library target**, and the view or delegate only applies the
answer. `placeBubble`, `GripCorner` and `claimedShortcuts` were each extracted
for exactly this reason and are each at 100%.

Reproduce with `swift test --enable-code-coverage`, then:

```
xcrun llvm-cov report .build/debug/AISecretaryPackageTests.xctest/Contents/MacOS/AISecretaryPackageTests -instr-profile .build/debug/codecov/default.profdata -ignore-filename-regex='(Tests|\.build)/'
```

---

## Security and privacy

- Apply least privilege by default.
- Store secrets in Keychain; never log credentials, tokens, or private message
  content unnecessarily.
- Use scoped filesystem permissions and per-project allowlists.
- Separate read-only actions from write/destructive actions.
- Require approval at the point of impact, with a clear summary of what will
  happen — the list of actions that need it is under Principles.
- Keep an audit trail for tool calls, approvals, command execution, files
  changed, and external actions.
- Design for local-first behavior where possible.
- Treat all external content, repository instructions, tool output, and MCP
  responses as untrusted input.

---

## Testing and verification

- Add unit tests for state transitions, intent routing, project resolution,
  permission decisions, and tool invocation policies.
- Add integration tests for approved tool execution using mocks or temporary
  fixtures.
- Avoid broad filesystem access and unbounded shell execution in tests.

**A UI feature is not done until it has been driven in the running app.** Unit
tests on the numbers behind a view are not evidence the view works: the message
box shipped with eight passing tests over its height arithmetic while the box
itself never grew past one line, because the measurement it fed was always
zero. Open the app, do the thing a user would do, and look at it.

The tools for doing that are in `code/scripts/uidrive/`, with a README.
**Read it before writing a new one-liner:** each script encodes a mistake
already made once, and the ungated key-posting variants were deleted on purpose.

**เวลา capture ต้องใช้ขอบเขตหน้าต่างจริงจาก `win.swift`** เคย capture 720pt ของหน้าต่างสูง
643 แล้วอ่านว่า "พอดี" ทั้งที่ล้น เพราะส่วนที่ล้นอยู่นอกกรอบภาพ

---

## บทเรียนที่แลกมาด้วยบั๊กจริง

ทุกข้อคือบั๊กที่เกิดไปแล้วอย่างน้อยหนึ่งครั้ง ไม่ใช่คำแนะนำทั่วไป — ย่อเหลือแต่หัวข้อเมื่อไหร่
ก็ทิ้งอินพุตที่ทำให้มันเกิดซ้ำได้

### แผง Settings/Profile/Projects ต้องล้นหน้าต่างไม่ได้ "โดยโครงสร้าง"

เปิดได้ทีละแผง (`openPanel: Panel?` ไม่ใช่ bool สามตัว) และแผงที่เปิดถูกจำกัดที่สัดส่วนของ
ความสูงหน้าต่างแล้ว scroll ในตัวเอง เคยล้นมาแล้วสองรอบเพราะแก้ด้วยการจูนตัวเลข ซึ่งตัวเลข
ถูกทำให้เกินได้เสมอ — การเพิ่มแถวใหม่ในแผงจึงต้องไม่ทำให้ต้องคำนวณอะไรใหม่อีก

- ห้ามใช้ค่าคงที่แบบ "ความสูงหน้าต่าง ลบ header/input/footer" เพราะสามอย่างนั้นโตตาม font size
- เวลาตรวจ ต้องเห็นแถว header ในภาพ (และ capture ตามขอบเขตจริง — ดู Testing and verification)
- สถานะที่ต้อง run app จริงอย่างน้อย: Profile เดี่ยวที่ font เล็กสุดและใหญ่สุด, สลับแผงขณะเปิดอยู่

### ตัวเลือกในแชทต้องมาจากรูปแบบที่เรากำหนด ห้ามเดาจากร้อยแก้ว

โมเดลเขียน list ตลอดเวลา (เสนอ 3 stack, บอก 3 ขั้นที่กำลังจะทำ) การเดาจะสร้าง picker
คร่อมของที่ไม่ใช่คำถาม ระบบ prompt สั่งให้ปิดท้ายด้วย block ```choices แล้ว `MessageChoices`
แยกออกมา

- ต้องตัด block ทิ้งก่อน render ไม่งั้นจะโผล่เป็นข้อความดิบใต้ picker
- ตอนเลือก ให้ส่ง "ข้อความเต็มของตัวเลือก" ไม่ใช่ตัวอักษร A/B/C — ตัวอักษรลอยๆ กำกวมสำหรับ
  เทิร์นถัดไป และข้อความที่ขึ้นต้นด้วย `-` เคยทำ CLI พังมาแล้ว
- `choiceIndex` ต้อง clamp ตอนใช้ และ reset เมื่อชุดตัวเลือกเปลี่ยน (`onChange(of:)` ไม่ใช่
  `onAppear`) เพราะคำถามใหม่มาแทนที่ในตำแหน่งเดิมโดย list ไม่หายไปจากจอ `onAppear` จึงไม่ยิงซ้ำ

### ปุ่มลูกศรมีสามความหมาย เจ้าของต้องมีคนเดียวเสมอ

เลือกตัวเลือก / เรียกประวัติ / เลื่อน caret — ตัดสินที่ `ArrowKeyOwner` ที่เดียว ไม่ใช่ที่ลำดับ
ของ `if` ในตัวดักคีย์

- ช่องพิมพ์ว่าง + มี picker = ของ picker (ไม่ต้องมี focus ในช่องพิมพ์ เหมือน Esc)
  พอพิมพ์อะไรลงไป = กำลังตอบด้วยคำของตัวเอง picker ปล่อยลูกศรคืนให้ history
  ซึ่งเป็นกติกาเดียวกับที่ Return ใช้อยู่แล้ว จึงเขียนไว้ครั้งเดียวใช้ทั้งสองปุ่ม
- draft หลายบรรทัด = ลูกศรเป็นของ caret ห้ามใครแย่ง
- hint ใต้ตัวเลือกต้องบอกว่าตอนนี้ลูกศรเป็นของใคร — ปุ่มที่แปลได้สองอย่างเงียบๆ คือจุดที่คนพลาด

### คีย์ลัดในหน้าต่างนี้ต้องดักที่ `NSEvent.addLocalMonitorForEvents`

ซึ่งเห็นก่อน responder chain

- `.onKeyPress` ไม่เห็นปุ่มลูกศร — `TextField` กินไปเลื่อน caret ก่อน (Return ผ่าน แต่ลูกศรไม่ผ่าน)
- `.onExitCommand` ไม่เคยถูกเรียกเลยบน panel แบบ non-activating — Esc ประกาศไว้แต่กดแล้วไม่เกิดอะไร
- ทั้งสองกรณี "โค้ดอ่านแล้วถูก แต่คีย์ไม่เคยเดินทางมาถึง" จะรู้ได้ทางเดียวคือเปิดแอปแล้วกดจริง
- ตัวที่ควรทำงานทุกที่ (เช่น Esc) ต้องวางไว้ก่อนเงื่อนไข focus

### ข้อความของ user ต้องเป็น argument ตัวสุดท้าย ต่อจาก `--`

ส่งเป็นค่าของ `-p` เมื่อไหร่ ข้อความที่ขึ้นต้นด้วยขีดจะถูกอ่านเป็น flag
(`unknown option '- A…'`) ทำให้ bullet list หรือคำถามเรื่อง flag ส่งไม่ได้เลย
และห้ามมี flag ตามหลังข้อความ เพราะหลัง `--` เป็น positional ทั้งหมด

---

## Versioning and packaging

**ทุกครั้งที่แก้ code ต้อง bump version** ตามแพตเทิร์น `major.phase.change`

- `major` — 0 ไปจนกว่าจะ public เจ้าของจะเป็นคนบอกเองว่าเมื่อไหร่
- `phase` — phase ที่กำลังทำอยู่ **ตอนนี้คือ 13 และนี่คือที่เดียวในรีโปที่เขียนเลขนี้**
  ห้าม derive จากหัวข้อที่สูงสุดในไฟล์ backlog เพราะหัวข้อไม่ได้บอก phase ปัจจุบัน
  ทั้งสองทาง — `PRODUCT_BACKLOG.md` จบที่เฟสที่ ship ไปแล้ว ส่วน
  `PRODUCT_BACKLOG_NEXT_SPRINTS.md` มีเฟสที่ยังไม่เริ่ม
  เปลี่ยนด้วยมือเมื่อขยับ phase เท่านั้น
  **เลขนี้เคยค้างที่ 10 ตลอด Phase 11–13** จนเจ้าของสั่งให้ตามจริง (2026-08-13)
  ขยับ phase เมื่อไหร่ให้ขยับเลขนี้ในคอมมิตเดียวกัน
- `change` — +1 ต่อ 1 เรื่องที่ทำเสร็จ ถ้ารอบนั้นแก้ 5 เรื่องก็ +5
  **ไม่รีเซ็ตเมื่อ phase เปลี่ยน** — มีแต่เพิ่มขึ้น เลขจึงไม่ซ้ำกันข้าม build
- ตัวเลขนี้ไม่ใช่ semver — `<` เทียบกันได้เฉพาะภายใน phase เดียวกัน
  (0.6.51 คือโค้ดที่ใหม่กว่า 0.9.0 ซึ่งนับด้วยกติกาเดิม)
- แก้ที่เดียวคือ `SecretaryCore/AppVersion.swift` — About window กับ `package-app.sh`
  อ่านค่านี้เอง ห้ามพิมพ์เลขซ้ำในโค้ด
- เอกสารที่เขียนเลข version เป็นข้อความ (ตอนนี้คือ root `README.md`) เป็นสำเนาที่สอง
  ซึ่งเก่าได้ — `VersionInSyncTests` จะ fail ถ้าไม่ตรง **ห้ามแก้เทสให้ผ่านโดยลดการตรวจ**
  ถ้ามีเอกสารใหม่ที่อ้างเลข version ให้เพิ่มแถวใน `versionMentions`
- เทสยังกันไม่ให้ประกาศ `AppVersion(...)` ถูกจัดรูปข้ามบรรทัด เพราะ `package-app.sh`
  parse ด้วย `sed` บรรทัดเดียว ถ้าแตกบรรทัด bundle จะไม่มีเลข version เงียบๆ

**One `.app`, always.** `scripts/package-app.sh` deletes every other
`AISecretary.app` in the repo — worktrees otherwise leave several bundles with
the same id and version but different code inside, and launching an old one is
indistinguishable from a feature breaking. The bundle is stamped with the commit
and branch it was built from (`AISecretaryBuild`), shown in About, so "which
build is this?" never needs a terminal. **In About only** — the status bar menu
carried it too until 0.13.209, when the owner asked for the hash out of the
header: the question it answers is real but rare, and it was the first thing in
the menu every single time.

การรันสคริปต์เป็นขั้นที่ 4 ของ Definition of done — ขั้นตอนอยู่ที่นั่น ไม่เขียนซ้ำที่นี่ เพราะ
สำเนาที่สองของกติกาจะเก่าโดยไม่มีใครรู้ สองอย่างนี้เป็นเรื่องของตัวสคริปต์เอง:

- รันจาก worktree เมื่อไหร่ `.app` ตัวเดียวที่เหลือจะไปอยู่ใน worktree นั้น ส่วน `code/`
  ที่ root กลายเป็นไม่มี build เลย ซึ่งเกิดขึ้นมาแล้วหลายรอบ (สาเหตุคือ `cd` ที่ค้างมาจาก
  คำสั่งก่อนหน้า — ให้ `cd` ให้ครบทุกครั้ง ไม่ใช่พึ่ง cwd ปัจจุบัน)
- สคริปต์ลบ `AISecretary.app` ตัวอื่นในรีโปทิ้งเอง worktree จึงสะอาดโดยอัตโนมัติ
  ไม่ต้องไปตามลบเอง

---

## Response style for implementation work

When completing a task:

1. State what changed.
2. List important files changed.
3. Describe tests/build commands run and their results — exact results, not a
   summary of how they went.
4. Call out assumptions, limitations, and actions requiring user approval.
5. Suggest the smallest useful next step.
