# Model Behavior Observations

A running log of cases where Claude's default architectural choices surprised us
or deviated from what we'd normally pick by hand. The goal is **not** to fight
the model — it's to spot patterns where our written standards are silent and
make a deliberate choice about whether to codify the model's default or override
it.

## How to use this file

When Claude makes an architectural call that surprises you:

1. Append a new entry below using the template.
2. Don't change the standards yet — capture the observation while it's fresh.
3. Revisit periodically (quarterly, or when starting a new project) and
   convert decided items into actual standards text.

If Claude is the one logging the entry, it should ask first and then write a
concise, neutral note — not a defense of its choice.

## Entry template

```markdown
### YYYY-MM-DD — {short title} ({model version if known})

- **Observation:** What Claude did, in one or two sentences.
- **Where it surfaced:** Project, ticket, or PR.
- **What the standards currently say:** Cite the file/section, or "silent."
- **Counterfactual:** What a human (or an earlier model) would likely have done.
- **Decision needed:** What question the standards should answer.
- **Status:** Open / Decided ({date} — short outcome).
```

---

## Entries

### 2026-05-13 — SQL admin auth default (Opus 4.7)

- **Observation:** On IntakeIt II-5 (Bicep + CI/CD scaffold), Claude defaulted
  the SQL server to Entra-ID-only auth (`azureADOnlyAuthentication: true`) with
  no SQL admin password anywhere. Runtime auth was via user-assigned managed
  identities and `Authentication=Active Directory Default;` connection strings.
  When the user asked to switch to a traditional connection-string-in-GitHub-Secret
  pattern during II-52, Claude pushed back citing "MI over secrets" from
  `standards/security.md`.
- **Where it surfaced:** drdatarulz/IntakeIt — II-5 (closed), II-52 (in progress).
- **What the standards currently say:** `standards/security.md` says "Managed
  Identity over secrets" without qualification. No worked example for the
  Azure-SQL-from-a-Container-App case specifically.
- **Counterfactual:** Opus 4.6 on prior TI projects defaulted to SQL Authentication
  with the connection string stored as a GitHub Secret. The MI option was not
  raised unless explicitly asked for.
- **Decision needed:** Is "MI over secrets" a hard default with a documented
  exception path (e.g., "use MI unless you have a specific operational reason
  to use a password"), or is SQL-Auth-first the actual TI default and the
  standard's current wording is too strong? Either is fine — the standards
  should pick.
- **Status:** Open.

