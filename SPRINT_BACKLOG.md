# Sprint Backlog

งานของ sprint ที่กำลังทำอยู่ ติ๊กแล้วคือ ship แล้ว

Sprint 14 จบทั้งสปรินต์ บันทึกทุกอย่างอยู่ใน `PRODUCT_BACKLOG.md`:

| หัวข้อใน `PRODUCT_BACKLOG.md` | เวอร์ชัน |
| --- | --- |
| Sprint 14-1 / 14-2 — Character คุยกันเอง และส่งงานให้กันได้ | v0.14.229–246 |
| Sprint 14.3 — ปิดโดยไม่มีโค้ดใหม่ | — |
| Sprint 14.4 — ตัวละครหายใจตอนคิด | v0.14.259–260 |

หัวข้อใน `PRODUCT_BACKLOG_NEXT_SPRINTS.md` ใช้เลขหลอก (`xxx`, `yyy`, `zzz`, `zzzz`)
เพราะเจ้าของยังไม่ได้ตัดสินว่าอันไหนเป็นสปรินต์ที่เท่าไร — **ที่นี่คือที่เดียวที่เลขสปรินต์เป็นของจริง**

## Sprint 15  ปรับเรื่อง permission
- [ ] ตอนนี้เวลาขึ้น session ใหม่ แต่อยู่ใน project เดิม AI จะขอ permission ใหม่เสมอ
- [ ]  อยากให้มี choice เพิ่ม คือ
  - [ ] ถ้าเป็นครั้งแรก การขอ permission จะมี Once, Always, Denine
  - [ ] ถ้าเลือก Always ให้จำลง memory file ของ project นั้นเลย เวลาขึ้น session ใหม่ให้ไปอ่าน memory ว่าset permission ไว้ยังไง
  - [ ] ถ้าเลือก once ก็จำใน memory ของ session นั้น (ปิด session นั้นไปก็หายไป)
  - [ ] การจำ permission จะอยู่ในขอบเขตของ project เท่านั้น ถ้ามีการ drag / drop file, folder เข้ามาใน chat แล้วไม่ได้อยู่ใน project ต้องถามเป็นครั้งๆ และจำแค่ session นั้นเท่านั้น
  - [ ] กฏ permission ใหม่จะไม่ override คำสั่งอันตรายที่เคยมีอยู่แล้ว ใน logic ของ code
