# Product Backlog — AI Desktop Companion / AI Secretary

Feature list by phase, extracted out of `CLAUDE.md` so the charter (architecture,
principles, engineering rules) stays separate from the backlog (what's built vs.
what's left). Checked items are shipped; unchecked items are still open.

The current phase for version-bumping purposes (`AppVersion.swift`,
`major.phase.change`) is **9** — see `CLAUDE.md` → Engineering expectations.


## Phase 12: Liquid Glass Theme
  **ข้อเท็จจริงใต้เฟสนี้ขยับไปแล้วบางส่วนที่ v0.10.197 (2026-08-11)** — รอบนั้นแก้อาการ
  "พื้นโปร่งทำให้อ่านไม่ออกเมื่อ desktop สว่าง" ซึ่งแตะโค้ดชุดเดียวกับเฟสนี้ อ่านก่อนเริ่มข้อไหนก็ตาม
  - `.fill(.regularMaterial)` ที่ข้อ #2 อ้างถึง **ไม่มีแล้ว** เป็น `theme.ground.color` (สีทึบ)
    ตัว `SpeechBubbleShape` ยังเป็น `Shape` เหมือนเดิม จึงยังส่งเข้า `glassEffect(in:)` ได้อยู่
  - **ข้อ #3 (Content first) ถือว่าเสร็จแล้ว และเสร็จคนละแบบกับที่เขียนไว้** — ไม่ได้ "เพิ่มพื้นทึบ
    ใต้ transcript แล้วไล่ปรับ opacity ~6 ค่าโดยดูด้วยตา" แต่เปลี่ยนทั้งแอปให้ใช้ palette ที่ตั้งชื่อ
    ตามบทบาท (`SecretaryCore/Theme.swift`) ซึ่งทุกค่าเป็นสีทึบ และ `ThemeTests` คำนวณ contrast
    ครบทุกคู่ (text × ground × palette) แล้วบังคับค่าขั้นต่ำ
    ถ้าจะทำ glass ต่อ **ห้ามย้อนกลับไปใช้ opacity ทับพื้นที่ไม่รู้ว่าเป็นสีอะไร** นั่นคือบั๊กเดิม
  - ข้อ #6/#7 นับจุดไว้ (25 จุดวาดพื้นเอง, ทา accent 4 จุด) — นับก่อนเปลี่ยน ต้องนับใหม่
  - **ข้อ #0 ทำไปแล้วครึ่งเดียว** กลไกเลือก theme มีแล้ว (`ThemeChoice` + แถวใน Settings +
    เก็บค่าข้ามการเปิดแอป) และตัวเลือกตอนนี้คือ System / Light / Dark
    (เคยมี Contrast ด้วยที่ 0.10.197 เจ้าของให้เอาออกที่ 0.10.198)
    ส่วน "Liquid Glass เป็นอีกตัวเลือกหนึ่ง" ยังไม่ได้ทำ — เพิ่มเป็น case ใหม่ของ `ThemeChoice`
    ได้เลย แต่ต้องตอบก่อนว่ามันเป็น palette ที่สาม หรือเป็นผิวที่ทับได้ทั้งสอง palette ที่มีอยู่

  ตามหลัก 10 ข้อของ Liquid Glass ที่เจ้าของสรุปไว้ (2026-08-04) เลขข้อตรงกับต้นฉบับ
  มี **ด่าน** อยู่ก่อน #0 ต้องผ่านก่อนถึงจะเริ่มข้อไหนก็ตาม รวมทั้ง #0 ด้วย
  ข้อเท็จจริงใต้แต่ละข้อสำรวจจากโค้ดจริงตอนตั้ง backlog ไม่ใช่การเดา — ถ้าโค้ดขยับไปแล้วให้ตรวจซ้ำ
