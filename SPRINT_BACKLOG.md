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

**เลขสปรินต์เป็นของจริงที่นี่ที่เดียว** และตั้งแต่ 2026-08-18 ทุกหัวข้อใน
`PRODUCT_BACKLOG_NEXT_SPRINTS.md` มีเลขจริงหมดแล้ว (20–24) ไม่มี `xxx`/`yyy`/`zzz`/`zzzz`
เหลืออยู่ — เลขเรียงตามลำดับที่จะลงมือทำ เพราะนั่นคือความหมายของเลขหลักกลางใน version

---
## Sprint 20: User work with all AI Secretary in the same time
Requirement: ต้องการให้ user สั่งงานทุก character ทีเดียวพร้อมๆกัน แทนที่จะสั่งงานผ่าน 1 ตัว แล้วให้ตัวนั้นไปสั่งตัวอื่นๆอีกทอดหนึ่ง 
- [ ] เพิ่ม command window โดยที่ใน window จะมี 
  - chat box เหมือนกับใน chat window เป็น float แบบไม่มีขอบ (เหมือน Spotlight ของ Mac หรือ chat box ของ Claude desktop) และ drag ไปมาได้ 
  - เมื่อเปิดมา, cursor จะ focus ใน chat box เลย
  - มี chat box, ปุ่ม send ใช้ design และ behaviour เหมือน chatbox เดิม
  - มี list ของ available characters ที่ user เลือกได้ว่าจะสั่งใคร โดยแสดง ชื่อ characters เหนือ chat box 
  - user กด Ecs จะเป็นการซ่อน window, แต่ไม่ได้ปิด session
  - มีปุ่ม "จบการทำงาน" ถ้ามี session ของ character ไหนที่ทำงานกับ command ค้างอยู่ ก็จบปิด session ทั้งหมด
- [ ] การสั่งงาน 
  - ต้องมี (และเลือก) character ที่จะสั่งให้ทำงานอย่างน้อย 1 ตัว (ถ้าไม่เลือก จะมี Error message สีแดงใต้ box บอกว่าให้เลือกอย่างน้อย 1 ตัว)
  - สามารถสั่ง character แยกได้ เช่น เลือกไว้ 3 ตัว แต่สั่ง Miku ตัวเดียว ด้วยการระบุเป็นภาษาธรรมชาติ เช่น "Miku pin คำตอบล่าสุดไว้" เป็นตัน Miku จะทำงานตัวเดียวตามคำสั่ง แต่ Miku ต้องถูกอยู่ใน character list ที่ถูกเลือก
  - สามารถเพิ่มลด character ได้ตลอด ทุกตัวจะรับคำสั่งตอนที่ถูกเลือกเท่านั้น
- [ ] มีเมนู Show / Hide Command เพื่อเปิด/ซ่อน command window อยู่ระหว่าง New Character กับ Token Usage (มีเส้นคั่นด้วย) 
  - defaul position คือ middle screen เลือนตำแหน่งแล้วจำ position ได้
- [ ] สามารถ upload instruction ได้ (เป็น batch commands - drag/drop file) โดยใน file instruction สามาระระบุได้ด้วยว่าให้ใครทำอะไร 
- [ ] สามารถกำหนด role ได้ ว่า ใคร role อะไร, แต่ละ role ทำอะไร/ไม่ทำอะไร แล้ว character จะทำงานเองตาม role ที่กำหนด เช่น 
  - role เป็น 3 สี Miku=แดง, Pikachu=เหลือง, Ditto=น้ำเงิน
  - เมื่อไหร่ที่คำสั่งสัมพันธ์กับสีไหน สีนั้นจะนับเลขไว้ 
  - instruction จะเขียนใน chatbox เลยก็ได้ หรือจะเป็น file แล้ว drag/drop มาใส่ก็ได้
  - ถ้ามี instruction มากกว่า 1 file ก็เอามา merge กัน ถ้ามีลำดับ instruction ก็ให้ทำลำดับใน file แรกก่อน แล้วต่อทำใน file ถัดๆไป
  - ถ้าไม่ได้กำหนดใน instruction ว่าใครทำอะไร ให้ character แบ่งงานกันเองว่าใครจะทำอะไร
