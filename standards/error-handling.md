# Error Handling & API Response Conventions

## Error Response Format — RFC 7807 Problem Details

- **Use the built-in Problem Details middleware** — `builder.Services.AddProblemDetails()` in API startup
- All error responses follow the [RFC 7807](https://datatracker.ietf.org/doc/html/rfc7807) standard shape
- No custom `ErrorResponse` DTOs — use the framework's `Results.Problem()` and `Results.ValidationProblem()`

```csharp
// Program.cs — register Problem Details
builder.Services.AddProblemDetails();

// 400 — validation failure (structured field-level errors)
return Results.ValidationProblem(new Dictionary<string, string[]>
{
    ["Subject"] = ["Subject is required"],
    ["ScheduledAt"] = ["Scheduled time must be in the future"]
});

// 409 — business rule conflict (single error message)
return Results.Problem(
    detail: "Email has already been queued and cannot be edited",
    statusCode: StatusCodes.Status409Conflict);

// 500 — unhandled exceptions are automatically formatted as Problem Details by the middleware
```

### When to use which

| Method | Use case |
|--------|----------|
| `Results.ValidationProblem(errors)` | Input validation failures — returns 400 with per-field error dictionary |
| `Results.Problem(detail, statusCode)` | Business rule violations, conflicts — returns specified status code |
| Automatic (middleware) | Unhandled exceptions — returns 500 with generic message (no stack trace in production) |

## HTTP Status Code Conventions

| Code | Usage |
|------|-------|
| 200 | GET (single resource or list) |
| 201 | POST (create) — include `Location` header |
| 204 | PUT / DELETE (success, no body) |
| 400 | Validation failure — return `ValidationProblem` |
| 403 | Authorization failure — no body |
| 404 | Resource not found — no body |
| 429 | Rate limit exceeded |
| 500 | Unhandled exception — generic message only |

## Validation

- **Data annotation attributes** on request model properties — the primary validation mechanism
- The framework validates automatically and returns RFC 7807 `ValidationProblem` responses
- **Inline imperative checks** for cross-field or business-logic validation that attributes can't express
- Validate at the API boundary, trust internal code

### Data Annotations (preferred for field-level rules)

```csharp
public class ScheduleEmailRequest
{
    [Required]
    [MaxLength(998)]
    [JsonPropertyName("subject")]
    public string Subject { get; set; } = "";

    [Required]
    [JsonPropertyName("scheduledAt")]
    public DateTime ScheduledAt { get; set; }

    [Required]
    [MinLength(1)]
    [JsonPropertyName("recipients")]
    public List<RecipientRequest> Recipients { get; set; } = [];
}
```

### Common Attributes

| Attribute | Use case |
|-----------|----------|
| `[Required]` | Non-nullable fields that must be provided |
| `[MaxLength(n)]` / `[MinLength(n)]` | String/collection length constraints |
| `[Range(min, max)]` | Numeric range constraints |
| `[EmailAddress]` | Email format validation |
| `[RegularExpression]` | Pattern matching |
| `[StringLength(max, MinimumLength)]` | String length with both bounds |

### Imperative Checks (for business logic)

Use inline checks for validation that attributes can't express — cross-field rules, async lookups, or domain-specific logic:

```csharp
if (request.ScheduledAt < DateTime.UtcNow)
    return Results.ValidationProblem(new Dictionary<string, string[]>
    {
        ["ScheduledAt"] = ["Scheduled time must be in the future"]
    });
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
