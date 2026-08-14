
**คำบนการ์ดแก้ตอนขับจริง (v0.14.249)** รอบแรกการ์ดอ่านว่า "May I run `remember “…” for
my-mcp-server, in your Claude Code memory` **in my-mcp-server**?" — ชื่อ project สองครั้ง
ในประโยคเดียว เพราะประโยคที่ห่อมันอยู่เติม "in <project>" ให้อยู่แล้ว summary จึงเลิกใส่ชื่อเอง
และเปลี่ยนไปพูดสิ่งที่การ์ดพูดผิด: subtitle ของ `.localWrite` เขียนว่า "Writes files in the
project" ซึ่งไม่ใช่ที่ที่ของอันนี้ลง แต่ subtitle นั้นใช้ร่วมกับ local write ทุกอันและถูกสำหรับอันอื่น
คำแก้จึงอยู่ที่ summary ไม่ใช่ที่ `ActionClass`

**ขับจริงครบวง** (Pikachu, project `my-mcp-server`): สั่งจำ → การ์ดขึ้น → กด Approve →
ได้ `build-script-code-repo-root.md` กับบรรทัดใน `MEMORY.md` จริงที่
`~/.claude/projects/-Users-Olarn-Desktop-my-mcp-server/memory/` หัวข้อภาษาไทยรอด
ชื่อไฟล์ ASCII ถูกถอดออกมาได้ แล้ว **เปิด `claude -p` ใหม่ใน project นั้นแล้วมันอ่านบรรทัดนั้น
กลับมาให้ได้** ซึ่งเป็นข้ออ้างทั้งหมดของดีไซน์นี้ — ที่เก็บเดียว อ่านได้ทั้งแอปและเทอร์มินัล
