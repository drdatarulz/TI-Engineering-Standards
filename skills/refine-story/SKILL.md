---
name: refine-story
description: Refine a GitHub issue into an implementation-ready spec by exploring the codebase, identifying gaps, interactively resolving decisions, then updating the issue.
argument-hint: "[STORY-ID e.g. TX-114]"
---

# Refine Story Skill

You are refining a GitHub issue into a complete, implementation-ready specification. Follow these phases exactly.

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

Extract the issue number from the argument. If only a story ID is given (e.g., `TX-114`), search for it:

```bash
gh issue list --search "STORY_ID in:title" --json number,title --jq '.[0].number'
```

Then fetch the issue:

- Use `mcp__github__issue_read` with `method: "get"`, `owner: "{REPO_OWNER}"`, `repo: "{REPO_NAME}"`, `issue_number: <number>`
- Also fetch comments: `method: "get_comments"`

Parse the issue body for:
- **Stub file** — the existing implementation file to modify
- **Interface** — the domain interface being implemented
- **Consumers** — workers/services that call the interface
- **DI registration** — where the implementation is wired up
- **Related stories** — dependencies or predecessors

### 1b. Explore the Codebase (in parallel)

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

**C. File I/O Flow** — For stories involving file processing: who downloads the input? Where does it go? Who uploads the output? Who cleans up temp files? Is blob storage involved?

**D. Interface Completeness** — Does the interface method have the right parameters? Is `CancellationToken` included? Are return types correct? Does the signature need to change?

**E. Configuration** — What settings are needed? What section of `appsettings.json`? What are sensible defaults?

**F. Infrastructure / Docker** — Are new system packages, NuGet packages, or Docker layers needed? Impact on container size?

**G. Error Handling** — What happens with corrupt input, missing dependencies, timeouts, or partial failures?

**H. Acceptance Criteria Completeness** — Are criteria specific and testable? Do they cover happy path, edge cases, and error scenarios?

**I. Files Expected to Change** — Can we enumerate every file that will be created or modified?

**J. Cross-Story Dependencies** — Does this story depend on another that isn't done yet? Will this story's output be consumed by a later story?

**K. Risks / Watch-outs** — Large container size, slow processing, flaky external tools, licensing concerns?

Skip categories that don't apply to the story (e.g., skip File I/O for a pure UI story).

## Phase 3: Interactive Refinement

For each gap that requires a user decision:

- Use `AskUserQuestion` to present the decision
- **Max 2 questions per message**, each with 2-3 options
- **Always recommend one option** (mark it with "(Recommended)" in the label)
- **Skip questions where**:
  - The codebase already provides a clear answer
  - There's only one reasonable choice (just state your decision)
  - The gap can be filled from existing patterns in the project

After all decisions are resolved, present a summary of all decisions made before proceeding to Phase 4.

## Phase 4: Update the Issue & Move on Board

### 4a. Compose the Refined Issue Body

Use this template. **Omit sections that don't apply** to the story. Adapt section names to fit the story's domain (e.g., "HOCR Parsing" instead of a generic name).

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

`story/XX-XXX-short-name`

## Test Coverage

| Tier | Scenario | Assertion |
|------|----------|-----------|
| Unit | Happy path | Returns expected output |
| Unit | Corrupt input | Returns error result |
| Integration | End-to-end | Blob uploaded correctly |

## Dependency on XX-XXX

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

### 4c. Move Issue to "Up Next" on Project Board

Look up the project board IDs dynamically (same approach as the orchestrate skill — query GraphQL for the project, field, and option IDs), then update the item's status to "Up Next".

### 4d. Confirm to User

Tell the user:
- The issue has been updated with the refined spec
- The issue has been moved to "Up Next" on the project board
- Link to the updated issue
