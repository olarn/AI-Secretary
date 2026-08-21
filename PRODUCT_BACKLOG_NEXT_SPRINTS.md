# Product Backlog — Next Sprints

งานของ sprint ถัดๆ ไป ยังไม่เริ่ม

## Sprint 23: Support OpenCode 
- [ ] รองรับการทำงานกับ OpenCode (local AI)
- [ ] ใน Profile, เพิ่ม choice ให้เลือกค่าย AI (ตอนนี้จะมีแค่ Claude กับ OpenCode) 
- [ ] เมื่อเลือก OpenCode จะมี config ของ OpenCode เพิ่มขึ้นมา คือ 
  - CLI Path (user กรอกเอง)
  - ส่วน model และ effor ก็เหมือนเดิม ถ้า AI ค่ายนั้นไม่รองรับ effort ก็ hide effort config ไป
  - มีปุ่ม test หลัง CLI Path text box เพื่อลอง call AI ตาม config ได้ 

## Sprint 24: Support Codex
- [ ] รองรับการทำงานกับ ChatGPT Codex
- [ ] ใน Profile, เพิ่ม choice ให้เลือกค่าย AI (ตอนนี้จะมีแค่ Claude Coed, OpenCode, ChatGPT Codex) 
- [ ] เมื่อ config เปลี่ยน app จะ auto discovery Codex ในเครื่อง การแสดงผล success/error เหมือน Sprint 22

## Sprint 25: Support Gemini CLI 

## Sprint 99: Voice
- [ ] Push-to-talk or explicit voice activation.
- [ ] Speech-to-text, text-to-speech, interruption behavior, and privacy controls.
- [ ] Voice must follow the same approval and auditing model as chat.
