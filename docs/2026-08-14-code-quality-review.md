# รายงานวิเคราะห์คุณภาพโค้ดและโครงสร้างโปรเจกต์ — 2026-08-14

วัดจากโค้ดจริง ณ commit `57a4257` (v0.14.247): เทสรันจริง **1,072 เทส ผ่านทั้งหมด
(0 failures, 6.5 วินาที)**, coverage วัดด้วย `llvm-cov` = **83.0% (lines) /
79.0% (regions)** ของ library targets การสำรวจครอบคลุมทุก target ทั้ง domain
modules (~15,700 บรรทัด), app target (6,420 บรรทัด), และเทส (~14,000 บรรทัด)

## ภาพรวม

โครงสร้าง SwiftPM 8 source targets / 6 test targets วินัยหลายด้านอยู่ระดับแบบอย่าง:

- Bow isolation สะอาด 100% — ทุก target ผ่าน `FunctionalCore` ไม่มีใคร
  `import Bow` ตรง และ `Package.swift` บังคับเชิงโครงสร้างอยู่แล้ว
- การแยก DTO/domain ถูกทุกที่ (`Project`/`ProjectDTO`,
  `ProfileSelection`/`ProfileSelectionDTO`)
- ไม่มี SwiftUI view ไฟล์ไหน import `FunctionalCore` — มีแค่ `DomainBridge.swift`
  กับ `PlanUsageModel.swift` ที่ import และทั้งคู่ไม่ใช่ view
- ไม่มี TODO/FIXME, ไม่มี dead code, force-unwrap มีจุดเดียวทั้งรีโป
  (`SecretaryProfile.swift:150` — UUID คงที่ที่พิสูจน์ได้ว่า parse ผ่าน)
- เทสไม่มี skip, fixture ใช้ temp dir ถูกต้องหมด, ไม่มี network I/O,
  ไม่มี `XCTAssertNil` บน Bow `Option`
- `throws` มีเฉพาะขอบ Foundation/Codable ตามกติกา, `Date()` เป็น
  defaulted parameter ทุกจุดที่เป็น domain function

ปัญหาไม่ได้กระจาย — กระจุกอยู่ที่เดียวเป็นหลัก

## สิ่งที่ต้องแก้ เรียงตามน้ำหนัก

### 1. `Secretary.swift` คือ god object

4,153 บรรทัด, 8 top-level types, 115 ฟังก์ชัน, ~45 stored properties,
14 injected dependencies — 35% ของ `SecretaryCore` และใหญ่กว่า `Permissions` +
`ProjectRegistry` + `AssistantState` + `ToolAdapters` + `FunctionalCore`
รวมกัน MARK ของมันเองนับได้อย่างน้อย 15 ความรับผิดชอบ

และเป็นที่อยู่ของ violation เกือบทั้งหมดของรีโป:

- **57 จาก 67 จุด** ของ `.toOptional()` + `guard let` ทั้งรีโป — เก็บเป็น
  `Option` ที่ประกาศ แต่แกะแบบ imperative ทุกจุดใช้ type จึงเป็นแค่เอกสาร
  ไม่ได้คุ้มครองอะไร (เช่น `Secretary.swift:1169`, `:1278`, `:1599`)
- `private struct ReplyRun` (`:186-194`) — `var` 5 ตัว mutate ผ่าน `inout`
  ที่ `failReply` (`:2729`) ขัดกติกา §2 ตรงๆ
- เรียก `FileManager.default` ตรง 3 จุด (`:1625`, `:1692`, `:2094-2097`)
  ทั้งที่ inject `fileAdapter` ไว้แล้ว — จุดหลังยังทำ I/O จาก computed property
- `preconditionFailure` 2 จุด (`:3598`, `:3600`) encode invariant ที่
  type system แทนได้ด้วยการแยก enum

ส่วนที่แยกออกได้โดยไม่แตะ injected surface: prompt construction
(~500 บรรทัด, `:3649-4150`), folder watching, instruction-file execution
การ inject เองทำดีอยู่แล้ว (protocol-typed + in-memory defaults ครบ) —
ปัญหาคือ class เดียวเป็น seam ของทุกอย่าง

จุดเดียวกันนี้สะท้อนในเทส: `SecretaryCoreTests` ถือ 855 จาก 1,072 เทส (80%)

### 2. คีย์ API จริงค้างบนดิสก์โดยไม่มีอะไรใช้

`claude-api-key.txt` ที่ root มีคีย์ `sk-ant-api03…` จริง 108 ไบต์
ถูก gitignore ถูกต้อง (`.gitignore:18`) และ**ไม่เคยเข้า git** (ตรวจ
`git log --all` แล้วว่าง) แต่ไม่มีโค้ดใน `Sources/` อ่านมันเลย — แอปใช้
Claude Code CLI ของเจ้าของ และมีโค้ดที่*ลบ* `ANTHROPIC_API_KEY` ออกจาก
env ด้วยซ้ำ (`ClaudeCodeProvider.swift:719`) เป็นซากดีไซน์เก่า มีแต่
โอกาสรั่ว ไม่มีประโยชน์ → **ควร revoke ใน Anthropic console แล้วลบไฟล์**

### 3. บั๊กจริง: `screenMargin` มีเจ้าของสองคน ค่าไม่ตรงกัน

