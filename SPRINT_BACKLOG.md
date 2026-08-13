# Sprint Backlog

งานของ sprint ที่กำลังทำอยู่ ติ๊กแล้วคือ ship แล้ว

## 13-3: Performance Improvement
- [x] วิเคราะห์ว่า แต่ละครั้งที่สั่งทำงาน สังเกตุว่าจะใช้เวลานานกว่าจะเริ่มตอบ
- [ ] หาทาง improve เรื่อง response + performance

### ผลการวัด (2026-08-13, CLI 2.1.229, v0.13.223)

**แอปไม่ได้ช้า — spawn `claude` หลังกด Return แค่ 0.04 วินาที** วัดจากแอปที่รันอยู่จริง
โดยจับเวลาตั้งแต่ปุ่ม Return ถูกโพสต์จนลูกของ process แอปโผล่ใน `pgrep -P` เวลาที่เหลือ
ทั้งหมดเป็นของ Claude Code ไม่ใช่ของเรา สิ่งที่ต้องแก้จึงไม่ใช่โค้ดฝั่ง UI หรือ orchestration

| สิ่งที่วัด | first line | first text | total |
|---|---|---|---|
| CLI flags เดียวกับแอป (โฟลเดอร์เปล่า) | 0.81s | 2.92s | 3.17s |
| เพิ่ม `--strict-mcp-config` (ปิด MCP) | 0.89s | 3.30s | 3.56s |
| turn ใหม่ / `--resume` turn 2 / turn 3 | 1.0 / 1.4 / 0.9s | 5.08 / 5.05 / 6.09s | — |
| ในแอปจริง (turn เดียว trivial) | — | — | 5.92s |

**สมมติฐานที่ผิดและถูกตัดทิ้งด้วยการวัด:**
- **ไม่ใช่ MCP** — ปิดแล้วเวลาเท่าเดิม connector ที่ผูกกับ claude.ai ไม่ได้ถูกต่อใน headless run
- **ไม่ใช่ login shell** — `LoginShellPath.resolve()` cache ไว้แล้วจริง หนึ่งครั้งต่ออายุแอป
- **ไม่ใช่งานฝั่งเราก่อน spawn** — 0.04s

**ตัวการคือ process ใหม่ทุกเทิร์น** ทุกครั้งที่สั่งงาน แอปเปิด `claude -p --resume <id>` ใหม่
ต้อง boot node, โหลด config, แล้วอ่าน transcript เก่ากลับเข้ามาทั้งก้อน — cache ของ prompt
เย็นทุกรอบ

**ทางแก้ที่วัดแล้วว่าได้ผล: `--input-format stream-json`** ป้อน user message ทีละบรรทัดเข้า
stdin ของ process เดียวที่เปิดค้างไว้ วัดที่ system prompt ขนาดจริง (~6.3KB):

| | first text | total |
|---|---|---|
| turn 1 (process เพิ่งเปิด) | 5.47s | 5.73s |
| turn 2 (process เดิม) | **1.49s** | 2.22s |
| turn 3 (process เดิม) | **1.15s** | 2.10s |

**เร็วขึ้นราว 3.7 เท่า ประหยัดราว 4 วินาทีต่อเทิร์น**

**ข้อจำกัดที่ต้องออกแบบรอบ:** `--append-system-prompt`, working directory, `--allowedTools`,
`--add-dir`, `--model`, `--effort`, `--chrome` เป็น flag ตอน launch ทั้งหมด เปลี่ยนเมื่อไหร่
ต้องเปิด process ใหม่ กติกาว่า "เมื่อไหร่ต้องเปิดใหม่" จึงต้องเป็น pure function ใน library target
ตรวจแล้วว่าค่าเหล่านี้ **ไม่เปลี่ยนระหว่างเทิร์นปกติ** — `outstanding` (ตัวเดียวที่ทำให้ system
prompt ขยับกลางบทสนทนา) ถูกตั้งเฉพาะตอนเทิร์นถูก block เรื่อง permission ซึ่งเป็นจังหวะที่
`allowedTools` เปลี่ยนอยู่แล้ว จึงต้องเปิดใหม่อยู่ดี ไม่ได้เสียของ

**สี่อย่างที่ process ค้างต้องทำให้ได้เท่าของเดิม** (แต่ละข้อคือ failure mode ไม่ใช่ polish):
1. **กด Stop กลางเทิร์น** ของเดิม `process.terminate()` ได้เลย ของใหม่การฆ่า process คือ
   ฆ่าทั้ง session
2. **`.staleSession`** ของเดิมอ่าน stderr หลัง process ตาย process ที่ไม่ตายต้องมีทางอื่น
3. **เส้นแบ่งเทิร์น** ต้องอ่านจนถึง `type == "result"` แล้วหยุด ไม่งั้น event ของเทิร์นถัดไป
   จะไปลงบัวเก่า
4. **process ตายเงียบระหว่างเทิร์น** ต้องรู้ตอนเขียน stdin ไม่ใช่ค้างรอ
