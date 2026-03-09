---
name: add-story-v3
description: "Conversationally create one or more stories for an existing project. Reviews current backlog and codebase, applies story-writing standards, creates GitHub issues on the project board."
argument-hint: "[description of what to add, or leave blank for interactive mode]"
---

# Add Story

You are adding stories to an existing project backlog. You work conversationally — the user describes what they want, you ask clarifying questions, then produce well-structured stories that conform to TI story-writing standards and fit cleanly into the existing project.

You do NOT implement anything. You produce stories.

## Phase 0: Load Context

### 0a. Resolve Project Identity

```bash
REPO_NWO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
REPO_OWNER=$(echo "$REPO_NWO" | cut -d/ -f1)
REPO_NAME=$(echo "$REPO_NWO" | cut -d/ -f2)
```

### 0b. Sync Standards & Read Config

1. Sync standards repo:
   - If `../TI-Engineering-Standards/` exists: `cd ../TI-Engineering-Standards && git pull --ff-only && cd -`
   - If not: `git clone https://github.com/drdatarulz/TI-Engineering-Standards.git ../TI-Engineering-Standards/`
2. **Read `../TI-Engineering-Standards/standards/story-writing-standards.md` in full**
3. Read `../TI-Engineering-Standards/standards/project-tracking.md`
4. Read `CLAUDE.md` — extract: story ID prefix, project board URL, build commands
5. Read `ARCHITECTURE.md`

### 0c. Understand Current State

1. **Fetch open stories** for existing backlog context:
   ```bash
   gh issue list --repo {REPO_OWNER}/{REPO_NAME} --state open --json number,title,labels --jq '.[] | {number, title, labels: [.labels[].name]}'
   ```

2. **Fetch recent closed stories** (last 10) for pattern reference:
   ```bash
   gh issue list --repo {REPO_OWNER}/{REPO_NAME} --state closed --label story --limit 10 --json number,title --jq '.[] | {number, title}'
   ```

3. **Determine current story ID range:**
   ```bash
   gh issue list --repo {REPO_OWNER}/{REPO_NAME} --state all --label story --json title --jq '.[].title' | grep -oP '{PREFIX}-\d+' | sort -t- -k2 -n | tail -1
   ```

4. **Scan the codebase** — understand what's built:
   - `src/` directory structure — what projects/components exist
   - Recent git log (`git log --oneline -20`) — what's been worked on
   - Existing screens/pages if UI exists

5. **Check for existing milestones:**
   ```bash
   gh issue list --repo {REPO_OWNER}/{REPO_NAME} --state open --label milestone --json number,title --jq '.[] | {number, title}'
   ```

### 0d. Resolve Project Board IDs

Query GraphQL for project ID, field ID, and status option IDs (same pattern as orchestrate-v3 Step 0c).

---

## Phase 1: Gather Requirements

### If $ARGUMENTS contains a description:

Parse the user's description and proceed to Phase 2 (Clarify).

### If $ARGUMENTS is empty or minimal:

Ask the user: **"What would you like to add to this project? Describe the capability, feature, or change — whatever level of detail you have. I'll ask follow-up questions if I need more."**

---

## Phase 2: Clarify

Based on the user's description and your understanding of the codebase, identify gaps. Ask clarifying questions — max 2-3 questions per message, each focused:

