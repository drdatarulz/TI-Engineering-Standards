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

### 2026-05-14 — `readEnvironmentVariable()` in `.bicepparam` files unreliable (Opus 4.7)

- **Observation:** In IntakeIt PR #53, Claude wired the SQL admin password and
  connection string into the `.bicepparam` files via
  `readEnvironmentVariable('SQL_ADMIN_PASSWORD', '')` so the deploy workflow
  could inject secrets through env vars while `az bicep build-params` still
  validated locally (empty-string default). During the II-52 staging bootstrap
  this proved unreliable: with the env vars confirmed exported (`env | grep -c`
  returned 1), `az deployment group create --parameters staging.bicepparam`
  still received empty strings — Azure rejected the empty SQL password and the
  Container App secret validation failed with "value or keyVaultUrl and identity
  should be provided".
- **Where it surfaced:** drdatarulz/IntakeIt — II-52 staging bootstrap; the
  bicepparam pattern introduced in PR #53.
- **What the standards currently say:** Silent. No guidance on how `.bicepparam`
  files should source injected secret values, or on `readEnvironmentVariable()`
  vs explicit `--parameters` CLI overrides.
- **Counterfactual:** A human would likely have passed the secrets purely via
  `--parameters key=value` on the `az deployment group create` CLI from the
  start, or used `getSecret()` against a Key Vault — not `readEnvironmentVariable()`.
- **Workaround applied:** All deploys (local bootstrap + the three GitHub Actions
  workflows) pass the SQL params explicitly via
  `--parameters administratorLoginPassword=... --parameters sqlConnectionString=...`,
  which bypasses the bicepparam's `readEnvironmentVariable()` entirely. The
  `readEnvironmentVariable()` lines remain in the bicepparam files only so
  `az bicep build-params` validation passes — they are effectively dead at
  deploy time.
- **Decision needed:** Should the standards prescribe explicit `--parameters`
  overrides as the default mechanism for injecting secrets into Bicep deploys
  (with `readEnvironmentVariable()` discouraged)? And should the now-dead
  `readEnvironmentVariable()` lines be cleaned out of the IntakeIt bicepparam
  files and replaced with a clearer placeholder + comment?
- **Status:** Open.

