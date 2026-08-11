# Product Backlog — AI Desktop Companion / AI Secretary

Feature list by phase, extracted out of `CLAUDE.md` so the charter (architecture,
principles, engineering rules) stays separate from the backlog (what's built vs.
what's left). Checked items are shipped; unchecked items are still open.

The current phase for version-bumping purposes (`AppVersion.swift`,
`major.phase.change`) is **9** — see `CLAUDE.md` → Engineering expectations.


## Phase 12: Multi-AI-Secretaty


## Phase 12: App ทำงานร่วมกันได้
- [ ] User สามารถ start app พร้อมกันได้มากกว่า 1 app
- [ ] Two or more app be able to talk to each other.
- [ ] การทำงานร่วมกัน
  - [ ] ให้ app มากกว่า 1 ตัว monitor instruction เดียวกัน
  - [ ] ให้ app มากกว่า 1 ตัว monitor task log เดียวกัน เพื่อให้แต่ละตัวเห็นความคืบหน้าของงาน
  - [ ] ให้ app แต่ละตัว ทำตาม instruction ตามขั้นตอนของตัวเอง โดยดูจากชื่อ profile ว่า step ไหน app ตัวไหนจะทำ
  - [ ] ก่อนเริ่ม app ต้องเช็คว่า 
      1) มีชื่อ profile ตัวเองใน instruction นั้นไหม (จะได้รู้ว่า step ไหนที่ตัวเองต้องทำ)
      2) ถาม user ว่าใช้ file ไหนเพื่อบอก progress ระหว่าง app (app ไหนทำอะไร ต้องมา write log เพื่อบอก app ตัวอื่นว่าทำ step ไหนไปแล้ว)
  - [ ] เมื่อ app เริ่มทำงาน app ไหนทำอะไร ต้องมา write log เพื่อบอก app ตัวอื่นว่าทำ step ไหนไปแล้ว
  - [ ] ถ้า step ไหนช่วยกันทำได้ app ต้องรู้ว่า parallel ได้กี่ app, ต้องรออะไรจึงจะรู้ว่าทำแล้ว, และทำเสร็จแล้ว โดย update กันใน task log
  - [ ] prevent เรื่อง lock file และ race condition (ทำซ้ำกัน, เข้าใจว่า app อื่นทำเลยไม่ได้ทำ, ลำดับงานผิด, ข้ามลำดับงาน, infinite loog) 

## Phase 13: Multi-session
- Before Start : อ่าน requirement ทั้งหมดใน phase นี้ก่อน เพราะต้อง re-architecture app และต้องจัดกลุ่ม feature ที่อยู่ใน Setting, Profile, Skills ใหม่ 
- Requirements
  - [ ] สามารถเปิด chat bubble ได้มากกว่า 1 window โดยที่แต่ละ window จะแยก Claude Session ออกจากกัน
  - [ ] การแสดง chat bubble ให้แสดง on top window เดิม แต่ให้ซ้อนทับแบบแหลื่อมๆกัน
  - [ ] ถ้า drag ตัวละคร, ให้ลากเอา chat bubble ทั้งหมดไปด้วย โดยซ้อนกับเป็นชั้นแบบเหลื่อมๆ แล้วลากไปด้วยกัน 
  - [ ] มีเมนูใน Menu icon ชื่อ Chats และลอกเอา feature มาจาก Pinned Messages เลย 
  - [ ] โดย default ใน Chats จะมี 1 session เสมอ คือ session ปัจจุบัน ถ้าปิด app แล้วเกิดใหม่ จะขึ้น session ใหม่ แต่ user สามารถกด session เก่าเพื่อเปิด chat เดิมที่คุยกันอยู่ได้
  - [ ] เมื่อเปิด chat เก่า จะขึ้น chat window ใหม่ ไม่ทับ chat ปัจจุบัน (ยกเว้นว่าเป็น session เดียวกัน)
  - [ ] แยก settings ตาม chat window ของใครของมัน แปลว่า แต่ละ chat จะแยก model, effort ได้
  - [ ] ถ้ามี Project อยู่แล้ว แล้วขึ้น session ใหม่ จะไม่เอา config project เดิมไปด้วย 
  - [ ] project ที่เพิ่มใหม่ใน session ใหม่ จะไม่เห็นใน session เดิม
  - [ ] chat window ที่ 2,3 จะไม่มี Profile จนกว่าจะปิดจนเหลือ session (window) เดียว app ก็จะแสดงกลับมา
  - [ ] จำ session history ได้ 
  - [ ] เพิ่ม menu Sessions ใน Menu bar
    - [ ] ตั้งชื่อเมนูสั้นๆ ให้ด้วย ตาม context ที่คุยกัน  
    - [ ] ถ้า click ที่ session ใน menu จะเปิด chat bubble แล้วคุยต่อ (resumr session) ได้เลย
    - [ ] แต่ละ session ใน menu มีปุ่มปิด ถ้าปิดก็ลบ history ไปเลย
- Expected App Architecture