**Questions to consider (ask only what's needed):**
- Does this affect an existing entity or introduce a new one?
- Is this a new screen/page, or additions to an existing one?
- Are there validation rules or business logic I should know about?
- How does this relate to existing stories in the backlog?
- Should this be its own milestone, or does it attach to an existing one?

**Skip questions where:**
- The codebase provides a clear answer
- The existing patterns make the choice obvious
- There's only one reasonable option

---

## Phase 3: Propose Stories

Based on the user's input, existing codebase, and story-writing standards, propose one or more stories.

Present each story in preview format before creating issues:

```markdown
## Proposed Stories

### {PREFIX}-{NNN}: {Title}
**Label:** story
**Milestone:** {Existing milestone name | "New milestone: {name}" | "None — standalone review gate"}

**Summary:** {1-2 sentences from user's perspective}

**Acceptance Criteria:**
- [ ] {Criterion 1}
- [ ] {Criterion 2}
- [ ] {Criterion 3}

**Dependencies:** {None | list of story IDs that must be complete first}

---

### [additional stories if needed]

---

**This would create {N} issue(s). Want me to proceed, or adjust anything?**
```

**Sizing check:** Before proposing, verify each story against story-writing standards sizing guidance:
- Is it a vertical slice (not a horizontal layer)?
- Does it group entity lifecycle operations together (not one story per CRUD op)?
- Is it completable in a single developer agent session?
- Is it too large? Split along capability boundaries.

Wait for user approval before creating issues.

---

## Phase 4: Create Issues

After user approves:

### 4a. Create Each Story Issue

```bash
gh issue create --repo {REPO_OWNER}/{REPO_NAME} \
  --title "{PREFIX}-{NNN}: {Title}" \
  --label "story" \
  --body "$(cat <<'EOF'
## Summary

{Description}

{If milestone: **Milestone:** {Milestone Name}}

## Acceptance Criteria

- [ ] {Criterion 1}
- [ ] {Criterion 2}
- [ ] {Criterion 3}

## Branch

`story/{PREFIX}-{NNN}-short-name`

## Test Coverage

| Tier | Required | Notes |
|------|----------|-------|
| Unit tests | [x] Yes / [ ] N/A | |
| Integration tests | [x] Yes / [ ] N/A | |
| UI / E2E tests | [ ] Yes / [x] N/A | |

## Plan

_Fill in before starting implementation._

## Implementation Notes

_Fill in during implementation._

## Test Results

_Fill in when done._

## Files Changed

_Fill in when done._
EOF
)"
```

After creation:
1. Set custom fields (Type=Story, Priority, Story ID)
2. Move to **Up Next**

### 4b. Create Milestone Marker (If Needed)

If the new stories warrant their own milestone (per story-writing standards or user request), create a milestone marker issue with the `milestone` label.

**Ensure the `milestone` label exists** — if not, create it:
```bash
gh label create milestone --repo {REPO_OWNER}/{REPO_NAME} --description "Milestone marker issue (review gate)" --color "0E8A16"
```

### 4c. Link Stories as Sub-Issues of Milestone

After creating all stories and the milestone marker, link each story as a sub-issue of the milestone. This gives epic-style progress tracking on the milestone issue.

For each story in the milestone:

1. Get the story's database ID:
   ```bash
   gh api graphql -f query='query($owner: String!, $repo: String!, $number: Int!) {
     repository(owner: $owner, name: $repo) { issue(number: $number) { databaseId } }
   }' -f owner={REPO_OWNER} -f repo={REPO_NAME} -F number={STORY_ISSUE_NUMBER} --jq '.data.repository.issue.databaseId'
   ```
2. Add as sub-issue using the GitHub MCP `sub_issue_write` tool:
   - `method`: `add`
   - `owner`: `{REPO_OWNER}`
   - `repo`: `{REPO_NAME}`
   - `issue_number`: the milestone marker's issue number
   - `sub_issue_id`: the story's database ID from step 1

If adding stories to an **existing** milestone, use the same process — get the existing milestone's issue number and add the new stories as sub-issues.

### 4d. Confirm

Tell the user what was created:

```markdown
## Stories Created

| # | Story ID | Title | Milestone |
|---|----------|-------|-----------|
| {number} | {PREFIX}-{NNN} | {title} | {milestone or "Standalone"} |

**Next steps:**
- Run `refine-story-v3 {PREFIX}-{NNN}` to add technical detail
- Or add to the next `orchestrate-v3` batch
```

---
<!-- skill-version: 3.1 -->
<!-- last-updated: 2026-03-09 -->
<!-- pipeline: v3 -->
