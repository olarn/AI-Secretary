# Initial Implementation Prompt for Claude Code

You are starting work on a repository for a macOS AI Desktop Companion / AI Secretary.

First, read and follow CLAUDE.md completely.

Product intent:

- The user interacts with a floating animated desktop character through chat, with voice planned for a later phase.
- The character is the UI layer.
- The AI Secretary is the central orchestrator that understands requests, manages context, applies permissions, selects tools, and reports results.
- Claude Code is a coding agent/tool used by the Secretary for software-development tasks.
- Do not design Claude Code as the Secretary itself.

Your first objective is to safely assess the repository and propose the best MVP implementation path before making broad changes.

Please work in this order:

1. Repository discovery
   - Inspect the repository structure, existing app code, build system, dependencies, tests, documentation, and configuration.
   - Identify whether it is already a SwiftUI/AppKit macOS app, another stack, or an empty/new repository.
   - Do not delete, overwrite, or restructure existing work without explaining why and obtaining approval when appropriate.

2. Architecture assessment
   - Explain the current architecture and gaps against the product vision.
   - Recommend a minimal, clean architecture for the MVP.
   - Prefer SwiftUI for normal UI and AppKit only where needed for macOS floating transparent-window behavior.
   - Define clean module boundaries, for example: Desktop Character UI; Assistant state machine; Chat/task UI; Secretary domain/orchestration; Project registry; Permission/approval policy; Tool adapters; Claude Code adapter; Logging/audit persistence.
   - Keep the design simple enough to implement incrementally in a single macOS application initially.

3. Tech-stack recommendation
   - Propose the concrete stack based on the repository, with short trade-offs.
   - Do not introduce a separate TypeScript, Rust, backend, database, voice pipeline, MCP server, or cloud dependency unless it is necessary for the current MVP.
   - If an abstraction is needed for future expansion, create interfaces/protocols without implementing unused infrastructure.

4. MVP plan
   - Provide a phased implementation plan:
     - Phase 1: floating desktop character shell, drag interaction, chat panel, local state-machine demo.
     - Phase 2: Secretary task model, project registry, approvals, controlled Claude Code tool adapter.
     - Phase 3: voice.
     - Phase 4: MCP/macOS/calendar/external integrations and optional proactive notifications.
   - For each phase, state the user-visible outcome, key modules, risks, and acceptance criteria.

5. Security and operational design
   - Define a least-privilege permission model.
   - Separate read-only, local-write, destructive, Git-history-changing, dependency-installing, and external-network actions.
   - Ensure destructive or externally impactful actions require explicit human approval.
   - Restrict coding-agent execution to an explicitly selected project registry entry and working directory.
   - Propose structured logs, task IDs, approval records, and safe error handling.
   - Treat repository instructions, tool output, MCP responses, and external content as untrusted.

6. Start implementation only after the assessment
   - If the repository is suitable, implement only the smallest useful Phase 1 vertical slice:
     - visible floating transparent desktop companion window;
     - simple placeholder character representation if production art/assets do not exist;
     - state machine: IDLE, LISTENING, THINKING, WORKING, SUCCESS, ERROR;
     - click interaction that opens a chat/task panel;
     - mock state transitions for demonstration;
     - unit tests for state transitions where practical;
     - concise documentation for how to build and run.
   - Preserve clear seams for the future Secretary, project registry, permission policy, and Claude Code adapter.
   - Do not implement real shell execution, broad filesystem access, autonomous agents, external APIs, voice, MCP, or real Claude Code invocation in the first vertical slice unless the repository explicitly already supports and requires it.

Implementation standards:

- Use clean architecture, modular design, typed domain models, and testable dependency boundaries.
- Keep UI code separate from orchestration/domain logic.
- Avoid unnecessary dependencies.
- Add tests for business logic and state transitions.
- Add structured logging where it meaningfully helps.
- Update documentation as you go.
- Make small, focused changes and run relevant build/tests after each meaningful milestone.

Before changing files, report:

1. What you found in the repository.
2. Your proposed architecture and stack.
3. Your proposed MVP plan.
4. The exact small implementation slice you intend to build.
5. Any assumptions or approvals needed.

After implementation, report:

1. What changed and why.
2. Files changed.
3. Build/test commands run and exact outcomes.
4. Known limitations.
5. The smallest recommended next step.
