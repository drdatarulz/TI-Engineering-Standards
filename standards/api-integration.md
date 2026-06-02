# External API Integration Standards

## Spec-First Rule (Non-Negotiable)

Every external third-party API integration MUST have its contract committed to `docs/api-specs/` before any C# models are written. **No inference. No exceptions.**

- **External API** (third-party provider — you cannot read the source code): spec required on disk
- **Internal API** (your own codebase — you can read the source): infer from code

### What qualifies as a spec

| Format | File convention | Example |
|--------|----------------|---------|
| OpenAPI / Swagger (JSON or YAML) | `{provider}-openapi.json` | `athena-openapi.json` |
| ArcGIS REST layer definition | `{provider}-arcgis-layer{N}.json` | `fema-nfhl-layer28.json` |
| Manually documented response schema | `{provider}-schema.md` | `e2value-schema.md` |

A manually documented schema is acceptable when no machine-readable spec exists (e.g., legacy XML APIs), but it must contain:
- Every endpoint path and HTTP method
- Request format (headers, auth, body)
- Response field names, types, and nesting structure
- At least one verified sample response per endpoint

### What does NOT qualify as a spec

- PRD descriptions of what the API returns
- Ticket acceptance criteria describing expected behavior
- Training-data knowledge of what the API "probably" returns
- A single test response without field-level type definitions

**PRD prose describes product intent. API specs describe wire format. These are different things. Never substitute one for the other.**

## Storage Convention

```
docs/
  api-specs/
    {provider}-openapi.json        # OpenAPI / Swagger
    {provider}-arcgis-layer28.json # ArcGIS REST
    {provider}-schema.md           # Manual documentation
    {provider}-mapserver.json      # MapServer root (if needed)
```

Specs are committed to the repo so they are versioned, diffable, and available to all agents and developers. They are NOT stored in external wikis or shared drives.

## Model-Building Rules

When writing C# models for external API responses:

1. **Field names come from the spec, not from guesses.** The `[JsonPropertyName("...")]` value must match the exact field name in the spec (or example response). If the spec says `Pixel_Risk_Score`, the attribute says `Pixel_Risk_Score` — not `pixel_risk_score`, not `pixelRiskScore`.

2. **Types come from the spec, not from assumptions.** If the spec says a field is `type: object` or the example shows a JSON object `{...}`, the C# type must be an object type (`Dictionary<>`, a typed class, or `JsonElement`). Never map a spec object to a scalar (`string`, `decimal`, `int`).

3. **Nesting comes from the spec, not from simplification.** If the spec shows `response.data.metrics.score`, the C# models must have matching nesting. Do not flatten nested structures into a single class unless you also flatten the deserialization path.

4. **No fields are invented.** If a field does not appear in the spec or example responses, do not add it to the model. Phantom fields silently deserialize as null and mask the fact that the data was never available.

5. **Missing fields are noted.** If the spec contains fields you choose not to map (because they're not needed yet), add a code comment listing what was intentionally skipped. This prevents future developers from thinking the field doesn't exist.

## Skill Integration

### refine-story-v4

Stories involving external API integration are **blocked** from refinement until a spec exists in `docs/api-specs/`. The skill checks for the spec file and returns `STATUS: Blocked` if it's missing.

### implement-ticket-v4

Before writing any provider model, the skill validates:
- A spec file exists in `docs/api-specs/` for the provider
- All `[JsonPropertyName]` attributes match spec field names
- All C# types are compatible with spec types

If validation fails, the skill returns `STATUS: Blocked`.

### orchestrate-v4

The orchestrator checks for external API spec availability after refinement and before dispatching to implementation. If the spec is missing, the ticket is moved to Waiting/Blocked with a clear reason.

### engineering-review-v4

PR reviews that touch provider models should verify `[JsonPropertyName]` values against the committed spec. Mismatches are flagged as violations.

## Fetching Specs

When a spec is needed but not on disk:

1. Check the project's API Integration Reference doc for the spec URL
2. Attempt to fetch it (e.g., `curl -o docs/api-specs/{provider}-openapi.json {url}`)
3. Validate the downloaded file is well-formed (JSON parse check)
4. Commit it to the repo

If the spec cannot be fetched (requires authentication, not publicly available, etc.), the story is blocked until the spec is manually obtained.
