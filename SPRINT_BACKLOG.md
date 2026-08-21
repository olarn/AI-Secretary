# Sprint Backlog

- งานของ sprint ที่กำลังทำอยู่ ติ๊กแล้วคือ ship แล้ว
- Sprint ที่จบแล้ว บันทึกทุกอย่างอยู่ใน `PRODUCT_BACKLOG.md`:

ยังไม่มี sprint ที่กำลังทำอยู่ — Sprint 22 ย้ายไป `PRODUCT_BACKLOG.md` แล้ว
รายการถัดไปอยู่ใน `PRODUCT_BACKLOG_NEXT_SPRINTS.md` (Sprint 23: Support OpenCode)

## Sprint 23: Support OpenCode 
- [ ] รองรับการทำงานกับ OpenCode (local AI)
- [ ] ใน Profile, เพิ่ม choice ให้เลือกค่าย AI (ตอนนี้จะมีแค่ Claude กับ OpenCode) 
- [ ] เมื่อเลือก OpenCode จะมี config ของ OpenCode เพิ่มขึ้นมา คือ 
  - CLI Path (user กรอกเอง)
  - ส่วน model และ effor ก็เหมือนเดิม ถ้า AI ค่ายนั้นไม่รองรับ effort ก็ hide effort config ไป
  - มีปุ่ม test หลัง CLI Path text box เพื่อลอง call AI ตาม config ได้ 