`Appearance.swift:93` ประกาศ `screenMargin = 16` (บอกว่าเป็น margin ที่
layout เว้นขอบจอ) แต่ layout จริงใช้ `screenMargin = 8` จาก
`CharacterInstance.swift:89` ซึ่งเป็นค่าที่ส่งเข้า `placeBubble`
(`CharacterInstance.swift:279`) → max-width ที่คำนวณใน
`Appearance.swift:95-96` แคบกว่าที่ layout อนุญาตอยู่ 8pt
แนวแก้: เจ้าของค่าต้องมีคนเดียว (ค่าคงที่ใน `SecretaryCore` ที่ทั้งคู่อ่าน)

### 4. เอกสารบรรยายสถาปัตยกรรมที่ถูกถอดไปแล้ว

- `README.md:110` — "Secrets live in the Keychain" แต่ไม่มีโค้ด Keychain
  ในรีโปเลย (ไม่มีไฟล์ไหน import `Security` / เรียก `SecItemAdd`)
  สตริง "Stored only in your Keychain" ใน UI (`AppearanceSettings.swift:184`)
  จึงเกินจริงด้วย
- `code/README.md:361-375` (stale ตั้งแต่ 27 ก.ค.) — ยังบรรยายโมดูล
  `Credentials/` และ `ClaudeChatProvider` ที่ไม่มีอยู่จริง และไม่พูดถึง
  `FunctionalCore` ที่เป็นฐานของทุก target — เป็นซากดีไซน์ API-key
  ชุดเดียวกับข้อ 2
- `README.md:95` "One suite per module" ไม่จริงตามตัวอักษร —
  `FunctionalCore` กับ `AISecretaryApp` ไม่มีเทส
- เลข version ตรงกัน (0.14.247) — อันนี้มี `VersionInSyncTests` คุมอยู่จริง

### 5. จุดอ่อนของเทสและ decision ที่ coverage มองไม่เห็น

- **assertion แบบ `contains` 233 จุด** ส่วนใหญ่เช็ค prompt ที่ generate
  (หนักสุด `AgentSessionTests` 29, `CharacterHandOffTests` 20) — ผ่านได้แม้
  prompt บวมสองเท่าหรือสลับลำดับ ควรค่อยๆ แทนด้วย exact equality ในจุดที่
  pin ได้
- `ChatPanelView.swift` ใหญ่ **2,114 บรรทัด** ~70 members มี seam ตาม
  โครงสร้างตัวเองอยู่แล้ว (settings pane, markdown rendering, projects,
  skills, badges, key monitors) แยกได้ทีละส่วน
- decision logic ~9 จุดยังอยู่ใน `AISecretaryApp` ที่ coverage มองไม่เห็น
  ขัดกติกา charter — เด่นสุด: clamp ขนาดหน้าต่าง `InfoWindows.swift:74-77`,
  cascade placement `InfoWindows.swift:157-163`, สูตร resize + sign flip
  `ChatPanelView.swift:395-428` (doc comment บันทึกบั๊ก oscillation ที่มัน
  กันไว้เอง — สมควรมีเทสที่สุดแต่มีไม่ได้ในที่ปัจจุบัน), clamp ความสูง
  message box `ChatPanelView.swift:336-342`, กติกา font
  `max(9, secondaryFontSize - 2)` ที่ซ้ำ 7 ที่ใน `UsageWindow.swift`
- injection ที่ถูกเจาะข้ามชั้นเดียว: `SkillDiscovery` inject
  `homeDirectory:` (`:105`) แล้วข้างใน `scan`/`findSkillFolders`
  (`:120`, `:199`, `:213`) เรียก `FileManager.default` เอง

### จุดเล็กอื่น

- `menu.pdf` 5.16 MB — ไฟล์ tracked ใหญ่สุดในรีโป ไม่เกี่ยวกับโปรเจกต์
- ไฟล์แถว ~300 บรรทัดหลายไฟล์รวม model + parser + store + test double
  ในไฟล์เดียว (`Attachment`, `AppearanceSettings`, `ConversationArchive`,
  `ProfileStore`) — ตัวขับขนาดอันดับสองรองจาก `Secretary.swift`
- duplicate: `acceptsFirstMouse` override 3 ที่
- เทสหนึ่งตัวไม่มี assertion (`FileIntentTests.swift:107`) — จงใจเป็น
  crash regression test ยอมรับได้แต่ควรรู้ไว้

## สิ่งที่ทำไปแล้วจากรอบนี้

ปิด 3 ช่องโหว่ในสกิล `swift-functional-programming` (commit `6bee583`)
โดยใช้ violation ข้อ 1 และ 5 ข้างบนเป็นหลักฐานว่าถ้อยคำเดิมมีช่อง:
ข้อยกเว้นของ store ไม่คลุม struct ข้างใน (§2), `Option` ที่ทุกจุดอ่านเป็น
`guard let` คือ type ที่ไม่คุ้มครอง (§5), injection ที่ถูกเจาะข้ามชั้นเดียว (§9)
พร้อม checklist 2 บรรทัด

## ขั้นถัดไปที่แนะนำ เรียงตามคุ้ม/ถูก

1. revoke + ลบ `claude-api-key.txt` (1 นาที, ปิดความเสี่ยงเดียวที่เป็น secret)
2. แก้บั๊ก `screenMargin` สองเจ้าของ (เล็ก, มีผลกับ layout จริง)
3. ลบย่อหน้า Keychain/`Credentials/`/`ClaudeChatProvider` ออกจาก README ทั้งสอง
4. เริ่มแยก `Secretary.swift` จากส่วนที่ตัดง่ายสุด: prompt construction
   ~500 บรรทัดออกเป็นไฟล์ pure function — ได้เทสเพิ่มฟรีทันที
5. ทยอยย้าย decision ใน `AISecretaryApp` เข้า library target ตามรายการข้อ 5