- [ ] **ด่าน — ทดสอบว่า glass ทำงานจริงบนหน้าต่างที่ไม่เป็น key ก่อนทำทุกข้อ
  ถ้าไม่ผ่าน ไม่ต้องไปต่อ ทั้งเฟสนี้ตกไป**
  - [ ] หน้าต่างของแอปนี้ถูกออกแบบให้ไม่เป็น key window ตลอดชีวิต และ AppKit ถอด accent ออกจาก
    tinted control เมื่อหน้าต่างไม่ใช่ key มาแล้วครั้งหนึ่ง — นั่นคือที่มาของ `PanelToggleStyle`
    ถ้า `.glass` ประพฤติแบบเดียวกัน ผิวทั้งเฟสจะดูตายตลอดเวลา ซึ่งแย่กว่าของเดิมที่มีอยู่
  - [ ] **อ่านโค้ดหรือเอกสารแล้วตอบไม่ได้** เอกสารของ Apple ไม่ได้พูดถึงกรณี non-activating panel
    ต้องเปิดแอปแล้วมองด้วยตา ทั้งตอนที่แอปเป็น frontmost และตอนที่ไปคลิก Finder ทิ้งไว้
  - [ ] spike ให้เล็กที่สุด: ตัวบับเบิล + แถวปุ่มท้ายกล่อง เท่านั้น ห้ามลาม ถ้าไม่ผ่านจะได้ทิ้งง่าย
  - [ ] ทำก่อน #0 ได้โดยไม่ต้องขยับ deployment target — ห่อ spike ด้วย `if #available(macOS 26, *)`
    ชั่วคราว เพื่อไม่ให้การทดสอบกลายเป็นการตัดสินใจเรื่อง macOS 14/15 ไปด้วยกัน
  - [ ] ถ้าไม่ผ่าน: จดผลลงที่นี่ว่าเห็นอะไร แล้วปิดเฟส อย่าปล่อยให้เป็นข้อค้างที่ใครมาเริ่มใหม่ได้
- [ ] **#0 Theme** - สามารถเปลี่ยน Theme ได้ โดย Theme เดิมเป็น Default, และมีให้เลือก Liquid Glass
- [ ] **#1 ขยับ deployment target `macOS 14` → `macOS 26`** (`code/Package.swift:7`) — API ชุดนี้
  (`glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)`) มีตั้งแต่ macOS 26 คงไว้ที่ 14
  แปลว่าทุกจุดต้องมี `if #available` คู่กับทางสำรองของเดิม คือเขียนสองหน้าตาแล้วต้องดูแลทั้งคู่
  แอปยังไม่ปล่อยต้นทุนจึงเกือบศูนย์ แต่ตัด macOS 14/15 ทิ้งทันที — เป็นการตัดสินใจของเจ้าของ
  - ที่ได้มาแล้วโดยไม่ต้องแก้อะไร: build ด้วย macOS 26 SDK อยู่แล้ว และ `package-app.sh`
    ไม่ได้ใส่ `UIDesignRequiresCompatibility` — ปุ่ม ช่องพิมพ์ scrollbar และหน้าต่าง
    About/Usage จึงรับหน้าตาใหม่ไปเรียบร้อย งานที่เหลือคือผิวที่เราวาดเอง
- [ ] **#2 Glass คือ UI ไม่ใช่ decoration** — ให้เฉพาะชั้นที่โต้ตอบได้: ตัวบับเบิล
  (จุดที่เป็น `.fill(.regularMaterial)` ใน `ChatPanelView.swift` — `SpeechBubbleShape` เป็น `Shape`
  อยู่แล้ว จึงส่งเข้า `glassEffect(in:)` ได้ตรงๆ), ปุ่มมุมหน้าต่าง, grip, แถวปุ่มท้ายกล่อง,
  กล่องแผงที่เปิด รวม ~5 จุด
  - ตัวละครห้ามเป็น glass — เป็นพระเอกตามข้อ 2 ไม่ใช่เครื่องมือ
- [ ] **#3 Content first — พื้นที่ข้อความต้องทึบ** ตอนนี้ transcript นั่งบน material ตรงๆ
  ไม่มีพื้นรองของตัวเอง พอเปลี่ยนเป็น glass กล่องข้อความที่ใช้ `Color.secondary.opacity(0.07)`
  จะกลืนหายไปกับพื้น ต้องเพิ่มพื้นทึบใต้ transcript แล้วไล่ปรับค่า opacity ~6 ค่า
  **ทุกค่าต้องดูด้วยตาบน wallpaper จริง** ไม่ใช่คำนวณ — ข้อนี้แตะบรรทัดมากที่สุดในเฟส
