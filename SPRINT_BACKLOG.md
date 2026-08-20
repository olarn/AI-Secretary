# Sprint Backlog

งานของ sprint ที่กำลังทำอยู่ ติ๊กแล้วคือ ship แล้ว

Sprint ที่จบแล้ว บันทึกทุกอย่างอยู่ใน `PRODUCT_BACKLOG.md`:

| หัวข้อใน `PRODUCT_BACKLOG.md` | เวอร์ชัน |
| --- | --- |
| Sprint 14-1 / 14-2 — Character คุยกันเอง และส่งงานให้กันได้ | v0.14.229–246 |
| Sprint 14.3 — ปิดโดยไม่มีโค้ดใหม่ | — |
| Sprint 14.4 — ตัวละครหายใจตอนคิด | v0.14.259–260 |
| Sprint 15 — permission ที่จำได้ข้าม session | v0.15.269–270 |
| Sprint 15.2 — ร้อยแก้วไม่ถูกอ่านเป็นคำสั่ง git | v0.15.272–273 |
| Sprint 16 — classifier หลบทางให้ agent | v0.16.275 |
| Sprint 17 — เลิกไล่เก็บ keyword ยก hand-off ให้โมเดล | v0.17.276 |
| Sprint 18-1 — sub-agent ไม่เงียบอีกต่อไป | v0.18.281–282 |
| Sprint 18-2 — ข้อความที่ต่อคิวไว้ ค้างตลอดกาล | v0.18.283 |
| Sprint 18-3 — ตัวเลือกที่สาม: ยกงานให้ตัวที่ว่าง | v0.18.284 |
| Sprint 18-4 — model ที่ตั้งให้ตัวละคร จำข้ามการเปิดแอป | v0.18.286 |
| Sprint 19 — notification เมื่องานเสร็จ คลิกแล้วเปิดแชทของตัวที่ส่ง | v0.19.288–290 |
| Sprint 20 — Command window: สั่งงานทุก character พร้อมกัน | v0.20.301–308 |
| Sprint 20.1 — เก็บงาน command box และ default character | v0.20.313 |
| Sprint 21 — Liquid Glass Theme (#5 ยังรอเจ้าของตัดสินใจ) | v0.21.319–323 |

**เลขสปรินต์เป็นของจริงที่นี่ที่เดียว** และตั้งแต่ 2026-08-18 ทุกหัวข้อใน
`PRODUCT_BACKLOG_NEXT_SPRINTS.md` มีเลขจริงหมดแล้ว (20–24) ไม่มี `xxx`/`yyy`/`zzz`/`zzzz`
เหลืออยู่ — เลขเรียงตามลำดับที่จะลงมือทำ เพราะนั่นคือความหมายของเลขหลักกลางใน version

## Sprint 21.2 - improvement

ห้าข้อครึ่งจบแล้ว บันทึกอยู่ใน `PRODUCT_BACKLOG.md` (v0.21.326–329) หัวข้อนี้ยังไม่ย้าย
เพราะข้อ 2 เหลืออีกครึ่ง ที่ต้องให้เจ้าของตัดสินใจก่อน

- [x] ตอนขยายฟอนต์ในคอม Box ฟอนต์จะขยายแค่ input text แต่ไม่ขยายในส่วนอื่นๆ
- [x] ปัญหา ตอนที่สั่งงานผ่าน command, ทุก character บอกว่าไม่มีสิทธิ์เขียนไฟล์ แล้วก็จะมี 2 เหตุการณ์ คือ
  - รอสักพัก ก็เขียนได้ หรือ
  - ค้างไปเลย

  แก้แล้ว: `agentPermissionNote` เคยจบด้วย "writing or running commands will be
  refused" โมเดลเลยไม่ยอมเรียก tool แล้วตอบเป็นร้อยแก้วว่าไม่มีสิทธิ์ — ไม่มี tool call
  ก็ไม่มี refusal ไม่มี refusal ก็ไม่มีการ์ด งานเลยหยุดสนิท ส่วน "รอสักพักก็เขียนได้"
  คือ standing grant ที่ widen ให้เงียบ ๆ ตามที่ Sprint 15 ตั้งใจ ไม่ใช่บั๊ก
- [ ] **ที่เหลือของข้อบน — ต้องให้เจ้าของตัดสินใจ** Claude Code ปฏิเสธ path นอก working
  directory ด้วยข้อความ *"ls in '…' was blocked. For security, Claude Code may only
  list files in the allowed working directories for this session"* ซึ่งไม่ตรงกับ
  `refusalPhrases` เลยไม่มีการ์ดขึ้น และต่อให้ขึ้นก็แก้ไม่ได้ เพราะสิ่งที่ขาดคือ `--add-dir`
  ของโฟลเดอร์นั้น ไม่ใช่สิทธิ์ของ tool `ls` — ให้การ์ดที่กด allow แล้วยังทำไม่ได้ แย่กว่าไม่มี
  ต้องมีทางขยาย *directory* ซึ่งเป็นการขยายขอบเขต filesystem ที่ charter ให้ถามก่อน
  (เจอตอน drive 2026-08-20)
- [x] **สาเหตุที่สามของข้อบน (เจอ 2026-08-20 ตอนสั่ง 4 ตัวพร้อมกัน)** `CLAUDE.md` ของ
  project เขียนว่า "ทุกคน จะขอ write permission ก่อน" อาเนียเลยขอเป็น *คำพูด* แล้วรอ —
  ซึ่งไม่มีใครตอบได้ เพราะทางเดียวที่คำถามจะถึงคนใช้คือเรียก tool แล้วโดนปฏิเสธ
  แก้สองชั้น: prompt บอกตรง ๆ ว่า "ขอ" ในแอปนี้แปลว่าเรียก tool, และแอปเองแก้ deadlock
  ให้ (ตอบกลับหนึ่งเทิร์นเมื่อ ```blocked บอกว่าขาด permission) — ไม่ให้สิทธิ์อะไรทั้งนั้น
  แค่บอกว่ารอไปก็ไม่มีใครมา (v0.21.331)
- [x] ปัญหา ตอนที่สั่งงานผ่าน command, ใน instruction บอกว่า ให้ monitor ถ้ามี file ให้ทำตาม instruction ที่ให้ไว้เลย แต่หลังจากที่ character monitor และ user เพิ่มไฟล์ลงไปที่ folder ที่กำหนด character แค่ report เท่านั้นว่ามี file มาใหมม่ แต่ไม่ทำตาม instruction เหมือนไม่ได้จำว่าต้องทำอะไร
- [x] ตอนที่สั่งงานผ่าน command, เวลา character ขอ permission อยากให้ส่งกลับมาขอที่ command session ให้ user approve แล้วส่งกลับไป
- [x] เพิ่ม feature ใน command window - ในกล่องผลลัพธ์ ตอนที่ expand ออกมา
  - มี Save ข้างซ้ายปุ่ม clear เพื่อเปิด save dialog และ save text ลง file ได้ (default เป็น .md)
  - มี icon copy เพื่อ copy text ลง clipboard ได้ - อยู่ถัดจากปุ่ม save
- [x] UI ทั้งหมด ให้เป็นภาษาอังกฤษ (ตอนนี้ไทยปนอังกฤษ)
- [x] เปลี่ยนลำดับปุ่มในกล่องผลลัพธ์เป็น copy (icon), Save, Clear (v0.21.331)
- [x] เพิ่มเวลาที่ได้รับ message หลังชื่อ character ในกล่อง Result (v0.21.333)
- [x] **4 character พร้อมกันช้ากว่า session เดียวมาก** — วัดแล้ว: main thread ว่าง 80%,
  และ `claude -p` 4 ตัวพร้อมกันนอกแอปเร็วปกติ (6.1s vs 6.1–7.4s) ตัวการคือ blockของ
  "ใครอยู่บนเดสก์ท็อปบ้าง" อยู่ใน `--append-system-prompt` ซึ่งเป็น launch flag และเป็น
  ส่วนหนึ่งของ `WarmProcessKey` — พอสถานะเพื่อน (busy / project ที่เปิด) เปลี่ยน
  warm process ก็ถูกฆ่าแล้วเปิดใหม่แทบทุกเทิร์น (วัดได้: 4 process เหลือรอด 1)
  แก้โดยย้ายส่วนที่เปลี่ยนไปอยู่ในข้อความของเทิร์นแทน — วัดหลังแก้: 3 เทิร์นติด
  process เดิมครบ 4 ตัว, cold start = 0 (v0.21.333)
- [x] พิมพ์ใน chat box แล้วหน่วง — วัดแล้ว: ทุกครั้งที่กดปุ่ม `ChatPanelView.body` ถูก
  ประเมินใหม่ทั้งก้อน แล้ว `ForEach` ของ transcript สร้างทุกข้อความใหม่หมด
  (1130 จาก ~1910 layout samples อยู่ใต้ `ForEachChild.updateValue()` ข้างล่างเป็น
  libThaiTokenizer / liblangid / CoreText) แก้ด้วย `TranscriptRows` ที่เป็น Equatable
  ข้ามการ rebuild เมื่อข้อความและหน้าตาไม่เปลี่ยน (v0.21.334) **ยังไม่ได้ลองในแอปจริง
  ตามที่เจ้าของบอกว่าไม่ต้อง test — อยากให้เจ้าของลองพิมพ์ในแชทยาว ๆ ดูสักครั้ง**
- [ ] theme ของ pinned window ให้ตามของ character — อ่านโค้ดแล้วสายไฟถูกอยู่แล้ว
  (`InfoWindows(appearance:)` ต่อ per character, `panel.appearance` มาจาก palette
  ของตัวละคร, ตัว view ก็ `.themedWindow(theme)`) ยังหาจุดพลาดไม่เจอจากการอ่านโค้ด
  และรอบนี้ไม่ได้ลองในแอป — ต้องถามเจ้าของว่าเห็นเป็นธีมอะไรแทน (ระบบ? ตัวละครอื่น?)
