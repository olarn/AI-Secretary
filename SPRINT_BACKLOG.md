# Sprint Backlog

งานของ sprint ที่กำลังทำอยู่ ติ๊กแล้วคือ ship แล้ว

Sprint 14 จบทั้งสปรินต์ บันทึกทุกอย่างอยู่ใน `PRODUCT_BACKLOG.md`:

| หัวข้อใน `PRODUCT_BACKLOG.md` | เวอร์ชัน |
| --- | --- |
| Sprint 14-1 / 14-2 — Character คุยกันเอง และส่งงานให้กันได้ | v0.14.229–246 |
| Sprint 14.3 — ปิดโดยไม่มีโค้ดใหม่ | — |
| Sprint 14.4 — ตัวละครหายใจตอนคิด | v0.14.259–260 |
| Sprint 15 — permission ที่จำได้ข้าม session | v0.15.269–270 |

หัวข้อใน `PRODUCT_BACKLOG_NEXT_SPRINTS.md` ใช้เลขหลอก (`xxx`, `yyy`, `zzz`, `zzzz`)
เพราะเจ้าของยังไม่ได้ตัดสินว่าอันไหนเป็นสปรินต์ที่เท่าไร — **ที่นี่คือที่เดียวที่เลขสปรินต์เป็นของจริง**

## Sprint 15.2  กันร้อยแก้วไม่ให้ถูกตีความเป็นคำสั่ง git

เจอจากการขับจริง (2026-08-17): ย่อหน้าภาษาอังกฤษเรื่องธุรกิจบริหารหนี้ ~300 ตัวอักษร
ถูกตอบกลับว่า *"No registered project matches …"* แล้วเทิร์นจบตรงนั้น **โมเดลไม่เคยถูกเรียก**
คนใช้เห็นเป็นอาการ "แอปนิ่ง" ทั้งที่ state machine กลับไป `IDLE` เรียบร้อย

ลูกโซ่: คำว่า `status` ใน "legal **status**" เข้ากฎ git ที่ `Intent.swift:120` →
`projectQuery(in:)` ที่ `Intent.swift:265` คว้าทุกอย่างหลัง `" in "` ตัวแรก
("specializing **in** non-performing…") มาเป็นชื่อโปรเจกต์ยาวทั้งย่อหน้า →
resolve ไม่เจอ → `finish(success: false)` ที่ `Secretary.swift:3157` ปิดเทิร์น
ที่ `Secretary.swift:665-675` มีแค่ `.unknown` เท่านั้นที่ไปถึง `startChat`

ไม่ใช่บั๊กเฉพาะประโยคนี้: **ข้อความอังกฤษใดก็ตามที่มี `status` / `log` / `branch` /
`changes` / `history` เป็นคำเต็ม บวกกับมี `" in "` / `" for "` / `" on "` จะถูกดูดเข้า
git tool call แล้วไม่มีวันไปถึงโมเดล** ร้อยแก้วเชิงธุรกิจโดนเงื่อนไขนี้บ่อยมาก

รากของเรื่องคือความไม่สมมาตรในไฟล์เดียวกัน — `fileIntent` มีเกราะครบ (strong/weak prefix,
บังคับ `looksLikePath`, คอมเมนต์บทเรียนที่ `Intent.swift:45-59`) ส่วน `codeToolIntent`
ไม่ได้เกราะพวกนั้นเลยสักอย่าง งานรอบนี้คือย้ายเกราะชุดเดียวกันไปติดอีกฝั่ง