- [ ] **#4 ลอยเหนือ content** — `FloatingPanel` เป็น `isOpaque = false` + `hasShadow = true`
  อยู่แล้วจึงผ่านโดยไม่ต้องแก้ ระวังอย่างเดียวคือเงาของ glass ซ้อนกับเงาของ `NSWindow`
- [ ] **#5 Glass ต้องเคลื่อนไหว** — *ตัดสินใจแยกจากข้ออื่น* ราคาไม่ได้อยู่ที่ animation
  แต่อยู่ที่โครงหน้าต่าง: ตัวละครกับกล่องแชตเป็นคนละ `NSPanel` (`AppDelegate.swift:99` และ `:119`)
  `glassEffectID` morph ข้ามหน้าต่างไม่ได้ ตัวอย่าง "กล่องแชตขยายจากไอคอนตัวละคร" จึงทำด้วย
  SwiftUI morph ไม่ได้เลย — ต้องเลือกระหว่างขยับ frame ของ panel เองแบบ AppKit (ใกล้เคียง
  ไม่ใช่ morph จริง) หรือยุบเป็นหน้าต่างเดียว ซึ่งรื้อ `placeBubble`/`GripCorner`/การลากตัวละคร
  - [ ] และทั้งแอปมี `withAnimation` อยู่ที่เดียว (`UsageWindow.swift`) ข้อนี้จึงไม่ใช่การปรับ theme
    แต่เป็นการสร้างของใหม่
- [ ] **#6 ห้ามซ้อน glass หลายชั้น** — มี 25 จุดที่วาดพื้นหลังเอง ควรเป็น glass แค่ ~5 จุดตามข้อ 1
  ที่เหลือ (กล่องข้อความ, badge, บล็อกโค้ด, การ์ด approval/`/run`/onboarding) อยู่ในชั้นเนื้อหา
  ต้องคงเป็นสีทึบ
- [ ] **#7 ใช้สีให้น้อยที่สุด** — เราทา `accentColor` เอง 4 จุด (ปุ่มแผงที่เปิด + badge สามอัน)
  เปลี่ยนไปใช้ neutral แล้วบอกสถานะด้วยความสว่างของ glass ตามข้อ 10
- [ ] **#8 Glass เปลี่ยนตาม context** — ได้ฟรีจาก `glassEffect` ไม่มีงาน
- [ ] **#9 เว้นพื้นที่รอบ Glass** — บับเบิลลอยห่างขอบจออยู่แล้วจาก `placeBubble` ไม่มีงาน
- [ ] **#10 ใช้ Shape เดียวกันทั้งระบบ** — badge เป็น `Capsule` อยู่แล้ว ส่วน `SpeechBubbleShape`
  เป็น shape เฉพาะเพราะมีหางชี้ตัวละคร ซึ่งเป็นเอกลักษณ์ของแอปนี้ ไม่ยุบรวม
- [ ] **#11 Focus ด้วย Glass** — หน้าต่างนี้ไม่เคยเป็น key window จึงพึ่ง focus state ของระบบไม่ได้
  ต้องวาดสถานะเอง ซึ่งเป็นเหตุผลเดียวกับที่ `PanelToggleStyle` มีอยู่ทุกวันนี้

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

## Phase 14: Loop & Notification
- [ ] สั่งให้ loop ได้ เช่น นับถอยหลัง 5 นาทีแล้วแจ้งเตือน หรือ long run แล้วแจ้งเตือนได้
- [ ] มี local notification เมื่อทำงานเสร็จ (notification settings ตาม macOS)
- [ ] เมื่อ click ที่กล่อง notication, จะเปิด app และ chat window ขึ้นมา

## Phase 15: Voice
- [ ] Push-to-talk or explicit voice activation.
- [ ] Speech-to-text, text-to-speech, interruption behavior, and privacy controls.
- [ ] Voice must follow the same approval and auditing model as chat.

## Defered
  - [ ] ยังไม่ได้พิสูจน์: MCP tool ที่มีผลออกนอกเครื่อง (ส่งเมล/สร้าง event) ถูกจัดเป็น `.localWrite`และการ์ดขออนุมัติขึ้นข้อความ "Send to Claude?" ซึ่งน่าจะสื่อผิด — ต้องทดสอบก่อนถือเป็นบั๊ก
