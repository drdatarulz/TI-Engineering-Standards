# Agentic Development Workflow

## Overview

This document defines the end-to-end workflow for 100% agentic software development using Claude (web interface and Claude Code), GitHub Projects, and a supervisor/worker orchestration pattern. The workflow covers everything from initial brainstorming through deployed, tested code.

The core philosophy: separate concerns between human-driven discovery, AI-assisted specification, and fully orchestrated development — with clean context boundaries at each transition to prevent drift.

---

## Phase 1: Discovery & Capture

**Tool:** Otter.ai  
**Participants:** Developer + stakeholders/clients  
**Output:** Raw transcript (.txt)

Record a freeform discussion using Otter.ai for live transcription. There is no required structure — the goal is to get every idea, requirement, concern, and tangential thought captured. Participants throw out everything they're thinking about in whatever order it comes.

Export the full transcript as a text file. This is the primary input artifact for the next phase.

---

## Phase 2: PRD Refinement

**Tool:** Claude Web Interface  
**Input:** Transcript file  
**Output:** PRD (Markdown) + Screen Inventory (Markdown) + Decisions Log (Markdown)

### 2.1 Initial Synthesis

Upload the transcript to Claude in the web interface. Prompt Claude to read the entire transcript, make sense of the discussion, and produce a first-pass PRD in Markdown format (not Word).

### 2.2 Convergence Loop

Enter an iterative refinement cycle:

1. Ask Claude: "Do you have any questions, or am I missing anything?"
2. Claude identifies gaps, asks clarifying questions, raises items not yet considered.
3. Answer the questions and refine scope.
4. When Claude indicates readiness to produce the PRD, ask: "What other items should I be thinking about?"
5. Repeat. Claude's suggestions will move from highly pertinent to increasingly marginal — this diminishing return is the exit signal.

### 2.3 Engineering Scoping

During the convergence loop (or as a dedicated step), define:

- **Tech stack** — languages, frameworks, databases, infrastructure
- **Compilable components** — APIs, clients, worker processes, background services. Define what each binary/deployable unit is and what it does. This prevents Claude Code from making assumptions about service boundaries during development.
- **Architectural constraints** — patterns to follow, patterns to avoid, dependency rules

### 2.4 Screen Inventory (New)

After functional requirements and engineering scope are largely settled, walk through the application's UI screen by screen. This is conversational — describe what each screen does, what the user sees and can do, and where they can navigate from there. Claude organizes this into a structured Screen Inventory document.

The Screen Inventory defines:

- **Every screen/view** with its purpose, key content, and available user actions
- **Modals and overlays** with their triggers, fields, and validation rules
- **Navigation flow** — a text-based map showing how screens connect
- **Data dependencies** — which API endpoints each screen needs
- **Key states** — empty, loading, and error states for each screen
- **Shared components** — UI elements that appear across multiple screens, defined once to prevent duplication

This gives Claude Code explicit screen boundaries during development, just as component definitions give it explicit service boundaries. Without it, Claude Code infers screen structure from the PRD's functional requirements, and those inferences compound into inconsistencies.

A reusable Screen Inventory template is available as a companion artifact. Use it as the starting structure during this conversation.

### 2.5 Final PRD Review

Claude produces the complete PRD. Review it in one more cycle of reading and pointing things out until satisfied.

### 2.6 Decisions Log (New)

Before closing the Claude Web session, ask Claude to produce a **Decisions Log** as a companion artifact. This is a concise document that captures:

- Key decisions made during the PRD process
- Alternatives that were considered and why they were rejected
- Assumptions that were made and their rationale
- Open questions that were deferred

Format: Short entries, each following the pattern: "**Decision:** [what was decided]. **Alternatives considered:** [what else was on the table]. **Rationale:** [why this choice was made]."

The Decisions Log gives Claude Code the *reasoning* behind the PRD, not just the requirements. This fills the context gap at the handoff point without the noise of the raw transcript.

---

## Phase 3: Project Bootstrap

**Tool:** Claude Code  
**Input:** PRD + Decisions Log  
**Output:** Initialized repo with enriched backlog

### 3.1 Repository Setup

Create the project folder, GitHub repo, and project board. The project board uses a Kanban layout: Inbox → Up Next → Active → Done. Two types of items live on the board:

- **Development stories** — code-producing tickets following a Kanban workflow
- **Operational tasks** — non-code items tracked for accountability

Label these distinctly (e.g., `story` vs. `task` labels or separate issue templates) so they don't get mixed.

### 3.2 Standards Integration

The project pulls from a shared TI-Engineering-Standards repository that is abstracted across all projects. On session start:

1. If the standards repo exists locally: `git pull --ff-only`
2. If not: `git clone` the repo
3. Read `CLAUDE.md` from the standards repo and every file it references

This is defined in each project's `CLAUDE.md` as the entry point. When standards change in one project, they propagate to all projects on next pull.

**Note:** Consider versioning or timestamping when standards were pulled to maintain consistency within a single project if standards change mid-development.

### 3.3 Backlog Generation

Claude Code reads the PRD, Screen Inventory, and Decisions Log and decomposes them into GitHub issues on the project board. Issues should be created and explicitly added to the project board (GitHub Project #5) — creating an issue alone does not automatically place it on a project board without automation.

**Recommended:** Set up a GitHub Actions workflow or project-level auto-add rule to catch new issues with certain labels and add them to the board automatically.

### 3.4 Backlog Review (Recommended)

Before investing in ticket enrichment, spend 10–15 minutes scanning the generated stories:

- Do story titles map back to PRD requirements?
- Is the decomposition at the right granularity?
- Are there gaps — PRD requirements with no corresponding story?
- Are there phantom stories — tickets that don't trace back to the PRD?

This lightweight gate catches misinterpretations before they compound.

### 3.5 Ticket Enrichment

Using a dedicated review skill, Claude Code reviews each story for:

- Technical completeness
- Questions a developer might have
- Cross-references with the codebase and other stories

The ticket is updated with implementation details, making it well-rounded before development begins.

---

## Phase 4: Orchestrated Development

**Tool:** Claude Code with Orchestrator + Developer skills  
**Input:** Enriched tickets  
**Output:** Implemented, tested, merged code

### 4.1 Architecture: Supervisor/Worker Pattern

Development uses two Claude Code skills working in concert:

- **Orchestrator skill** — manages the loop: pre-flight, delegation, post-processing, board updates, merging, session summary. Stays lightweight.
- **Developer sub-agent skill** — implements a single ticket with a fresh context window. Loads all standards and constraints from scratch each time. This is the core mitigation for context drift.

The orchestrator spawns one developer sub-agent per ticket sequentially. Each sub-agent gets a clean context with full standards, preventing the procedural drift that occurs when a single long-running session accumulates context and deprioritizes instructions.

### 4.2 Orchestrator Flow

For each ticket in the batch:

**Pre-Flight (orchestrator):**
1. Read the ticket via GitHub MCP
2. Pull latest main
3. Verify git hooks
4. Create feature branch (`story/TX-XXX-short-name`)
5. Move ticket to In Progress on project board

**Ticket Readiness Gate (recommended):** Before spawning the sub-agent, verify the ticket has acceptance criteria and a non-empty description. If not, skip the ticket and log it as Skipped with reason.

**Spawn Sub-Agent:**
- Read the developer skill
- Substitute placeholders: ticket number, title, body, branch name
- Pass to Task tool as a fresh sub-agent

**Process Result (orchestrator):**
- If **Complete**: verify build, verify tests, update acceptance criteria, post completion comment, merge to main (no-ff), delete branch, push (autonomous only), close issue
- If **Partial**: comment on issue with what remains, leave branch as-is
- If **Blocked**: move to Waiting/Blocked on board, comment with blocker details

**Status Parse Hardening (recommended):** Explicitly parse the sub-agent's STATUS line. If not exactly "Complete", "Partial", or "Blocked", treat as Partial and flag it.

**Mode Gate:**
- **Supervised**: hard stop after each ticket. Output check-in report and wait for "proceed." Used when iterating on skills or early in a project.
- **Autonomous**: continue to next ticket automatically.

**Circuit Breakers (both modes):**
- 3 consecutive Partial/Blocked → halt (systemic issue)
- Main corrupted after merge → halt
- Merge conflict requiring human judgment → halt

### 4.3 Developer Sub-Agent Flow

Each sub-agent executes independently with a full context reload:

**Context Load:**
1. Read TI-Engineering-Standards/CLAUDE.md and all 12 referenced standards files
2. Read project CLAUDE.md
3. Read ARCHITECTURE.md
4. Do NOT write any code until all three steps are complete

**Critical Constraints (inlined for visibility):**
- Domain has zero dependencies
- Dapper only (no Entity Framework)
- Minimal APIs only (no MVC controllers)
- xUnit + FluentAssertions only (no mocking frameworks)
- Hand-rolled fakes only
- Snake_case test naming
- INT IDENTITY primary keys, DATETIME2 + SYSUTCDATETIME()
- DbUp forward-only migrations
- Serilog structured logging
- Stage specific files (never `git add .`)

**Implementation Workflow:**
1. **Explore** — read existing code, understand patterns, identify changes needed
2. **Plan** — determine approach respecting build order (Domain → Fakes → Infrastructure → Api)
3. **Implement** — follow build order, write fakes and tests alongside code
4. **Test** — build and test; 3 attempts to fix failures before reporting Partial
5. **Commit** — stage specific files, concise "why" message

**Exit Checklist (recommended addition — before report):**
- [ ] All standards files were read
- [ ] No banned dependencies introduced (EF, Moq, etc.)
- [ ] Fakes created for all new interfaces
- [ ] Tests written alongside implementation
- [ ] `dotnet build` succeeds with zero errors
- [ ] `dotnet test` passes all tests
- [ ] Staged specific files only
- [ ] Commit message follows `TX-XXX:` format
- [ ] GitHub issue updated with implementation summary
- [ ] Acceptance criteria reviewed

**Report:** Structured output with STATUS, changes, tests, decisions, concerns, and blocked reason if applicable.

---

## Phase 5: Session Summary & Review

**Tool:** Human + Claude Code  
**Output:** Session report, refined skills

### 5.1 Session Report

The orchestrator produces a final summary: completed tickets, partial tickets, blocked tickets, skipped tickets, total tests added, total files changed.

### 5.2 Debug & Iterate

Run the application, test flows manually, identify issues. Debug with Claude Code as needed. Feed observations back into:

- The shared engineering standards repo (if broadly applicable)
- Project-specific CLAUDE.md or ARCHITECTURE.md
- Skill files (orchestrator and developer)

This is where skills get refined — checklists become more explicit, constraints get inlined, and procedural instructions evolve from narratives to checkboxes based on observed drift patterns.

---

## Key Principles

**Context drift is the primary adversary.** The supervisor/worker pattern exists specifically to reset context on every ticket. Front-loaded instructions decay; end-of-task checklists stick better because they're proximate to the action.

**Separate concerns at every boundary.** Humans do discovery. Claude Web does specification. Claude Code does implementation. The orchestrator manages workflow. The developer sub-agent writes code. Each actor has a clear, bounded role.

**Shared standards, project-specific rules.** The engineering standards repo is the single source of truth across projects. Project-level files (CLAUDE.md, ARCHITECTURE.md) layer on project-specific context. This lets you improve once and propagate everywhere.

**Trust but verify.** The orchestrator independently verifies build and tests after the sub-agent reports Complete. The sub-agent's word is not sufficient — the orchestrator confirms.

**Diminishing returns signal phase transitions.** In the PRD convergence loop, the shift from pertinent suggestions to marginal minutiae is the signal to stop refining and start building. Recognize and respect that signal.

---

## Appendix: Recommended Enhancements Summary

| Enhancement | Phase | Effort | Impact |
|---|---|---|---|
| Decisions Log | 2 (PRD) | Low | High — fills context gap at handoff |
| Screen Inventory | 2 (PRD) | Low–Medium | High — prevents UI interpretation drift |
| Backlog Review Gate | 3 (Bootstrap) | Low | Medium — catches misinterpretations early |
| Developer Exit Checklist | 4 (Dev) | Low | High — targets observed procedural drift |
| Ticket Readiness Gate | 4 (Dev) | Low | Medium — prevents wasted sub-agent runs |
| Status Parse Hardening | 4 (Dev) | Low | Medium — prevents silent misrouting |
| Standalone Standards Sync | 4 (Dev) | Low | Low — edge case for standalone runs |
| GitHub Auto-Add Rule | 3 (Bootstrap) | Low | Medium — eliminates manual board management |
| Issue Labeling (story vs. task) | 3 (Bootstrap) | Low | Medium — clean separation of work types |
