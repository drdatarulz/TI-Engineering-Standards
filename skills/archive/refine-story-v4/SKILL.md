---
name: refine-story-v4
description: "Refine a GitHub issue into an implementation-ready spec. Supports orchestrator mode (auto-decisions, issue comments, structured status report) and standalone mode (interactive)."
argument-hint: "[STORY-ID e.g. AZ-014]"
---

# Refine Story v2 Skill

You are refining a GitHub issue into a complete, implementation-ready specification. Follow these phases exactly.

**Orchestrator Mode:** When `{ORCHESTRATOR_MODE}` is `true` (substituted by the orchestrator), skip interactive questions (Phase 3) and make best-judgment decisions. When running standalone (the literal `{ORCHESTRATOR_MODE}` appears unsubstituted), use interactive mode.

## Phase 0: Resolve Project Context & Pull Latest

```bash
REPO_NWO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
REPO_OWNER=$(echo "$REPO_NWO" | cut -d/ -f1)
REPO_NAME=$(echo "$REPO_NWO" | cut -d/ -f2)
git pull --ff-only
cd ../TI-Engineering-Standards && git pull --ff-only 2>/dev/null; cd -
```

## Phase 1: Gather Context

### 1a. Fetch the Issue

Extract the issue number from the argument. If only a story ID is given (e.g., `AZ-014`), search for it:

```bash
gh issue list --search "STORY_ID in:title" --json number,title --jq '.[0].number'
```

When invoked by the orchestrator, these values are already populated:
- **Issue Number:** {ISSUE_NUMBER}
- **Story ID:** {STORY_ID}
- **Repo Owner:** {REPO_OWNER}
- **Repo Name:** {REPO_NAME}

Fetch the issue:

- Use `mcp__github__issue_read` with `method: "get"`, `owner: "{REPO_OWNER}"`, `repo: "{REPO_NAME}"`, `issue_number: <number>`
- Also fetch comments: `method: "get_comments"`

Parse the issue body for:
- **Stub file** — the existing implementation file to modify
- **Interface** — the domain interface being implemented
- **Consumers** — workers/services that call the interface
- **DI registration** — where the implementation is wired up
- **Related stories** — dependencies or predecessors

### 1b. Already-Refined Detection

Before proceeding to exploration, check if the issue body already contains ALL of these key sections:
- `## Summary` (with context pointers like Stub, Interface, Consumer)
- `## Technical Approach`
- `## Acceptance Criteria` (with testable criteria)
- `## Files Expected to Change`
- `## Branch`

If ALL sections are present and substantive (not just placeholder text), report:

```
STATUS: AlreadyRefined
STORY_ID: {STORY_ID}
ISSUE_NUMBER: {ISSUE_NUMBER}
REASON: Issue already has complete specification with all required sections
```

Post an issue comment: "Refinement skipped — issue already has a complete implementation-ready spec."

Then STOP. Do not proceed to further phases.

### 1c. Explore the Codebase (in parallel)

Launch parallel searches for full context. Adapt these based on what the issue references:

1. **Stub file** — Read the implementation file mentioned in the issue
2. **Interface definition** — Read the interface in the Domain project
3. **Fake implementation** — Search for the fake in the Fakes project
4. **Domain models** — Read any models referenced in method signatures
5. **Consumer code** — Grep for the interface name across `src/` to find all callers
6. **DI registration** — Read the relevant host builder or `Program.cs`
7. **Docker/infra** — Check `Dockerfile`, `docker-compose.yml`, `.csproj` files for relevant service
8. **Configuration** — Check `appsettings.json`, `appsettings.Development.json` for related config sections
9. **Existing tests** — Search `tests/` for test files related to this feature
10. **Related completed stories** — If the issue references other stories, fetch those issues for context

## Phase 2: Identify Gaps

Systematically check each category against what the issue currently provides. For each gap found, note whether it needs a user decision or can be resolved from codebase context alone.

### Gap Categories

**A. Missing Context Pointers** — Does the issue reference the specific stub file, interface, consumers, and DI registration lines? Or is it vague?

**B. Technical Approach** — Is the library/tool/technique specified? Are there alternatives worth considering? Does the issue explain *why* this approach?

**C. External API Spec on Disk (HARD GATE — see `standards/api-integration.md`)** — Does this story involve calling an external third-party API (not our own endpoints)? Signs: provider implementation, HttpClient usage, endpoint URLs, auth credentials in config, or the story references a third-party service by name.

If YES, check whether the provider's **API spec file exists on disk** at `docs/api-specs/`:

```bash
ls docs/api-specs/{provider}* 2>/dev/null
```