- [ ] **Guard 1 — ชื่อโปรเจกต์ต้องหน้าตาเหมือนชื่อ**
  - [ ] เพิ่มฟังก์ชันบริสุทธิ์ `looksLikeProjectName(_:) -> Bool` วางคู่ `looksLikePath`
        ผ่านเมื่อ: ยาวไม่เกิน 60 ตัวอักษร **และ** ไม่เกิน 5 คำ **และ** ไม่มี `,` `.` `(` `)` `;` `:`
  - [ ] ตัวเลข 60 กับ 5 ต้องมีคอมเมนต์ why อ้างเคสนี้ (ย่อหน้า ~300 ตัวอักษร ~50 คำ
        ถูกส่งเป็นชื่อโปรเจกต์) — ตัวเลขที่อ่านจากโค้ดไม่ได้ว่ามาจากไหน ต้องมี why เสมอ
  - [ ] เปลี่ยนวิธีเลือก occurrence: ตอนนี้วนตามลำดับ marker `[" in ", " for ", " on "]`
        แล้วคืน**อันแรกที่เจอ** ซึ่งไม่ใช่อันที่อยู่ต้นสุดในข้อความ → เปลี่ยนเป็นสแกนทุก
        occurrence ของทุก marker แล้วเอา**อันท้ายสุดที่ tail ผ่าน `looksLikeProjectName`**
        เพราะชื่อโปรเจกต์อยู่ท้ายประโยคเสมอ ไม่เจอเลย → `.none()`
  - [ ] **`looksLikeProjectName` ต้องใช้ร่วมกันทั้ง `projectQuery(in:)` (บรรทัด 265) และ
        `splitProject` (บรรทัด 237)** — สองอันนี้เป็นตรรกะ marker ที่เกือบซ้ำกัน ใส่เกราะ
        ที่เดียวแล้วอีกทางยังส่งย่อหน้าทั้งก้อนเข้า file path ได้อยู่
  - [ ] ห้ามแตะคอมเมนต์เรื่อง crash จากการ slice สำเนา lowercased ใน `splitProject`
        นั่นเป็นบันทึกบั๊กจริง ("Range requires lowerBound <= upperBound" จากข้อความไทยที่มี " On ")

- [ ] **Guard 2 — คีย์เวิร์ด git เป็นคำสั่งได้เฉพาะตอนข้อความมีรูปเป็นคำสั่ง**
  - [ ] ใน `codeToolIntent` ก่อนแมตช์กฎ ต้องผ่านเงื่อนไข "ข้อความเป็นประโยคเดียว" —
        ไม่มีขอบประโยคภายใน (`.` `?` `!` ที่ตามด้วยช่องว่างแล้วมีเนื้อความต่อ)
        ไม่ผ่าน → `.none()` → ตกไปเป็นแชท
  - [ ] **ใช้เกณฑ์เชิงโครงสร้าง ห้ามนับจำนวนคำ** — บทเรียนแผง Settings บอกว่าตัวเลขที่จูนไว้
        ถูกทำให้เกินได้เสมอ ส่วน "ประโยคเดียว" ไม่มีปุ่มให้หมุน
  - [ ] **ห้ามใส่ทางลัด "ถ้ามีคำว่า `git` ให้ข้ามเงื่อนไข"** — เปิดรูเดิมกลับมา และเคสนี้ไม่ต้องใช้

- [ ] **Guard 3 — invariant ที่บันทึกไว้ก่อน ยังไม่ต้องทำ**
  - [ ] เขียนคอมเมนต์ที่ `handleTool` ว่า **การจัดประเภทผิดต้องตกลงไปเป็นแชท ห้ามจบเทิร์น**
        ซึ่งเป็นยาที่รักษาอาการ "นิ่ง" โดยตรง พอมี Guard 1+2 แล้ว `.notFound` จะเกิดเฉพาะกับ
        query ที่หน้าตาเหมือนชื่อโปรเจกต์จริงๆ ซึ่งข้อความปฏิเสธเป็นคำตอบที่**ถูกต้อง** จึงยัง
        ไม่แก้ — **แต่ต้องบันทึกไว้ให้คนที่มาทีหลังรู้ว่าที่ไม่ทำคือตั้งใจ ไม่ใช่ลืม**

