# Product Backlog — AI Desktop Companion / AI Secretary

Feature list by sprint, extracted out of `CLAUDE.md` so the charter (architecture,
principles, engineering rules) stays separate from the backlog (what's built vs.
what's left). Checked items are shipped; unchecked items are still open.

The sprint digit in `AppVersion.swift` (`major.sprint.change`) is **not** derived
from anything in this file — the highest heading here has never been the current
sprint. It is stated once, in `CLAUDE.md` → Engineering expectations. A copy kept
here said **9** while the charter said **10**, so the copy is gone rather than
corrected.

## v0.23.365 — ขอ write permission ซ้ำๆ ทั้งที่กด Always ไปแล้ว และกดไม่ได้เพราะไม่มี box

เจ้าของรายงานจาก project Second-Brain: Miku ขอสิทธิ์เขียนไฟล์ใหม่ทุกครั้งทั้งที่เคยตอบ
Always ไปแล้ว และตอนถามก็ไม่มี card ขึ้นมาให้กด ได้แต่พูดว่ารออนุญาตอยู่ เรื่องนี้ถูก
"แก้" มาแล้วอย่างน้อยสี่รอบ (`9195bfe`, `6cb1ab5`, `9fa4824`, `19cfac8`, `7c2b73f`)
ทุกครั้งแก้ด้วยการสอนให้แอปรู้จักกำแพงอีกแบบหนึ่ง — แต่กำแพงไม่ใช่ปัญหา

**Grant ไม่ได้หาย** `permissions-<miku>.json` มี `(901DA562, claude.code, localWrite)`
และ `projects-<miku>.json` มี Second-Brain ใต้ id นั้นจริง มันตรงกันอยู่แล้ว
เป็นบั๊กคนละตัวสองตัวที่ทับกันจนอ่านเป็นเรื่องเดียว

**อาการที่ 1 — ถามทุกครั้ง** `isNew = !rules.allSatisfy(sessionAgentTools.contains)`
กั้นการอ่าน grant ไว้ และ rule ของการเขียนไฟล์คือชื่อ tool เปล่าๆ (`"Write"`) การเขียน
ครั้งแรกของบทสนทนาใส่ `Write` ลง `sessionAgentTools` ฉะนั้น**การเขียนครั้งที่สองเป็นต้นไป
ข้ามการอ่าน grant ทั้งหมดแล้วขึ้น card ทันที** ทั้งที่มี Always อยู่ในมือ เห็นในบันทึกของ
เจ้าของเอง: กด Always 16:43:32 แล้วไฟล์เดิมถูกถามซ้ำ 16:43:51 — 19 วินาทีถัดมา
`AgentSessionTests:667` เขียนยืนยันพฤติกรรมนี้ว่าถูกต้อง ซึ่งเป็นเหตุผลที่สี่รอบที่ผ่านมา
ไม่มีใครแตะมัน

**อาการที่ 2 — ไม่มี box** ทางกู้สองทางวิ่งชนกัน `finishChat` เอา nudge ของ `BlockedBlock`
ใส่คิวแล้ว drain คิวตอนออกจากฟังก์ชัน (`defer`) เทิร์นใหม่จึงเริ่มไปแล้วตอนที่ `complete`
เรียก `offerToWiden`; transition ของ retry ถูกปฏิเสธ (`log show` บันทึกไว้ที่
2026-08-22 20:37:38.273) แต่ `streamReply` ยังทำงานต่อ ใส่ bubble เปล่าแล้ว
`streamingTask?.cancel()` ฆ่าเทิร์นที่ nudge เพิ่งเริ่ม ผลคือ bubble ว่างสองอัน ตัวละคร
บอกว่ารออนุญาต และไม่มี card — สองอันนั้นคือ placeholder ของ stream ที่ถูกยกเลิก

### ที่แก้

- **`recoverFromRefusals` — ฟังก์ชันบริสุทธิ์ตัวเดียวที่ตัดสินใจ** ทางที่เคย `return`
  เงียบๆ สามทางใน `offerToWiden` กลายเป็น `.cannotHelp(...)` ที่ผู้เรียก**ต้อง**พูดออกมา
  การทำ card หายจึงเขียนออกมาไม่ได้อีก
- **brake ผูกกับ retry chain ไม่ใช่ทั้งบทสนทนา** `widenedThisChain` เก็บเฉพาะ rule ที่
  เพิ่งขยายให้ครั้งที่กำลัง retry อยู่ และล้างทันทีที่เทิร์นจบโดยไม่โดนปฏิเสธ — วงจร
  refused→widen→retry→refused ยังหมุนไม่ได้ แต่การเขียนครั้งที่สองไม่ถูกถามอีก
- **grant เป็น input ของ allowlist ไม่ใช่ตัวกู้หลังโดนปฏิเสธ** project ที่อนุมัติแล้วได้
  `Write`/`Edit`/`NotebookEdit` ตั้งแต่ต้นเทิร์น บทสนทนาใหม่จึงไม่ต้องเสียรอบ
  "โดนปฏิเสธก่อนแล้วค่อยขยาย" อีกเลย
- **retry ไม่เริ่มทับเทิร์นที่ยังวิ่งอยู่** `pendingRetry` เป็นช่องเดียว drain หลัง stream
  loop จบ ไม่ใช่คิวข้อความ (คิวนั้นวิ่งเข้า `beginTurn` ซึ่งเป็นทางของข้อความผู้ใช้)
- **folder ที่อยู่ใน project ไม่ใช่ "ที่อื่น"** เดิม card ขอเปิด folder เด้งกับ sub-folder
  ของ project ที่อนุมัติไปแล้ว ทำให้ Always หนึ่งครั้งกลายเป็น grant รายโฟลเดอร์
  ตอนนี้ Always ครั้งเดียวครอบทั้ง project และทุก sub-folder ใต้มัน (เจ้าของเลือกข้อ 1)
- **`classOf` — project grant ไม่ครอบสิ่งที่ charter สั่งให้ถาม** rule ของ shell ที่ถูก
  ปฏิเสธเคยกลายเป็น `.localWrite` เสมอ `rm`/`shred`/`dd`/`sudo` จึงจะถูกขยายให้เงียบๆ
  ใต้ grant ตอนนี้แยกเป็น `.destructive`, `.dependencyInstalling`, `.gitHistoryChanging`
  ซึ่ง `mayBeRemembered` ปฏิเสธทั้งสามคลาส — ถามทุกครั้งแม้อยู่ใน project ที่ตอบ Always
  แล้ว ส่วน `mkdir`/`mv` ยังเป็น `.localWrite` เพราะเป็นงานปกติของ vault
- **`scratchProject` มี id คงที่** และ `GrantSubject` ทำให้ "ไม่มี project เปิดอยู่" เป็น
  สถานะของตัวเอง — ไม่ไปอ่าน grant และไม่เสนอ Always แทนที่จะอ้างชื่อ project ปลอม

`AgentSessionTests:667` ถูกเขียนใหม่ให้ยืนยันกฎที่ถูกต้อง (rule เดิมโดนปฏิเสธซ้ำ**ใน
chain เดียวกัน**ยังต้องหยุดและบอกเหตุผล) — เป็น assertion เดียวที่แก้ ที่เหลือผ่านหมด
ไม่แตะ 1466 tests, 0 failures

### ที่ยังไม่ได้แก้ และรู้ตัว

`rm` ที่ถูก sandbox ของ Claude Code ปฏิเสธ ยังไม่ผ่าน `isPermissionRefusal` — ข้อความ
ปฏิเสธไม่ตรงวลีไหนเลย จึงไม่เกิด `DeniedTool` ไม่มีอะไรไปถึงชั้นตัดสินใจ และไม่มี card
ตัวละครได้แต่บอกเป็นคำพูดว่ารออนุญาต ขับเจอตอน 2026-08-22 21:47 อาการเดียวกับที่
รายงาน แต่คนละสาเหตุ และเป็นข้อที่ `6cb1ab5` บันทึกไว้แล้วว่ายังไม่เคยแก้

## Sprint 24: Support Codex
- [ ] รองรับการทำงานกับ ChatGPT Codex
- [ ] ใน Profile, เพิ่ม choice ให้เลือกค่าย AI (ตอนนี้จะมีแค่ Claude Coed, OpenCode, ChatGPT Codex) 
- [ ] เมื่อ config เปลี่ยน app จะ auto discovery Codex ในเครื่อง การแสดงผล success/error เหมือน Sprint 22

## Sprint 25: Support Gemini CLI 

## Sprint 26: Notification หน้าตาแบบ Discord (Communication Notification)

ตอนนี้ banner ขึ้น icon ของ app ทางซ้าย ส่วนรูปตัวละครไปอยู่ทางขวาในฐานะ attachment
ที่อยากได้คือแบบ Discord — รูปตัวละครเป็น icon ใหญ่ทางซ้าย และมี icon ของ app เล็กๆ
badge อยู่มุมขวาล่างของรูปนั้น

**ติดที่การเซ็นแอป ไม่ใช่ที่โค้ด** (ตรวจสอบแล้ว 2026-08-21): macOS ทำได้ผ่าน
Communication Notification (macOS 12+, `UNNotificationContent.updating(from:)` มีอยู่ใน
SDK จริง) แต่ต้องมี entitlement `com.apple.developer.usernotifications.communication`
ซึ่งเป็น restricted entitlement — ต้องมาจาก provisioning profile เท่านั้น และ
`codesign --sign -` (ad-hoc ที่ `scripts/package-app.sh` ใช้อยู่) พา entitlement แบบนี้ไปไม่ได้
`/Applications/Discord.app` มี entitlement ตัวนี้จริง ส่วน `AISecretary.app` ไม่มี entitlement เลยสักตัว
และเครื่องนี้ `security find-identity -v -p codesigning` ได้ `0 valid identities`

- [ ] **ข้อกำหนดก่อนเริ่ม:** มี Apple Developer account + provisioning profile ที่เปิด
      capability Communication Notifications — ถ้ายังไม่มี ข้อที่เหลือทำไม่ได้เลย
- [ ] แก้ `scripts/package-app.sh` ให้เซ็นด้วย identity จริงและ embed provisioning profile
      แทน ad-hoc signing
- [ ] donate `INSendMessageIntent` ต่อหนึ่งคำตอบ โดยให้ตัวละครเป็น `INPerson` ที่มี
      `INImage` เป็นรูป portrait ของเธอ (รูปเดียวกับที่ตอนนี้แนบไปทางขวา)
- [ ] เรียก `content.updating(from: intent)` ก่อน `UNUserNotificationCenter.add()` ใน
      `CompletionNotifier.post`
- [ ] แก้ comment ใน `CompletionNotifier.swift` ที่เขียนว่า icon ทางซ้าย
      "cannot be set per notification" — จริงเฉพาะตอนที่แอปไม่มี entitlement นี้
- [ ] ของแถมที่ได้มาด้วย: ตัวละครแต่ละคนจะมีแถวของตัวเองใน System Settings →
      Notifications และ allow-list ผ่าน Focus ได้เป็นรายตัวละคร

**ทางเลือกที่ไม่เอา:** วาด toast window เองจะได้รูป avatar โดยไม่ต้องมี entitlement
แต่ขัดกับการตัดสินใจที่บันทึกไว้แล้วใน `CompletionNotifier.swift` ("notification settings
ตาม macOS" — System Settings เป็น control surface เดียว) และ toast ที่วาดเองจะไม่เข้า
Notification Center และไม่เคารพ Focus

## Sprint 99: Voice
- [ ] Push-to-talk or explicit voice activation.
- [ ] Speech-to-text, text-to-speech, interruption behavior, and privacy controls.
- [ ] Voice must follow the same approval and auditing model as chat.
