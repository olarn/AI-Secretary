# Product Backlog — AI Desktop Companion / AI Secretary

Feature list by phase, extracted out of `CLAUDE.md` so the charter (architecture,
principles, engineering rules) stays separate from the backlog (what's built vs.
what's left). Checked items are shipped; unchecked items are still open.

The current phase for version-bumping purposes (`AppVersion.swift`,
`major.phase.change`) is **6** — see `CLAUDE.md` → Engineering expectations.

## Phase 1: Desktop companion shell

- [x] Transparent floating character window.
- [x] Basic character state animations or placeholders.
- [x] Dragging and basic interaction.
- [x] Chat panel opened from the character.
- [x] Local mock state transitions.

## Phase 2: Secretary and coding workflow

- [x] Intent classification for a limited set of commands.
- [x] Project registry and explicit working-directory resolution.
- [x] Task lifecycle, approval prompts, execution logs, and result summaries.
- [x] Claude Code adapter for approved coding tasks.
- [x] Basic Git status/diff and test-result reporting.

## Phase 3: Chat with me

- [x] Integration with Claude as a mask app.
- [x] ใช้ Claude Code ที่ user ติดตั้งและ login ไว้แล้ว (บัญชีของ user เอง ไม่ต้องใช้ API key) — ถ้าเครื่องไม่มี ให้แนะนำวิธีติดตั้งและ login
- [x] context ต่อเนื่องเหมือน ChatGPT: ผลลัพธ์คำสั่งและเนื้อหาไฟล์ที่อ่านต้องอยู่ใน context เพื่อถามต่อเนื่องได้
- [x] จำ project ล่าสุดที่ทำงานอยู่ ไม่ต้องพิมพ์ `in <project>` ซ้ำทุกครั้ง
- [x] ถ้า add project มากกว่า 1 ต้องเข้าใจบริบทของทุก project พร้อมกัน
- [x] ต่อ local / localhost MCP ได้ โดยอ่าน config จาก Claude Code ของ user เอง ไม่ต้องตั้งค่าซ้ำในแอป
- [x] แสดงข้อความ activity ที่ AI กำลังทำ (กำลังคิด / เรียกเครื่องมือไหน) แทรกอยู่ในสายของ chat และมีกรอบข้อความ เพื่อให้เห็นชัดว่านี่ไม่ใช่คำตอบ
- [x] ปิด/เปิด activity ได้ด้วยการ toggle icon status และบอกผลการ toggle ในสาย chat ด้วยกรอบเดียวกัน จำค่าไว้ข้ามการเปิดแอป ครั้งแรก default ซ่อน
- [x] เวลา AI ตอบ chat ถ้า position อยู่ที่ bottom ให้ auto scroll ตาม แต่ถ้า user scroll ขึ้นไปอ่าน message เก่าๆ ไม่ต้อง auto scroll จนกว่า user จะ scroll ลงมาล่างสุด
- [x] แสดง markdown table เป็นตารางจริงใน chat ถ้าตารางกว้างเกินหน้าต่าง ให้ scroll แนวขวางได้เฉพาะ content ของตาราง ไม่ใช่ทั้ง chat

## Phase 4: Settings

- [x] ใช้ window chat เดิมได้ ไม่ต้องมีหน้าต่างใหม่
- [x] เพิ่ม increase / decrease font size (มีปุ่มแค่ + -) max ที่ 32
- [x] เพิ่ม increase / decrease ขนาดหน้าต่าง chat (มีปุ่มแค่ + -) แล้วหน้าต่างจะยืดหดได้ โดย minimum เท่าขนาด default และ max ไม่เกินขนาดหน้าจอ
  - [x] เดิมข้อนี้เขียนว่า "แนวตั้งเท่านั้น" — Phase 5.5 เปิดให้ปรับความกว้างด้วยแล้ว (ปุ่ม step และลาก grip)
- [x] เลือก model และ effort ได้จากหน้า setting (คลิกที่ชื่อแล้วมี popup ให้เลือก) โดย default ใช้ค่าเดียวกับ Claude Code ของ user และบอกการเปลี่ยนแปลงใน chat

## Phase 5: Secretary Profiles

- [x] ขยาย/ย่อ app size ได้ 3 ระดับ (S,M,L - เล็กลง/ใหญ่ขึ้น 30%) - ขนาดปัจจุบันคือ M
- [x] สร้าง profile ใหม่ได้
  - [x] ตั้งชื่อได้ ชื่อจะแสดงใน chat (เช่น ตอนนี้คือ Miku)
  - [x] upload รูป profile ใหม่ได้ (save ใน local storage)
  - [x] รูป profile จะแสดงใน bubble ของ app
  - [x] upload รูป แยกตาม activity ได้ เช่น Idle, Thinking, ... ซึ่งจะ require แค่รูปเดียวเป็น default ของ profile
  - [x] กำหนดเพศได้ เช่น เพศ หญิง/ชาย/LBGTQ+ (นอกจากชายหญิง กรอก free text ได้)
  - [x] กำหนดวัยได้ เด็ก/วัยรุ่น/ผู้ใหญ่ หรือกำหนดอายุเลย
  - [x] กำหนดสไตล์ได้ เช่น มืออาชีพ เพื่อน เป็น free text ถ้าไม่เข้าใจ ใช้ default คือ มืออาชีพ (ไม่อนุญาติให้สื่อไปทางความสัมพันธ์ทางเพศ)
- [x] เปลี่ยน profile ได้ App จะ refresh ทันที
- [x] App จะแสดงรูปที่แตกต่างกันตาม activity ที่กำลังทำ (เปลี่ยนเมื่อ thinking หรือ idle)
- [x] เมื่อ activity แต่ไม่มีรูป ให้ใช้รูป default รูปเดียว

## Phase 5.5: ปรับ UI/UX จากการใช้งานจริง

- [x] ครั้งแรกที่ run ต้องมี default profile คือ Miku เขียนลง local storage เลย ไม่ใช่มีแค่ใน memory
- [x] upload รูป profile รูปเดียวต่อ profile (ไม่แยกตาม activity) เป็นแถว Picture แถวเดียว คลิกแล้วมี popup (Choose / Clear) แบบเดียวกับ Model และ Effort — activity สื่อด้วยสี halo, badge และ label ใต้ตัวละคร
  - [x] ของเดิมที่ upload แยกตาม activity ไว้ ต้องย้ายมาเป็นรูปเดียวให้อัตโนมัติ ไม่ให้รูปหาย
- [x] ตัวละครต้องอยู่กลาง bubble ไม่ว่ารูปจะสัดส่วนแบบไหน
- [x] เอาปุ่ม Debug ออกจาก chat window
- [x] ตารางและกล่อง activity ต้องขยาย/ย่อตาม font size ที่ตั้งไว้
- [x] หน้าต่างตัวละครต้องขยายตาม S/M/L จริง และต้องไม่ถูกตัดขอบ (bubble ที่คลุมตัวละครต้องกลมครบวง)
- [x] ตำแหน่ง chat window ต้องห่างจากตัวละครตามสัดส่วนขนาด app (S ไม่ห่างเกิน L ไม่ทับกัน)
- [x] URL ใน chat ต้องคลิกเปิดเบราว์เซอร์ได้ ทั้ง URL ล้วนและ markdown link
  - [x] hover แล้ว cursor เปลี่ยนเป็นนิ้ว และขึ้น underline
  - [x] อนุญาตเฉพาะ http/https/mailto — scheme อื่น (เช่น file:, javascript:) แสดงเป็นข้อความธรรมดา คลิกไม่ได้ เพราะข้อความจาก model/เว็บ/tool ถือเป็น untrusted
- [x] คลิกที่ตัวละคร 1 ครั้ง = เปิด/ปิด chat 1 ครั้ง (คลิกแรกต้องไม่ถูกกินไปเป็นการ focus หน้าต่าง)
- [x] textbox ของ chat ต้อง word wrap และขยายทีละบรรทัด จาก 1 เป็น 2,3,4 สูงสุด 5 บรรทัด เกินนั้นไม่ขยายต่อ แต่ scroll แนวตั้งได้
  - [x] Enter = ส่ง, Shift+Enter หรือ Option+Enter = ขึ้นบรรทัดใหม่
- [x] resize chat window ได้เองด้วยการลาก grip ที่มุมบนด้านตรงข้ามหาง (อีกมุมเป็นแถวปุ่ม) ปรับได้ทั้งกว้างและสูงพร้อมกัน, minimum เท่าขนาด default, max ไม่เกินหน้าจอ
  - [x] ลากไปทางที่กล่องจะขยายออก (ขอบด้านหางถูกตรึงไว้กับตัวละคร กล่องจึงโตออกด้านตรงข้ามเสมอ)
  - [x] **resize คือ resize อย่างเดียว ห้ามขยับตัวละคร** — `applyWindowSizes` ทำงานทุกครั้งที่ appearance เปลี่ยน จึงห้ามเรียก `keepCharacterOnScreen` จากที่นั่นโดยไม่เช็คว่าขนาด *ของตัวละครเอง* เปลี่ยนไหม เคยวัดได้ว่าตัวละครที่ยืนคร่อม Dock กระโดดขึ้น 54pt ทันทีที่แตะกริป
    - [x] clamp ตัวละครกับ `screen.frame` ไม่ใช่ `visibleFrame` — ยืนบน Dock เป็นที่ปกติของ desktop character กติกาที่เหลือคือแค่ "ห้ามหลุดออกนอกจอ"
  - [x] **พลิกกล่องลงใต้ตัวละครเฉพาะตอนข้างล่างมีที่จริง** — กฎเดิมพลิกทันทีที่ "วางข้างบนไม่พอ" โดยไม่ถามว่าข้างล่างพอไหม กล่องสูง 883 เหนือตัวละครที่ยืนคร่อม Dock (จอ 1920×1080: ตัวละคร y 30–179) ข้างบนขาดไป 6pt แต่ข้างล่างเหลือ **−18** พอพลิกลงแล้วโดน clamp กลับเข้าจอ กล่องไปลงที่ y 62–945 คือกลบตัวละครทั้งตัว ซึ่งเป็นสิ่งเดียวที่ห้ามเกิด เพราะตัวละครคือทางเดียวที่ user เอื้อมถึงกล่อง — `placeBubble` (ใน `SecretaryCore` เพื่อให้เทสได้โดยไม่ต้องมีจอ) จึงเทียบที่ว่างสองด้าน พลิกเมื่อด้านล่างพอ หรือ (ถ้าไม่พอทั้งคู่) ด้านล่างว่างกว่า
    - ทางพลิกต้องยังใช้ได้ ตัวละครที่อยู่ติดแถบเมนูต้องได้กล่องอยู่ใต้ตัวและหางชี้ขึ้น — มีเทสคุมทั้งสองทิศ
    - ที่ความสูงสุด (= ความสูงจอ) กล่องยังทับตัวละครอยู่ดีประมาณ 115pt เพราะขนาดที่ตั้งไว้ใหญ่กว่าที่ว่างเหนือหัว เป็นผลตรงของกติกา "max ไม่เกินหน้าจอ" ไม่ใช่บั๊กของการวาง — ถ้าจะแก้ต้องลดเพดานความสูง ซึ่งเป็นการหั่นค่าที่ user ตั้งเอง ต้องให้เจ้าของเลือก
  - [x] **กริปต้องอยู่มุมที่กล่องโตออก ไม่ใช่มุมบนเสมอ** — พอกล่องพลิกไปอยู่ใต้ตัวละคร ขอบบนถูกหางตรึงไว้ กล่องโตลงล่าง แต่กริปยังค้างอยู่มุมบน คนจึงต้องลากลง "ผ่าน" กริปที่ไม่ตามเมาส์ และลากเข้าหาตัวละคร ทั้งที่พื้นที่ว่างที่กำลังจะถมอยู่อีกฟากของกล่อง — กฎมุมอยู่ใน `GripCorner` (แนวนอน = ตรงข้ามหาง, แนวตั้ง = ขอบที่ขยับได้) มีเทสคุมทั้ง 4 กรณี ไม่ใช่แค่ 2 กรณีที่เปลี่ยน
    - แถวปุ่ม Settings/Profile/Projects อยู่มุมล่างด้วย จึงต้องย้ายไปอีกฝั่งเมื่อกริปมาลงมุมเดียวกัน ไม่งั้นกริปทับปุ่ม Settings
    - glyph เลือกด้วย**ชื่อ symbol ตามแนวทแยงของมุมนั้น** ไม่ใช่หมุนอันเดียว และต้องเป็นตัว "กางออก" — ทุกแนวทแยงมีฝาแฝดที่ลูกศรชี้เข้าหากัน (`arrow.up.right.and.arrow.down.left` = หุบเข้า) ทั้งคู่เป็น symbol ที่มีจริง จับได้ทางเดียวคือเปิดดูของจริง มีเทสกันทั้งชื่อที่ไม่มีอยู่ (render เป็นความว่าง ดูเหมือนกริปหาย) และฝาแฝดที่ชี้เข้า
  - [x] ทิศทางการโตต้องตรึงไว้ตั้งแต่เริ่มลาก (เก็บใน `DragOrigin`) ห้ามอ่านสดจาก layout ทุก event — พอกล่องไม่พอที่ด้านบนมันจะพลิกไปอยู่ใต้ตัวละครแล้วทิศกลับด้าน ลากค้างทางเดิมกลายเป็นย่อ แล้วพลิกกลับ วัดได้ 909 → 801 → 933 → 777 ใน 4 event และแกว่งกว้างขึ้นเรื่อยๆ
- [x] มี icon "←|→" (กว้างขึ้น) และ "→|←" (กลับเป็นขนาด default) เรียงข้างปุ่มปิด chat window โดย icon ทั้งสองเล็กกว่าปุ่มปิด 30%
  - [x] "←|→" กด 1 ครั้ง = 1 step: x1 → x2 → x3 แล้ว disable
  - [x] "→|←" กดครั้งเดียวกลับเป็นขนาด default ทันที ไม่ต้อง step
- [x] เมื่อ mirror กล่องคำพูด ให้ grip กับแถวปุ่ม (ปิด/ย่อ/ขยาย) สลับด้านกัน และสลับลำดับปุ่มด้วย โดยปุ่มปิดอยู่ริมนอกสุดเสมอ
- [x] Title ของกล่อง chat อยู่ใต้แถวปุ่ม ชิดซ้ายเสมอ ไม่ทับปุ่มและไม่ขยับตามการ mirror
- [x] ขยาย/ย่อ font ด้วย ⌘+ และ ⌘− ได้ ไม่ใช่แค่ปุ่ม + − ใน Settings
- [x] font size ต้องมีผลกับปุ่ม Settings/Profile/Projects และตัวอักษรในช่องพิมพ์ข้อความด้วย ไม่ใช่แค่เนื้อหา chat
  - [x] ตัวอักษรในช่องพิมพ์ต้องอยู่กลางกล่องตามแนวตั้ง ไม่ลอยติดขอบบน
- [x] เวลาขยาย/ย่อ chat window ปลายแหลมของกล่องคำพูดต้องอยู่ตำแหน่งเดิม (ยึดขอบด้านหาง แล้วขยายออกด้านตรงข้าม) ทั้งกรณีหางอยู่ซ้ายและหางอยู่ขวา (mirrored)

## Phase 5.6: Version and About

- [x] เลข version อยู่ใน code (`SecretaryCore/AppVersion.swift`) เป็นแหล่งเดียว — `package-app.sh` อ่านค่านี้ไปใส่ `CFBundleShortVersionString` ไม่ให้เลขสองที่ไม่ตรงกัน
- [x] แอปต้องบอก version ตัวเองได้ แม้รันแบบไม่มี bundle
- [x] มีหน้าต่าง About เปิดจากเมนู status bar แสดงชื่อ, version, และคำอธิบายสั้นๆ
- [x] ⌘H = Hide/Show Character (ไม่ใช่ hide ทั้งแอป เพราะ accessory app ไม่มีหน้าต่างใน Dock ให้เรียกกลับ)
  - [x] ซ่อนคือ "เอาไปพ้นทางแป๊บนึง" ไม่ใช่ค่าที่ต้องจำ — เปิดแอปอีกครั้งต้องเห็นตัวละครเสมอ ต้องปิดสองทางถึงจะครบ ทั้งคู่เคยทำให้เปิดแอปแล้วไม่มีอะไรขึ้นเลย
    - [x] เปิดแอปซ้ำตอนตัวเดิมยังรันอยู่ macOS **ไม่ได้ launch process ใหม่** แต่ส่ง `applicationShouldHandleReopen` มาแทน — ถ้าไม่ดักไว้ การดับเบิลคลิกแอป (ซึ่งเป็นสิ่งที่คนทำตอนหาตัวละครไม่เจอ) จะไม่เกิดอะไรขึ้นเลย
    - [x] panel ต้อง `isRestorable = false` ไม่งั้น state ที่ AppKit จำไว้ตอน quit สั่ง orderOut ทับ `orderFrontRegardless` ใน `applicationDidFinishLaunching` ได้
- [x] **Esc ปิดกล่องแชทได้แม้แอปไม่ได้เป็นหน้าต่างหน้าสุด**
  - `addLocalMonitorForEvents` กับ key equivalent ของเมนู เห็นเฉพาะอีเวนต์ที่ระบบเลือกส่งมาให้แอปนี้ — กล่องลอยอยู่เหนือแอปอื่น กด Esc คีย์ไปที่แอปนั้น กล่องจึงไม่ปิด "โค้ดถูก แต่คีย์ไม่เคยมาถึง" แบบเดียวกับ `.onExitCommand`
  - ใช้ `RegisterEventHotKey` ของ Carbon — ทางเดียวที่ไม่ต้องขอสิทธิ์ Accessibility (ต่างจาก `CGEventTap`) และเป็นทางเดียวที่ **กลืน** คีย์ ส่วน `addGlobalMonitorForEvents` ได้ยินแต่กลืนไม่ได้ แอปที่อยู่หน้าสุดจะทำตามคีย์นั้นไปด้วย
  - **จดทะเบียนเฉพาะตอนกล่องแชทเปิด กล่องปิดแล้วไม่ยึดอะไรเลย** — Esc เป็นคีย์ที่คนใช้ตลอด (ปิด dialog, ออก full screen, จบสไลด์โชว์) ยึดค้างไว้ทั้งที่กล่องไม่ได้เปิดคือพังของทั้งเครื่องแลกกับหน้าต่างที่ไม่ได้โผล่
  - กติกาว่ายึดคีย์ไหนเมื่อไหร่อยู่ใน `GlobalShortcut` ที่ `SecretaryCore` มีเทสคุม ไม่ใช่ register สองบรรทัดฝังในโค้ดหน้าต่าง — ทุกคีย์ที่ยึดคือคีย์ที่หายไปจากทุกแอปบนเครื่อง ของแบบนี้ต้องเห็นได้ในที่เดียว
- [x] **⌘H ต้องเป็นชอร์ตคัตของแต่ละแอป ห้ามยึดทั้งเครื่อง** — เคยยึดไปแล้วหนึ่งรอบ (0.6.61) ผลคือ Hide ของทุกแอปบนเครื่องหายไป เจ้าของแจ้งภายในไม่กี่นาที คืนให้ใน 0.6.62
  - บทเรียนไม่ใช่แค่ "⌘H พิเศษ" แต่คือ **คอมบิเนชันที่มี ⌘ เป็นของเมนูแอปอื่นเสมอ** — มีเทสบังคับว่าชอร์ตคัตที่ยึดได้ห้ามมี Command เป็นตัวประกอบ เรื่องนี้จึงกลับมาโดยบังเอิญไม่ได้
  - ถ้าจะเอา "ซ่อนทั้งแอปจากที่ไหนก็ได้" จริงๆ ต้องเป็นคอมบิเนชันที่ไม่มีใครใช้ เช่น ⌥⌘H ไม่ใช่ทับของเดิม
  - ตอนถามเจ้าของให้เลือก ตัวเลือกที่เขียนให้เลือกก็ต้องไม่ขัด requirement ที่เคยให้ไว้ — รอบนั้นเขียนตัวเลือก "ยึดทั้งระบบ" ขึ้นมาเอง แล้วก็ทำตามตัวเลือกที่ผิดนั้น
- [x] **dialog เลือกโฟลเดอร์/รูป ต้อง `NSApp.activate` ก่อน `runModal()`** — `runModal()` เปิดหน้าต่างให้ แต่ไม่ได้ดึงแอปขึ้นมาเป็นแอปหน้าสุด และตอนกดปุ่มแอปมัก**ไม่ได้**เป็นแอปหน้าสุดอยู่แล้ว เพราะแชทเป็น non-activating panel คลิกในนั้นไม่ทำให้แอป active — open panel ของแอปที่ไม่ active จะไม่เป็น key window รายการโฟลเดอร์เลยไม่ตอบสนองการคลิก นี่คือเหตุผลของคำว่า "บางครั้ง": มันใช้ได้ถ้าเพิ่งเปิดแชท เพราะการเปิดแชทเรียก activate อยู่แล้ว
  - ไม่ใช่เรื่องระดับหน้าต่างบัง — วัดแล้ว dialog อยู่ layer 8 (`.modalPanel`) ส่วน panel ของเราอยู่ layer 3 (`.floating`) มันอยู่เหนือเราอยู่แล้ว
  - **ต้องคืน hotkey ระหว่าง modal ด้วย** (`GlobalHotKeys.whileSuspended`) — Carbon hotkey ยิงไม่สนว่าอะไรอยู่บนจอ พอกล่องแชทเปิดอยู่หลัง dialog กด Esc จะไปปิดแชทแล้วทิ้ง dialog ค้างไว้ ซึ่งเป็นปุ่มที่ทุกคนใช้ยกเลิก dialog และต้อง "คืนคีย์" ไม่ใช่ "เมินคีย์" เพราะเมินแล้วคีย์ยังถูกกลืนอยู่ดี กด Esc จะไม่เกิดอะไรเลย
- [x] **อย่าใช้การ register ซ้ำเป็นเครื่องมือวัดว่าใครถือคีย์อยู่** — เขียนโพรบไปแล้วรอบหนึ่ง macOS ยอมให้อีก process จดคีย์เดียวกันได้ มันตอบ FREE ทั้งตอนที่แอปถืออยู่และไม่ถือ วัดได้ทางเดียวคือดูพฤติกรรมจริง
  - วิธีที่ใช้ได้: เปิดแถบค้นหาของ Safari (⌘F) แล้วกด Esc — กล่องเปิดอยู่ แถบค้นหาต้องยังอยู่ (เรากลืน) กล่องปิดแล้ว แถบค้นหาต้องหาย (เราคืนคีย์) ส่วน ⌘H เช็คด้วย `visible of process "Safari"` ว่าซ่อนได้จริง

## Phase 5.7: คีย์ลัดในแชท และตัวเลือกที่กดเลือกได้

- [x] ข้อความที่ขึ้นต้นด้วย `-` ต้องส่งได้ (bullet list, คำถามเกี่ยวกับ flag)
- [x] Shift+Enter ขึ้นบรรทัดใหม่ได้ ไม่ใช่แค่ Option+Enter
- [x] ลูกศรขึ้น/ลง เรียกข้อความที่เคยส่งในเซสชันนั้นกลับมาได้ เหมือน terminal
  - [x] ลงจนสุดแล้วได้ข้อความที่พิมพ์ค้างไว้คืน ไม่หาย
  - [x] ทำงานเฉพาะตอนกล่องพิมพ์เป็นบรรทัดเดียว — ถ้าหลายบรรทัด ลูกศรเป็นของการเลื่อน caret
- [x] Esc ปิดหน้าต่างแชท (ทำงานไม่ว่า focus อยู่ตรงไหน)
- [x] เวลา AI ถามให้เลือก ต้องขึ้นกล่องตัวเลือกที่กดลูกศรเลือกและ Enter ยืนยันได้ (คลิกได้ด้วย)
- [x] scroll ลงล่างสุดแล้วข้อความบรรทัดสุดท้ายต้องไม่ติดขอบจนดูเหมือนโดนตัด
- [x] code / JSON ในคำตอบต้องแสดงเป็นกล่อง code (monospace, รักษาการเยื้องบรรทัด, เลือกคัดลอกได้)
  - [x] บรรทัดยาวห้าม wrap — ให้ scroll แนวขวางเฉพาะกล่องนั้น เหมือนตาราง (การ wrap โค้ดใส่การขึ้นบรรทัดที่ไม่มีจริง อ่านแล้วไม่รู้ว่าต้องพิมพ์อะไร)
  - [x] ต้องแยก block ออกมาก่อนถึง `MessageMarkdown` เพราะ `.inlineOnlyPreservingWhitespace` กลืน fence แล้วยุบเนื้อในเป็นบรรทัดเดียว (เคยเห็น JSON โผล่มาเป็น `json { "iso": ... }`)
  - [x] หา code fence ก่อนหาตาราง — ในกล่องโค้ดมี `|` ได้ ถ้าหาตารางก่อนจะฉีกโค้ดออกเป็นตาราง

## Phase 6: External tools

- [x] MCP-based integrations such as calendar, Slack, email, and knowledge sources.
  - [x] ไม่ต้องเขียนโค้ดเพิ่ม — ทดสอบแล้วใช้ได้อยู่แล้ว (2026-07-28) เพราะแอปขับ Claude Code ของ user ซึ่งโหลด MCP server จาก config ของเขาเองตามที่ Phase 3 ตั้งใจ
  - [x] หลักฐาน: ถาม "ตอนนี้กี่โมงแล้ว" ลอยๆ ใน session ใหม่ โมเดลหา tool เจอเองด้วย ToolSearch แล้วเรียก `mcp__my-tools__get_time` สำเร็จ ไม่ต้องผ่านรอบขออนุมัติ และลิสต์ MCP server ที่เข้าถึงได้เองได้ครบ (ทั้ง server ราย project และ global เช่น Figma)
  - [x] อย่าเพิ่ม `mcp__*` ลง allowlist หรือเขียน MCP client เอง — allowlist ปัจจุบันไม่ได้บล็อก MCP
- [x] Be able to understand the web content through Chrome Claude plug in (suggest user that app can use this approach when user ask about app to understand the web contents).
  - [x] ทำแล้ว (2026-07-28) — ไม่ใช่แค่ "แนะนำ" อย่างเดียว แอปอ่านหน้าเว็บที่ต้อง login ได้จริง
  - [x] เหตุผล: `WebFetch` ยิงจาก process ของแอปเอง ไม่มี cookie/session — หน้า login จะคืนหน้า sign-in มาแทนเนื้อหา แล้วโมเดลรายงานหน้า sign-in ว่าเป็นเนื้อหาของหน้านั้น ส่วน extension ไม่ได้ fetch แต่อ่าน DOM ของ tab ใน Chrome ที่ user login ค้างอยู่ — ยืม session ที่เปิดอยู่ ไม่เคยเห็น password
  - [x] กลไก: Claude Code มี flag `--chrome` ต่อกับ Claude in Chrome extension ผ่าน MCP server ชื่อ `claude-in-chrome` (22 tools) — ในเมื่อแอปขับ Claude Code อยู่แล้ว จึงได้มาทั้งชุด
  - [x] พิสูจน์แล้วว่า `--chrome` ต่อติดใน non-interactive (`-p --output-format stream-json`) ด้วย: init event รายงาน `"claude-in-chrome": "connected"` ไม่มี first-run dialog มาค้าง (Claude Code 2.1.220)
  - [x] default = ปิด เปิดได้ที่ Settings → Browser และบอกใน chat เมื่อเปลี่ยน จำค่าข้ามการเปิดแอป
  - [x] pre-approve เฉพาะ tool ที่ "แค่ดู" (`read_page`, `get_page_text`, `find`, console/network, `tabs_context_mcp`) ส่วน navigate/click/type/upload/JavaScript ต้องขออนุมัติผ่าน try→refuse→ask→retry เดิม — tool ที่ไม่รู้จักถือเป็นต้องขออนุมัติไว้ก่อน
  - [x] ข้อควรระวัง: เนื้อหาเว็บเป็น untrusted input และตอนนี้อ่านจาก browser ที่ login อยู่ ระบบ prompt สั่งให้ถือข้อความในหน้าเว็บเป็นสิ่งที่ "รายงาน" ไม่ใช่ "คำสั่งให้ทำตาม"
  - [x] ขับจริงในแอปแล้ว (ไม่ใช่แค่ unit test): ถามลอยๆ **โดยไม่มี project** ก็เข้าเส้นทาง agent ได้ โมเดลเรียก browser tool เองโดยไม่มีการ์ดขออนุมัติ (เพราะเป็น tool อ่าน) และเมื่อสั่ง `navigate` ถูกปฏิเสธ ก็รายงานตรงๆ ว่า "ยังไม่ได้เปิดแท็บ ยังไม่ได้ปิดอะไร" ไม่แกล้งทำเป็นสำเร็จ
  - [x] การกระทำในเบราว์เซอร์ (scroll/คลิก/พิมพ์/เปิดหน้า) ขออนุมัติผ่าน try→refuse→ask→retry เดิม
    - [x] `scroll` = tool `computer` ซึ่งครอบคลิกและพิมพ์ด้วย — `--allowedTools` แยกระดับ argument ไม่ได้ การ์ดจึงต้องเขียนขอบเขตจริง ห้ามเขียนแคบแล้วให้กว้าง
    - [x] `ActionClass.browserAction` แยกจาก `.localWrite` — การ์ดเคยพาดหัวว่า "Send to Claude?" และ "Writes files in the project" ซึ่งผิดทั้งคู่สำหรับการคลิกในหน้าเว็บ
    - [x] `offerToWiden` ต้องไม่บังคับ project — งานเบราว์เซอร์ไม่สังกัด project เคยทำให้การ์ดไม่ขึ้นเงียบๆ และความสามารถนั้นเข้าไม่ถึงเลย
    - [x] ข้อความปฏิเสธของ browser tool คือ "requires permission" ไม่ตรงกับวลีของ Claude Code — `isPermissionRefusal` ต้องรู้จัก แต่เฉพาะกับ browser tool เท่านั้น (วลีนี้กว้างเกินไป)
  - [x] ชั้นอนุมัติมี **สองชั้น** และแอปคุมได้ชั้นเดียว: allowlist ของแอป กับ site permission ของ extension เอง (ข้อความ "Claude in Chrome requires permission") ชั้นหลังต้องกด allow ใน Chrome — ไม่เข้า `offerToWiden` ของแอป และไม่ควรพยายามทำให้เข้า
  - [x] extension เห็นเฉพาะแท็บที่ถูกแชร์เข้า session (กดไอคอน Claude ที่แท็บ) ไม่ใช่ทุกแท็บที่เปิดอยู่
  - [x] ต้องมี Claude in Chrome extension (≥1.0.36) และ login แบบ subscription — ถ้าใช้ API key Claude Code จะปิด Chrome integration เอง แม้ส่ง `--chrome` ไป (แอป strip `ANTHROPIC_API_KEY` อยู่แล้ว)

## Phase 6.1: ติดตามตามเวลาจริง (`/loop`)

- [x] แอปติดตามเรื่องที่ user สั่งไว้ตามเวลาจริงได้ — ทุก N นาที Secretary ถามตัวเองด้วยคำถามที่ค้างไว้ แล้วตอบลงในสายแชท (เกิดจากงานจริง: คุม workshop อยู่ พิมพ์ไม่ได้ ต้องรู้ว่าถึงหัวข้อไหน)
- [x] โมเดล **ไม่มีนาฬิกาและไม่ได้รันอยู่ระหว่างข้อความ** — prompt ของแต่ละรอบต้องบอกเวลาจริงไปด้วย ไม่งั้นมันเดาเวลาจากบริบทเก่า
- [x] เข้าได้สองทาง เข้าโค้ดชุดเดียวกัน
  - [x] `/loop 10m <จะรายงานอะไร>` · `/loop stop` · `/loop` = ดูสถานะ (`/track` เป็น alias) รับ `10`, `10m`, `10 min`, `10 นาที`, `1h`, `90s` เพราะพิมพ์มือเดียวตอนกำลังยุ่ง
  - [x] โมเดลตั้งเองตามบริบทด้วย block ```loop (`every: 10m` + บรรทัดถัดไปคือสิ่งที่จะรายงาน) — **ห้ามเดาจากร้อยแก้ว** เหตุผลเดียวกับ ```choices: โมเดลพูดว่า "จะคอยดูให้นะ" ตลอดเวลา ถ้าเดาจะได้ timer ที่ไม่มีใครสั่ง
- [x] กฎที่ห้ามหาย เพราะเป็นสิ่งที่ทำให้ "ของที่พูดเองได้" ยังปลอดภัย
  - [x] ประกาศในแชททุกครั้งที่เริ่ม พร้อมวิธีหยุด และมี badge ⏱ ที่ header กดหยุดได้ 1 คลิก — ข้อความประกาศ scroll หายไปได้ แต่คำตอบที่โผล่มาเองต้องมีคำอธิบายอยู่บนจอเสมอ
  - [x] ทุกรอบแทรก activity box บอกว่านี่คือ loop check **โดยไม่สนค่า toggle activity** เพราะนี่ไม่ใช่ขั้นตอนของงานที่ user สั่ง แต่เป็น "เหตุผลที่มีข้อความที่ไม่มีใครขอ"
  - [x] ขอบเขต: 1 นาที – 2 ชั่วโมง และหยุดเองเมื่อครบ 12 ชั่วโมง (`LoopSchedule`) ใช้กับทั้งคำสั่งของ user และของโมเดล — อย่างแย่สุดจึงเป็น timer ที่เห็นอยู่ มีขอบเขต และกดหยุดได้
  - [x] session-only ไม่เขียนลง disk — loop ผูกกับสิ่งที่เกิดขึ้นตอนนี้ ถ้ารอดข้ามการเปิดแอป มันจะตื่นมาถามเรื่องตารางที่จบไปแล้ว (เหตุผลเดียวกับ write/browser grant)
  - [x] ห้ามยิงทับ: `streamingTask` เป็น single-flight ถ้ายิงตอนกำลังตอบจะ cancel คำตอบที่ user กำลังอ่าน — ถ้าไม่ idle ให้เลื่อนไปรอบหน้า (`postponed`) และไม่นับว่าส่งแล้ว
  - [x] `.beginExecuting` ออกจาก `.idle` ไม่ได้ — tick ต้องส่ง `.userBeganInput` → `.beginInterpreting` เหมือนข้อความที่ user พิมพ์ และต้องเข้า `startChat` ตรงๆ ไม่ผ่าน intent classifier (คำของเราเองอาจถูกอ่านเป็นคำสั่งแล้วไปรัน tool ที่ไม่มีใครสั่ง)
  - [x] ตัวจับเวลาอยู่ใน `Secretary` ไม่ใช่ใน view — loop ต้องเดินต่อแม้ปิดหน้าต่างแชท เพราะคนที่สั่งกำลังมองห้องประชุม ไม่ได้มองจอ

## Phase 6.7: เพิ่ม Token Usage
- [x] สามารถ chat ถาม AI usage token ได้ — `/usage` (หรือ `/tokens`) ตอบเป็นตารางในสายแชท
- [x] มี windows ที่เปิดได้จาก menu icon แล้วแสดง usage token ได้ — เมนูแถบสถานะ → Token Usage (⌘U)
  - [x] **เปิดค้างไว้ได้** เป็นหน้าต่างของตัวเอง ไม่ใช่แผงในกล่องแชท — ปิดแชทแล้วตัวเลขต้องไม่หายไปด้วย และ observe `Secretary.sessionUsage` จึงอัปเดตสด เปิดทิ้งไว้ก่อนถามคำถามแรกก็เห็นตัวเลขไหลเข้ามาเอง
- [x] **แก้บั๊ก: อ่าน cache token ตกไปทั้งสองก้อน** — `result` event ส่ง token มา 4 ก้อน แต่โค้ดอ่านแค่ `input_tokens` กับ `output_tokens` เทิร์นที่วัดจริงได้ `in=2 out=5` ทั้งที่ traffic จริงคือ 11,768 cache write + 24,436 cache read รวม **36,211** — ไม่ใช่แค่ไม่ครบ แต่ผิดคนละ order of magnitude และตัวเลขนี้ถูกเขียนลง audit log มาตลอด
  - แยก 4 ก้อนไว้ ไม่รวมเป็นเลขเดียว เพราะราคาต่างกันมาก (cache read ถูก, cache write แพง) และเป็นตัวบอกว่าบทสนทนายาวขึ้นแล้วจ่ายอะไรอยู่
  - **context ใช้ค่าของเทิร์นล่าสุด ไม่ใช่ผลรวม** — คำถามคือ "ตอนนี้ context เต็มแค่ไหน" ถ้าบวกสะสมจะทะลุ 100% ทั้งที่ยังว่างอยู่เยอะ (`contextWindow` อ่านจาก `modelUsage` ซึ่ง key เป็นชื่อโมเดล ต้องขุด ไม่ใช่ path ตายตัว)
  - **ตัวเลขเงินต้องมีคำกำกับเสมอ** — Claude Code ส่ง `total_cost_usd` มาแม้ใช้ subscription ซึ่งไม่ได้ถูกตัดเงินต่อ token เลขดอลลาร์ลอยๆ ในแชทอ่านแล้วเข้าใจว่าโดนเรียกเก็บ มีเทสบังคับว่าสรุปทุกครั้งต้องมีคำอธิบายติดไปด้วย
- [ ] ยังทำไม่ได้: โควตาของ subscription (แบบที่ `/usage` โหมด interactive โชว์ 5 ชั่วโมง/สัปดาห์) — ไม่มีใน stream, CLI ไม่มี subcommand, และไม่มี cache ใน `~/.claude` ต้องยิง endpoint ของ Anthropic เองซึ่งเกินขอบเขต "หน้ากากทับ Claude Code"

## Phase 7: Loop & Notification
- [ ] สั่งให้ loop ได้ เช่น นับถอยหลัง 5 นาทีแล้วแจ้งเตือน หรือ long run แล้วแจ้งเตือนได้
- [ ] มี local notification เมื่อทำงานเสร็จ (notification settings ตาม macOS)
- [ ] เมื่อ click ที่กล่อง notication, จะเปิด app และ chat window ขึ้นมา

## Phase 8: Multi-session
- [ ] สามารถเปิด chat bubble ได้มากกว่า 1 window โดยที่แต่ละ window จะแยก Claude Session ออกจากกัน
- [ ] แยก settings ตาม chat window ของใครของมัน แปลว่า แต่ละ chat จะแยก model, effort ได้
- [ ] ถ้ามี Project อยู่แล้ว แล้วขึ้น session ใหม่ ให้ใช้ project เดิมเลย แต่สามารถเพิ่ม project ได้ 
- [ ] project ที่เพิ่มใหมม่ใน session ใหม่ จะไม่เห็นใน session เดิม
- [ ] chat window ที่ 2,3 จะไม่มี Profile จนกว่าจะปิดจนเหลือ session (window) เดียว app ก็จะแสดงกลับมา
- [ ] จำ session history ได้ 
- [ ] เพิ่ม menu Sessions ใน Menu bar
  - [ ] ตั้งชื่อเมนูสั้นๆ ให้ด้วย ตาม context ที่คุยกัน  
  - [ ] ถ้า click ที่ session ใน menu จะเปิด chat bubble แล้วคุยต่อ (resumr session) ได้เลย
  - [ ] แต่ละ session ใน menu มีปุ่มปิด ถ้าปิดก็ลบ history ไปเลย

## Phase 8.1 : Info-window
- [ ] สามารถเอาข้อมูลไปเปิด window ลอยๆ ค้างไว้ได้ เช่น เมื่อถามข้อมูลอะไรบางอย่าง แล้วได้เป็นตาราง ก็บอก app ได้ว่า แสดงข้อมูลนั้นแยกออกจาก chat หรือแสดงข้อมูลนั้นแยก window ก็จะดึงข้อมูลที่คุยกัน (ในส่วนที่ระบุ) ออกไปเป็น window แยกได้
- [ ] แสดงได้หลาย window
- [ ] ปิดได้, hide ได้ (กดปุ่มปิด คือปิดและลบ, กด Esc คือ hide)
- [ ] list ของ windows แสดงอยู่ในกลุ่มเมนู Windows ที่เปิดได้จาก menu icon และกดลบได้จากเมนูนั้นๆ
- [ ] กดที่เมนูก็แสดง window นั้นขึ้นมา
- [ ] ใรเมนู Windows มีเมนู Clear all (อยู่ล่างเสมอ) เพื่อ clear ทุก windows ที่มีอยู่

## Phase 9: Talk to each other

- [ ] Two or more app be able to talk to each other.
- [ ] First, brainstorm about the feasible that can made 2 or more AI-Secretary app can talk to each other.
- [ ] Second, its can do the same project (or projects) with different role (configure with .md file in the project somehow)

## Phase 10: Voice

- [ ] Push-to-talk or explicit voice activation.
- [ ] Speech-to-text, text-to-speech, interruption behavior, and privacy controls.
- [ ] Voice must follow the same approval and auditing model as chat.

## Defered
  - [ ] ยังไม่ได้พิสูจน์: MCP tool ที่มีผลออกนอกเครื่อง (ส่งเมล/สร้าง event) ถูกจัดเป็น `.localWrite`และการ์ดขออนุมัติขึ้นข้อความ "Send to Claude?" ซึ่งน่าจะสื่อผิด — ต้องทดสอบก่อนถือเป็นบั๊ก
