# Product Backlog — AI Desktop Companion / AI Secretary

Feature list by sprint, extracted out of `CLAUDE.md` so the charter (architecture,
principles, engineering rules) stays separate from the backlog (what's built vs.
what's left). Checked items are shipped; unchecked items are still open.

The sprint digit in `AppVersion.swift` (`major.sprint.change`) is **not** derived
from anything in this file — the highest heading here has never been the current
sprint. It is stated once, in `CLAUDE.md` → Engineering expectations. A copy kept
here said **9** while the charter said **10**, so the copy is gone rather than
corrected.

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