Acceptable spec formats: OpenAPI JSON/YAML, ArcGIS REST layer JSON, or a manually documented schema (`.md`) that contains every endpoint path, request format, response field names with types, and at least one verified sample response.

**The following are NOT API specs and NEVER satisfy this gate:**
- PRD descriptions of what the API returns (product intent ≠ wire format)
- Ticket acceptance criteria describing expected behavior
- Training-data knowledge of what the API "probably" returns
- A description like "returns wildfire scoring with grade" without field-level detail

**If no spec file exists on disk:**

1. Check the project's API Integration Reference doc for a spec URL
2. If a URL exists, attempt to fetch and save it:
   ```bash
   curl -s -o docs/api-specs/{provider}-openapi.json {url}
   python3 -c "import json; json.load(open('docs/api-specs/{provider}-openapi.json')); print('Valid JSON')"
   ```
3. If fetch succeeds, use the spec as source of truth and continue refinement
4. If fetch fails or no URL exists:
   - **Standalone mode:** Stop and tell the user: *"This story requires integration with {provider} but no API spec exists at `docs/api-specs/`. Provide an OpenAPI spec, developer portal URL, or documented response schema before refinement can continue."* Do not guess endpoints, auth mechanisms, request formats, or response schemas.
   - **Orchestrator mode:** Return status BLOCKED:

     ```
     STATUS: Blocked
     STORY_ID: {STORY_ID}
     ISSUE_NUMBER: {ISSUE_NUMBER}
     REASON: Story requires external API integration ({provider name}) but no API spec found at docs/api-specs/. Provide OpenAPI spec, ArcGIS layer definition, or documented response schema before refinement can proceed.
     CHECKLIST_ITEM: "External API spec on disk" — FAILED
     ```

**If the spec file exists on disk:**

1. Read the spec and identify the relevant endpoint schemas
2. Use the spec's field names, types, and nesting as the **sole source of truth** for the Technical Approach
3. Include a `## Spec Reference` section in the refined issue body:
   ```markdown
   ## Spec Reference

   - **Spec file:** `docs/api-specs/{provider}-openapi.json`
   - **Endpoint:** `POST /advanced_wildfire_profile_request`
   - **Response schema:** `AdvancedWildfireResponse` → `metrics` (object with `Pixel_Risk_Score`, `PxlRiskClass`, `Six_Class`, `Risk_Score`, `Probability`, `Odds`)
   - **Field mapping:** [table of spec field → C# property → C# type]
   ```
4. In the Technical Approach, reference specific schema names and field definitions from the spec — not prose descriptions
5. In the Acceptance Criteria, add this checklist item:
   ```markdown
   - [ ] External API spec validation: All JsonPropertyName values match the spec. All C# types are compatible with spec types. No fields were inferred.
   ```

Do not supplement spec data with guesses from training data. If the spec is ambiguous or incomplete, note the ambiguity in the issue and flag it for the user — do not fill in the gaps with assumptions.

**D. File I/O Flow** — For stories involving file processing: who downloads the input? Where does it go? Who uploads the output? Who cleans up temp files? Is blob storage involved?

**E. Interface Completeness** — Does the interface method have the right parameters? Is `CancellationToken` included? Are return types correct? Does the signature need to change?

**F. Configuration** — What settings are needed? What section of `appsettings.json`? What are sensible defaults?

**G. Infrastructure / Docker** — Are new system packages, NuGet packages, or Docker layers needed? Impact on container size?

**H. Error Handling** — What happens with corrupt input, missing dependencies, timeouts, or partial failures?

**I. Acceptance Criteria Completeness** — Are criteria specific and testable? Do they cover happy path, edge cases, and error scenarios?

**J. Files Expected to Change** — Can we enumerate every file that will be created or modified?

**K. Cross-Story Dependencies** — Does this story depend on another that isn't done yet? Will this story's output be consumed by a later story?

**L. Risks / Watch-outs** — Large container size, slow processing, flaky external tools, licensing concerns?

Skip categories that don't apply to the story (e.g., skip File I/O for a pure UI story).

## Phase 3: Interactive Refinement (Standalone Mode Only)

**If `{ORCHESTRATOR_MODE}` is `true`, SKIP this phase entirely.** Make best-judgment decisions for all gaps based on:
- Existing codebase patterns
- Project conventions from CLAUDE.md and ARCHITECTURE.md
- The most conservative/standard option when genuinely ambiguous

Document each decision you made autonomously in a list for the issue comment (Phase 4b).

**If running standalone (interactive mode):**

For each gap that requires a user decision:

- Use `AskUserQuestion` to present the decision
- **Max 2 questions per message**, each with 2-3 options
- **Always recommend one option** (mark it with "(Recommended)" in the label)
- **Skip questions where**:
  - The codebase already provides a clear answer
  - There's only one reasonable choice (just state your decision)
  - The gap can be filled from existing patterns in the project

