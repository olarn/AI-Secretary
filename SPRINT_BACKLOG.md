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
- [x] ตอนขยายฟอนต์ในคอม Box ฟอนต์จะขยายแค่ input text แต่ไม่ขยายในส่วนอื่นๆ
- [ ] ปัญหา ตอนที่สั่งงานผ่าน command, ทุก character บอกว่าไม่มีสิทธิ์เขียนไฟล์ แล้วก็จะมี 2 เหตุการณ์ คือ 
  - รอสักพัก ก็เขียนได้ หรือ
  - ค้างไปเลย
- [ ] ปัญหา ตอนที่สั่งงานผ่าน command, ใน instruction บอกว่า ให้ monitor ถ้ามี file ให้ทำตาม instruction ที่ให้ไว้เลย แต่หลังจากที่ character monitor และ user เพิ่มไฟล์ลงไปที่ folder ที่กำหนด character แค่ report เท่านั้นว่ามี file มาใหมม่ แต่ไม่ทำตาม instruction เหมือนไม่ได้จำว่าต้องทำอะไร
- [ ] ตอนที่สั่งงานผ่าน command, เวลา character ขอ permission อยากให้ส่งกลับมาขอที่ command session ให้ user approve แล้วส่งกลับไป
- [x] เพิ่ม feature ใน command window - ในกล่องผลลัพธ์ ตอนที่ expand ออกมา 
  - มี Save ข้างซ้ายปุ่ม clear เพื่อเปิด save dialog และ save text ลง file ได้ (default เป็น .md) 
  - มี icon copy เพื่อ copy text ลง clipboard ได้ - อยู่ถัดจากปุ่ม save
- [x] UI ทั้งหมด ให้เป็นภาษาอังกฤษ (ตอนนี้ไทยปนอังกฤษ)