- [ ] **เทส** — `Tests/SecretaryCoreTests/ProseIsNotACommandTests.swift` (ไฟล์ใหม่)
      ทุกอย่างเป็นฟังก์ชันบริสุทธิ์ใน library target จึงนับ coverage ได้
  - [ ] fixture ของจริง: ย่อหน้าข้างล่างนี้ **คัดลอกทั้งก้อนแบบตรงตัวอักษร** เป็น constant
        พร้อมคอมเมนต์ว่าเจอเมื่อไหร่ ต้องได้ `.unknown`

        ```
        Alpha Capital Group is a company specializing in non-performing asset management through its operating subsidiaries, Alpha Capital Asset Management Co., Ltd. (Alpha) and Wireless Asset Management Co., Ltd. (WAMC). The group manages non-performing loan (NPL) portfolios and non-performing assets (NPA), including property sales, borrower follow-up, collection, legal status, collateral management, customer enquiries, and related service processes
        ```

        **ห้ามย่อ ห้ามแต่ง** — คุณสมบัติที่ทำให้มันเป็น fixture มีสามอย่างพร้อมกันในก้อนเดียว
        และหายไปทันทีถ้าเขียนใหม่: มี `status` เต็มคำ (ใน "legal status"), มี `" in "`
        (ใน "specializing **in**"), และ**มีขอบประโยคหลายจุด** ซึ่งเป็นอย่างเดียวที่ทดสอบ
        Guard 2 ได้จริง — ข้อความประโยคเดียวสั้นๆ ที่มี "legal status" กับ `" in "` จะ*ผ่าน*
        เงื่อนไขประโยคเดียวแล้วยังจัดประเภทผิดอยู่ ต้องกันด้วย Guard 1 แทน
        เขียนเทสแยกให้ครอบทั้งสองทาง
  - [ ] ร้อยแก้วอื่นที่มี `status` / `log` / `branch` / `changes` / `history` เต็มคำ + มี `" in "`
        ต้องเป็นแชท
  - [ ] `looksLikeProjectName` ตรงๆ: `"AI-Secretary"` ผ่าน, ย่อหน้าไม่ผ่าน, `""` ไม่ผ่าน
  - [ ] **regression must-hold: เทสสี่ตัวใน `KeywordBoundaryTests.swift` ต้องเขียวโดยไม่ถูกแก้**
        (`testTheWordThatStartedThis`, `testKeywordsBuriedInLongerWordsAreNotCommands`,
        `testRealCommandsStillClassify`, `testPunctuationCountsAsABoundary`)
        ถ้าต้องแก้เทสเดิมให้ผ่าน แปลว่าออกแบบผิด ไม่ใช่เทสผิด
  - [ ] เคสที่พังเงียบง่ายที่สุดคือ `"which branch am I on?"` — tail หลัง `" on "` เป็น `""`
        หลัง trim `?` ต้องได้ `.none()` แล้ว**ยังต้องถูกจัดเป็นคำสั่งอยู่ผ่าน Guard 2**

- [ ] เรียกสกิล `swift-functional-programming` ก่อนแตะ `.swift` ไฟล์แรก
- [ ] bump `AppVersion.swift` +2 (Guard 1, Guard 2)
- [ ] **ขับแอปจริง**: พิมพ์ย่อหน้านั้นซ้ำ ต้องได้คำตอบจากโมเดล ไม่ใช่ข้อความปฏิเสธ —
      unit test ไม่นับเป็นหลักฐานว่า UI ทำงาน

## Sprint 16  Classifier หลบทางให้ agent

มาจากการวิเคราะห์ 2026-08-17: `RuleBasedIntentClassifier` เกิดในสปรินต์แรกๆ ตอน backend
เป็น bare API ที่ไม่มีมือมีเท้า (`Intent.swift:6` เขียนเองว่า "for this sprint") วันนี้ backend
หลักคือ Claude Code agent ที่มีเครื่องมืออ่านไฟล์/รัน git ของตัวเอง และ `agentSystemPrompt`
ก็สั่งไว้แล้วว่า "look for yourself" — แต่ `beginTurn` (`Secretary.swift:662`) ยังเรียก
`classify` ทุกเทิร์นโดยไม่ดูว่า backend เป็นแบบไหน ผลสามอย่าง:

1. **ไม่ correct** — ผลของ local adapter ไม่เคยเข้า session ของ agent:
   `ClaudeCodeProvider` ส่งเฉพาะข้อความ user ล่าสุดแล้ว `--resume` (บันทึกไว้ที่
   `Secretary.swift:713` เรื่อง `unseenReports`) พิมพ์ "diff in X" แล้วตามด้วย
   "อธิบายหน่อย" โมเดลไม่รู้ว่า diff ไหน — bug class เดียวกับที่เคยตอบ
   "ยังไม่มีอะไรให้สรุปเลยค่ะ" ทั้งที่คำตอบอยู่บนจอ
2. **ไม่ seamless** — keyword เป็นอังกฤษล้วน: "อ่าน README.md" ได้ agent (เก่งกว่า),
   "read README.md" ได้ adapter (จำกัดกว่า) พฤติกรรมแยกตามภาษาที่พิมพ์