After all decisions are resolved, present a summary of all decisions made before proceeding to Phase 4.

## Phase 4: Update the Issue

### 4a. Compose the Refined Issue Body

Use this template. **Omit sections that don't apply** to the story. Adapt section names to fit the story's domain.

```markdown
## Summary

[Expanded summary with context pointers]

- **Stub:** `src/ProjectName.Infrastructure/path/to/Stub.cs`
- **Interface:** `src/ProjectName.Domain/Interfaces/IServiceName.cs`
- **Consumer(s):** `src/ProjectName.Infrastructure/Workers/ConsumerWorker.cs` (lines XX-YY)
- **DI Registration:** `src/ProjectName.Api/HostBuilders/WorkerHostBuilder.cs` (line XX)

## Technical Approach

[Description of the chosen approach and rationale]

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| Option A | ... | ... | **Chosen** |
| Option B | ... | ... | Rejected — reason |

## [Domain-Specific Section Name]

[Details specific to this story's domain — parsing rules, output format, etc.]

## File I/O Flow

1. Consumer calls `IService.ProcessAsync(documentId, cancellationToken)`
2. Implementation downloads blob from Azure Blob Storage
3. Writes to temp file at `/tmp/project/...`
4. Processes with [tool/library]
5. Uploads result to blob storage
6. Cleans up temp files in `finally` block

## Interface Change

**Before:**
```csharp
Task<Result> ProcessAsync(Guid documentId);
```

**After:**
```csharp
Task<Result> ProcessAsync(Guid documentId, ProcessingOptions options, CancellationToken cancellationToken);
```

## Configuration

```json
{
  "SectionName": {
    "Setting1": "default-value",
    "Setting2": 30
  }
}
```

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| Setting1 | string | `"default-value"` | ... |
| Setting2 | int | `30` | ... |

## Acceptance Criteria

- [ ] Criterion 1 — specific and testable
- [ ] Criterion 2 — covers edge case
- [ ] Criterion 3 — covers error scenario

## Files Expected to Change

| File | Change |
|------|--------|
| `src/ProjectName.Infrastructure/...` | Implement stub |
| `tests/ProjectName.Fakes/...` | Update fake |
| `tests/ProjectName.Api.Tests/...` | Add unit tests |

## Branch

`story/{PREFIX}-{issue#}-short-name`

## Test Coverage

| Tier | Scenario | Assertion |
|------|----------|-----------|
| Unit | Happy path | Returns expected output |
| Unit | Corrupt input | Returns error result |
| Integration | End-to-end | Blob uploaded correctly |

## Dependency on {PREFIX}-{issue#}

[Only if a real dependency exists — describe what's needed and current status]

## Risks / Watch-outs

- **Risk name** — description and mitigation

---

### Plan

_to be filled in during implementation_

### Implementation Notes

_to be filled in during implementation_

### Test Results

_to be filled in during implementation_
```

### 4b. Update the Issue on GitHub

Use `mcp__github__issue_write` with `method: "update"` to replace the issue body with the refined version. Preserve the original title unless it needs clarification.

### 4c. Post Issue Comment (Audit Trail)

Post a comment on the issue summarizing the refinement:

```bash
gh issue comment {ISSUE_NUMBER} --repo {REPO_OWNER}/{REPO_NAME} --body "$(cat <<'EOF'
## Refinement Complete

**Decisions made:**
- [List each gap that was resolved and the decision taken]
- [Include rationale for non-obvious choices]

**Sections added/updated:**
- [List which template sections were filled in]

**Open questions:** [None | list any that need manual attention]
EOF
)"
```

### 4d. Move Issue to "Up Next" (Standalone Mode Only)

**If `{ORCHESTRATOR_MODE}` is `true`, SKIP this step.** The orchestrator manages board state.

**If running standalone:** Look up the project board IDs dynamically (query GraphQL for the project, field, and option IDs), then update the item's status to "Up Next".

### 4e. Confirm / Report

**Standalone mode:** Tell the user the issue has been updated and moved to "Up Next", with a link.

**Orchestrator mode:** Return a structured report:

```
STATUS: Refined
STORY_ID: {STORY_ID}
ISSUE_NUMBER: {ISSUE_NUMBER}
DECISIONS_COUNT: [number of decisions made]
SECTIONS_UPDATED: [comma-separated list]
OPEN_QUESTIONS: [None | count]
```

---
<!-- skill-version: 4.2 -->
<!-- last-updated: 2026-06-02 -->
<!-- pipeline: v4 -->
