# Screen Inventory

> Companion artifact to the PRD. Defines every screen/view in the application, its purpose, what the user can do there, and how it connects to other screens. This gives Claude Code explicit screen boundaries so it doesn't have to infer them during development.

---

## How to Use This Template

During the PRD refinement phase (Phase 2), after the functional requirements are largely settled, walk through the application screen by screen in conversation. For each screen, describe:

- What is this screen for?
- What does the user see when they land here?
- What can they do?
- Where can they go from here?
- What data does this screen need?

Claude will organize your descriptions into the structure below. Don't worry about visual layout — this is about *what exists and what it does*, not how it looks.

---

## Application: [Project Name]

### Navigation Model

> Describe the overall navigation pattern: sidebar + content area, tab-based, wizard/step flow, hub-and-spoke, etc. This sets the structural context for all screens below.

**Primary navigation:** [e.g., Left sidebar with main sections, top bar with user menu]  
**Authentication boundary:** [e.g., Login screen gates all other screens]  
**Default landing:** [e.g., Dashboard after login]

---

### Screen Definitions

---

#### [Screen Name]

**Route:** `/path/to/screen`  
**Purpose:** One sentence — why does this screen exist? What job does it accomplish for the user?

**User arrives here from:**
- [Screen Name] → [action that triggers navigation, e.g., "clicks project name in list"]
- [Screen Name] → [action]

**What the user sees:**
- [Key content area or section — e.g., "Summary cards showing total count, active count, error count"]
- [Another content area — e.g., "Filterable data table of all records, paginated, 25 per page"]
- [Another element — e.g., "Action toolbar with Create New, Export, and Bulk Edit buttons"]

**What the user can do:**
| Action | Behavior | Navigates To |
|--------|----------|-------------|
| [e.g., Click a row in the table] | [e.g., Opens detail view for that record] | [Screen Name] |
| [e.g., Click "Create New"] | [e.g., Opens creation form as a modal] | [Modal / stays on screen] |
| [e.g., Apply filter] | [e.g., Refreshes table with filtered results] | [Stays on screen] |
| [e.g., Click "Export"] | [e.g., Downloads CSV of current filtered view] | [Stays on screen] |

**Data dependencies:**
- [e.g., GET /api/records — paginated list with filter params]
- [e.g., GET /api/records/summary — aggregate counts for summary cards]

**Key states:**
- **Empty state:** [What shows when there's no data — e.g., "Illustration + 'No records yet. Create your first one.' + CTA button"]
- **Loading:** [e.g., "Skeleton placeholders for cards and table rows"]
- **Error:** [e.g., "Inline error banner above the table with retry action"]

**Notes / Open questions:**
- [Anything unresolved — e.g., "Do we need real-time updates or is polling okay?"]
- [Design considerations — e.g., "Table might need horizontal scroll on mobile"]

---

#### [Next Screen Name]

> Repeat the same structure for each screen.

---

### Modals & Overlays

> Screens that appear on top of other screens (dialogs, drawers, sheets). These are defined separately because they don't have their own route but still represent distinct UI states.

---

#### [Modal Name]

**Triggered from:** [Screen Name] → [action]  
**Purpose:** [e.g., "Create a new record with required fields"]

**Fields / Content:**
- [e.g., Name (text, required)]
- [e.g., Category (dropdown, required, options from GET /api/categories)]
- [e.g., Description (textarea, optional, max 500 chars)]

**Actions:**
| Action | Behavior |
|--------|----------|
| [e.g., Save] | [e.g., POST /api/records, closes modal, refreshes parent table, shows success toast] |
| [e.g., Cancel / close] | [e.g., Closes modal, no changes. If form is dirty, confirm discard.] |

**Validation:**
- [e.g., Name must be unique — validated on blur via GET /api/records/check-name?name=X]
- [e.g., Category is required — inline error on submit if empty]

---

### Screen Map (Navigation Flow)

> A text-based map showing how screens connect. This is the "table of contents" for the UI.

```
Login
  ├── [success] → Dashboard
  └── [forgot password] → Password Reset → Login

Dashboard
  ├── [nav: Records] → Record List
  │     ├── [click row] → Record Detail
  │     │     ├── [edit] → Edit Record (modal)
  │     │     └── [delete] → Confirm Delete (modal) → Record List
  │     └── [create new] → Create Record (modal) → Record List
  ├── [nav: Settings] → Settings
  └── [nav: Reports] → Report List
        └── [click report] → Report Detail
```

---

### Shared Components

> UI elements that appear on multiple screens. Defining these prevents Claude Code from reimplementing the same thing differently on each screen.

| Component | Used On | Description |
|-----------|---------|-------------|
| [e.g., Data Table] | Record List, Report List | Paginated, sortable, filterable table. Supports row selection for bulk actions. |
| [e.g., Summary Card] | Dashboard, Record List | Displays a label, count, and optional trend indicator. |
| [e.g., Confirmation Modal] | Record Detail, Settings | Generic "Are you sure?" dialog with configurable message and action labels. |

---

## Completion Checklist

Before handing this to Claude Code:

- [ ] Every screen the user can navigate to is listed
- [ ] Every modal/overlay is defined with its trigger
- [ ] Navigation paths between screens are documented
- [ ] Data dependencies (API endpoints) are identified for each screen
- [ ] Empty, loading, and error states are considered
- [ ] Shared components are identified to avoid duplication
- [ ] Screen map reflects the full navigation graph