3. Sprint 15.2 คือการติดเกราะให้ classifier — สปรินต์นี้ทำให้เส้นทางหลักไม่ต้องพึ่งเกราะนั้น
   เลย **ทำหลัง 15.2 เพราะเกราะยังจำเป็นกับ fallback** (ดู "อะไรไม่เปลี่ยน" ข้างล่าง)

- [ ] **ทางหลัก: มี workspace tools = ทุกข้อความเป็นแชท**
  - [ ] ใน `beginTurn` ก่อนเรียก `classify`: ถ้า
        `(chatProvider as? WorkspaceScopedProvider)?.hasWorkspaceTools == true`
        ให้ไป `startChat` ตรงๆ — เงื่อนไขเดียวกับที่ `systemPrompt`
        (`Secretary.swift:3867`) ใช้เลือก `agentPrompt` อยู่แล้ว สองที่นี้ต้องตัดสิน
        จากคำถามเดียวกันเสมอ ไม่งั้นจะเกิด "prompt บอกโมเดลว่ามีมือ แต่ turn ถูก adapter ดัก"
  - [ ] audit ยังต้องได้ entry `intentClassified` เขียนเหตุผลว่า "agent-mode: chat" —
        เส้น audit trail ต้องอ่านออกว่าทำไมเทิร์นนี้ไม่ผ่าน classifier
  - [ ] `help` ที่ดักใน `submit` (`Secretary.swift:598`) คงไว้ — เป็น local ล้วน ไม่เกี่ยวกับ
        backend
- [ ] **หน้าต่าง detection ยังไม่จบ** — `hasWorkspaceTools` เป็น false จนกว่า detector
      จะรายงาน (`ChatBackend.swift:142` บอกเองว่า "detection has usually not finished"
      ตอนเปิดแอป) ข้อความแรกๆ หลังเปิดแอปจะยังผ่าน classifier
  - [ ] ยอมรับพฤติกรรมนี้ ไม่ต้องรอ detection — มันคือพฤติกรรม fallback ที่ถูกต้องของ
        โมเมนต์นั้น แต่**ต้องมีคอมเมนต์ why ตรงเงื่อนไข** ว่าหน้าต่างนี้มีจริงและตั้งใจปล่อย
        ไม่ให้คนมาทีหลังเห็นว่า "บางทีก็ classify บางทีก็ไม่" แล้วคิดว่าเป็นบั๊ก
- [ ] **อะไรไม่เปลี่ยน — เขียนกันไว้ก่อนลงมือ**
  - [ ] chat-only fallback (ไม่มี Claude Code / detection ล้มเหลว) ใช้ classifier + adapter
        เหมือนเดิมทุกอย่าง — ที่นั่น bare API ทำเองไม่ได้จริงๆ และ `chatOnlySystemPrompt`
        ออกแบบคู่กับมัน (สอนผู้ใช้พิมพ์ "list files in …")
  - [ ] เกราะของ Sprint 15.2 ห้ามถอด — fixture ย่อหน้า Alpha Capital ต้องยังเขียวใน
        โหมด fallback และเทสสี่ตัวใน `KeywordBoundaryTests.swift` ต้องเขียวโดยไม่ถูกแก้
  - [ ] `handleTool` / adapter / `Permissions` ไม่แตะ — ยังเป็นเส้นทางของ fallback
- [ ] **helpText สองความจริง** — ข้อความ help ปัจจุบัน (`SecretaryPrompts.swift:235`)
      สอนคำสั่ง "status / read / list" ซึ่งหลังสปรินต์นี้เป็นจริงเฉพาะโหมด fallback
  - [ ] แยกเป็นสองข้อความตามโหมด หรือเขียนใหม่ให้ไม่สอนสิ่งที่โหมด agent ไม่ทำแล้ว —
        เลือกตอนลงมือ แต่ห้ามปล่อยให้ help สอนคำสั่งที่พิมพ์แล้วพฤติกรรมไม่ตรงคำสอน
