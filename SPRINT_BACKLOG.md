# Sprint Backlog

- งานของ sprint ที่กำลังทำอยู่ ติ๊กแล้วคือ ship แล้ว
- Sprint ที่จบแล้ว บันทึกทุกอย่างอยู่ใน `PRODUCT_BACKLOG.md`:

## Sprint 22: Re-architecture app to support multi-AI Vendor
current stage: ตอนนี้ app รองรับแค่ Claude Cowork ต่อไป app ต้อง support AI มากกว่า 1 ค่าย
- [ ] Re-architecture app เพื่อให้รอบรับ AI มากกว่า 1 ค่าย 
- [ ] โครงสร้างใหม่ รองรับการทำงานกับ Project ได้เหมือนเดิม
- [ ] สามารถ Recovery เมื่อเปลี่ยน config ได้ ว่า connect กับ Claude ได้ 
  - โดยจะมี checked icon เล็กๆ สีเขียวถ้า connect ได้ 
  - ถ้าไม่ได้ ก็ขึ้น mark x icon เล็กๆ สีแดง และบอก error message (เหมือน require field message ตาม web ทั่วไป)
- [ ] Makesure everything work just fine as before.