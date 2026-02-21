# Error Handling & API Response Conventions

## Error Response Format

- **Standard DTO** — all error responses use a consistent `ErrorResponse` shape
- Two fields: `Error` (string, always present) and `Detail` (nullable string, optional context)
- No Problem Details / RFC 9457 — keep it simple and predictable

```csharp
public record ErrorResponse
{
    public required string Error { get; init; }
    public string? Detail { get; init; }
}
```

## HTTP Status Code Conventions

| Code | Usage |
|------|-------|
| 200 | GET (single resource or list) |
| 201 | POST (create) — include `Location` header |
| 204 | PUT / DELETE (success, no body) |
| 400 | Validation failure — return `ErrorResponse` |
| 403 | Authorization failure — no body |
| 404 | Resource not found — no body |
| 429 | Rate limit exceeded |
| 500 | Unhandled exception — generic message only |

## Validation

- **Inline imperative checks** in endpoint handlers — no FluentValidation, no data annotations
- Validate at the API boundary, trust internal code
- Return early with `Results.BadRequest(new ErrorResponse { ... })`

```csharp
if (string.IsNullOrWhiteSpace(request.Subject))
    return Results.BadRequest(new ErrorResponse { Error = "Subject is required" });

if (request.ScheduledAt < DateTime.UtcNow)
    return Results.BadRequest(new ErrorResponse { Error = "Scheduled time must be in the future" });
```

## Authorization Failures

- **`Results.Forbid()`** with no body
- Never leak why access was denied
- Don't reveal whether the resource exists

## Not Found

- **`Results.NotFound()`** with no body
- Use when a specific resource lookup fails (e.g., GET by ID)

## Domain Service Errors

- **Return result objects** (e.g., `SendResult`) or nullable returns for expected failure cases
- Exceptions for truly exceptional situations only
- No generic `Result<T>` wrapper required — use purpose-built types when needed

```csharp
// Result object for operations with meaningful failure modes
public record SendResult(bool Success, string? ErrorMessage);

// Nullable return for simple "found or not" cases
Email? email = await emailRepository.GetByIdAsync(id);
if (email is null) return Results.NotFound();
```

## Pagination

- **Envelope pattern** — consistent shape across all list endpoints

```json
{
  "items": [],
  "totalCount": 42,
  "page": 1,
  "pageSize": 25
}
```

- Query parameters: `?page=1&pageSize=25`
- Default page size: 25. Maximum page size: 100.

## Global Exception Handling

- Unhandled exceptions are logged with full detail (stack trace, request context)
- Response to client: 500 with generic message — never expose stack traces or internal details in production
- Use middleware or Serilog request logging to capture the full picture server-side