- [ ] **เทส** — ฟังก์ชันบริสุทธิ์ + `Secretary` กับ provider ปลอม
  - [ ] provider ปลอมที่ `hasWorkspaceTools == true`: "read README.md in AI-Secretary",
        "status in AI-Secretary", ย่อหน้า Alpha Capital — ทั้งหมดต้องถึง `startChat`
        ไม่มีอันไหนแตะ adapter
  - [ ] provider ธรรมดา: ชุดเดียวกันต้อง classify เหมือนก่อนสปรินต์นี้ทุกตัว
  - [ ] ลำดับ: provider เริ่ม false แล้วพลิกเป็น true ระหว่าง session — เทิร์นก่อนพลิกใช้
        classifier เทิร์นหลังพลิกไม่ใช้
- [ ] เรียกสกิล `swift-functional-programming` ก่อนแตะ `.swift` ไฟล์แรก
- [ ] bump `AppVersion.swift` +1
- [ ] **ขับแอปจริง**: (1) "read README.md in AI-Secretary" ต้องได้คำตอบจาก agent ที่อ่าน
      ไฟล์เอง (2) "diff in <project>" แล้วตามด้วย "อธิบายหน่อย" — คำตอบที่สองต้องรู้เรื่อง
      diff เพราะทั้งคู่อยู่ใน session เดียวกันแล้ว ซึ่งเป็นสิ่งที่ก่อนสปรินต์นี้ทำไม่ได้

## Sprint 17  หยุดไล่เก็บ keyword — ยกความเข้าใจ hand-off ให้โมเดล

`DelegationIntent.swift` บันทึกประวัติตัวเองไว้แล้ว: ขยาย `addressPhrases` สองรอบ
ในวันเดียว (2026-08-14) และรอบที่สองจดไว้ว่าเคสที่หลุดไปถึงโมเดล **"did the right thing
through the block"** — โมเดลอ่านภาษาเก่งกว่า substring matching บนภาษาที่ไม่มีวรรค
และ ```to block ก็รับหลายชื่อแล้วตั้งแต่ 0.14.242 ข้อจำกัดที่เคยบังคับให้โต keyword
ถูกแก้ไปแล้ว สปรินต์นี้กลับทิศ: **โค้ดเลิกพยายามอ่านเก่ง แล้วเหลือหน้าที่เดียวคือถามเมื่อชัด
ว่าเป็นการฝากงาน** ส่วนการอ่านที่เหลือเป็นของโมเดลผ่าน block ที่มี enforcement ครบอยู่แล้ว
(`HandOffBlock.parse` ที่ `Secretary.swift:2980,3088` — เทียบชื่อกับ roster, ชื่อแปลก
ถูกถามกลับ ไม่เดา)

**กติกา charter สองข้อที่สปรินต์นี้ห้ามแตะ** — ไม่ใช่ของที่ "AI ทำอยู่แล้ว":

- *never act silently on a guess* — ทางที่ตัดสินเองได้มีทางเดียวคือ block ที่โมเดลเขียน
  ชัดๆ ซึ่งเป็น explicit format ไม่ใช่การเดาจากร้อยแก้ว และชื่อที่ไม่ตรง roster ยังต้องถาม
- `HandOffBlock` เกิดเพราะโมเดลเคยรายงานว่าส่งแล้วทั้งที่ไม่มีอะไรถูกส่ง (Ditto +
  `SendMessage`, `HandOffBlock.swift:12-15`) — การ deny ตัว tool และการส่งจริงผ่าน
  แอปเท่านั้น คือ enforcement ที่ prompt แทนไม่ได้

- [ ] **หด `addressPhrases` เหลือเฉพาะคำที่คุ้มค่าคำถาม**
  - [ ] ตัดคำที่กว้างจนจับประโยคธรรมดา: `จาก`, `from `, `send`, `get `, `have `,
        `message` — ทุกตัวในนี้แมตช์ประโยคที่แค่*พูดถึง*ตัวละคร แล้วผลคือคำถามคั่นจังหวะ
        ("Should I pass this to …?") กับงานที่ไม่เกี่ยว เคสจริงที่เคยพลาดเพราะคำพวกนี้
        ("ขอราคา … จาก Pikachu และ Ditto") วันนี้ตกไปถึงโมเดลแล้วโมเดลออก block เองได้
  - [ ] คำที่เหลือ ต้องมีคอมเมนต์ why ต่อคำ ว่าประโยคแบบไหนที่มันจับแล้ว*ควรถาม*จริง
  - [ ] **เขียน freeze ไว้บนหัว list**: ห้ามขยายอีก — เคสที่หลุดคือหน้าที่ของโมเดล ไม่ใช่
        สัญญาณให้เติมคำ คอมเมนต์สองรอบของ 2026-08-14 คงไว้เป็นหลักฐานว่าทำไม
  - [ ] `handOffPhrases` (ฝากถาม/ขอให้/ask/tell) คงไว้ทั้งชุด — ความหมายแคบ จับแล้ว
        เป็นการฝากงานจริงเกือบเสมอ และเป็นตัวเดียวที่ยังให้ `.confident` ได้
- [ ] **`.confident` จากร้อยแก้วเหลือกรณีเดียว** — hand-off phrase ชัด + ชื่อเดียว
      (เคส `(1, true, _)` เดิม) นอกนั้นร้อยแก้วให้ได้อย่างมากแค่ `.unsure` = คำถาม
      เคสหลายชื่อ (`(2..., _, true)` ที่พึ่ง `namesAreJoined`) เปลี่ยนเป็นถามเสมอ —
      conjunction ตรวจด้วย substring บนภาษาไม่มีวรรคคือการเดา และผู้รับผิดคนไม่มี undo
      เคสหลายชื่อที่มั่นใจได้ให้เป็นของโมเดลผ่าน block ซึ่งเขียนชื่อผู้รับตรงๆ ทีละบรรทัดเดียว
- [ ] **ตรวจว่าเส้นโมเดลรับน้ำหนักได้ก่อนตัด** — ก่อน merge ต้องยืนยันในแอปจริงว่า
      prompt ฝั่ง agent มีคำอธิบาย ```to block และโมเดลใช้มันเมื่อผู้ใช้พิมพ์ประโยค
      ที่เคยพึ่ง keyword ที่ถูกตัด ("ขอราคา … จาก Pikachu และ Ditto" ต้องไปถึงทั้งสองคน)
      — ถ้าโมเดลไม่ออก block ในเคสนี้ แปลว่ายังตัด keyword ไม่ได้ หยุดแล้วกลับมาคุยก่อน
- [ ] **อะไรไม่เปลี่ยน**
  - [ ] `answerItYourselfChoice` และ picker ถามผู้รับ — ทางออกเมื่ออ่านผิดต้องอยู่ครบ
  - [ ] การเทียบชื่อกับ roster + ชื่อแปลกถูกถาม ใน `answerHandOff` และฝั่ง block
  - [ ] `stepwise` (แผนหลายขั้น step 1 ออกก่อน) — คนละเรื่องกับการอ่าน keyword
  - [ ] กติกา `shortestMatchableName` / `shortestMatchableFirstWord` — บันทึกบั๊กจริง
        ("The Assistant" เสนอ "the")
- [ ] **เทส** — `delegationIntent` เป็นฟังก์ชันบริสุทธิ์อยู่แล้ว เทสตรงๆ ได้
  - [ ] ทุกประโยคใน `handOffPhrases` + ชื่อเดียว → `.confident` เหมือนเดิม
  - [ ] "ขอราคา … จาก Pikachu และ Ditto" → `.none` (ไปโมเดล) — กลับทิศจากพฤติกรรม
        ปัจจุบันโดยตั้งใจ เขียนคอมเมนต์อ้างสปรินต์นี้ไว้ที่เทส
  - [ ] ประโยคที่*พูดถึง*ตัวละคร ("อาเนียบอกว่าอะไรนะ") → ต้องไม่เกิดคำถาม
  - [ ] `HandOffBlock` หลายชื่อ + ชื่อหนึ่งไม่อยู่ใน roster → ส่งเฉพาะที่ตรง และถามชื่อ
        ที่ไม่ตรง ไม่เดา
- [ ] เรียกสกิล `swift-functional-programming` ก่อนแตะ `.swift` ไฟล์แรก
- [ ] bump `AppVersion.swift` +1
- [ ] **ขับแอปจริง** สามฉาก: ฝากงานชื่อเดียวด้วย hand-off phrase (โค้ดจับ ส่งเลย),
      สองชื่อมี "และ" (โมเดลออก block ถึงทั้งคู่), ประโยคพูดถึงตัวละครเฉยๆ (ไม่มีคำถาม
      ไม่มีการส่ง) — ฉากที่สองคือฉากที่พิสูจน์ว่าสปรินต์นี้ไม่ได้ทำฟีเจอร์ถอย
