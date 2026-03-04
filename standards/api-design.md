# API Design Standards

## Endpoint Return Types — No Anonymous Types

- **Every endpoint must return a typed DTO** — never return anonymous objects (`new { id, name }`)
- No domain models exposed through API endpoints — always use dedicated request/response DTOs
- This applies to both public and internal endpoints

```csharp
// BAD — anonymous type
app.MapPost("/api/emails", async (ScheduleEmailRequest request, ...) =>
{
    var id = await repo.CreateAsync(email);
    return Results.Created($"/api/emails/{id}", new { id });
});

// GOOD — typed response DTO
app.MapPost("/api/emails", async (ScheduleEmailRequest request, ...) =>
{
    var id = await repo.CreateAsync(email);
    return Results.Created($"/api/emails/{id}", new ScheduleEmailCreatedResponse { Id = id });
});
```

```csharp
// BAD — domain model returned directly
app.MapGet("/api/emails/{id}", async (int id, ...) =>
{
    Email? email = await repo.GetByIdAsync(id);
    return email is null ? Results.NotFound() : Results.Ok(email);
});

// GOOD — map to response DTO
app.MapGet("/api/emails/{id}", async (int id, ...) =>
{
    Email? email = await repo.GetByIdAsync(id);
    return email is null ? Results.NotFound() : Results.Ok(email.ToResponse());
});
```

## Serialization Attributes

- **`[JsonPropertyName("camelCase")]`** on all request and response model properties
- Ensures explicit control over JSON wire format regardless of serializer configuration
- Prevents breaking changes if global serializer settings change

```csharp
public class EmailResponse
{
    [JsonPropertyName("id")]
    public int Id { get; set; }

    [JsonPropertyName("subject")]
    public string Subject { get; set; } = "";

    [JsonPropertyName("scheduledAt")]
    public DateTime ScheduledAt { get; set; }

    [JsonPropertyName("status")]
    public string Status { get; set; } = "";
}
```

## DTO Naming Conventions

- **Request models:** `{Verb}{Entity}Request` — e.g., `ScheduleEmailRequest`, `CreateSendingDomainRequest`, `UpdateTeamMemberRequest`
- **Response models:** `{Entity}Response` or `{Entity}{Qualifier}Response` — e.g., `EmailResponse`, `DeliveryStatsResponse`, `EmailStatusHistoryResponse`
- **Created responses:** `{Verb}{Entity}CreatedResponse` — for POST endpoints that return the created resource ID, e.g., `ScheduleEmailCreatedResponse`
- Organize in `Models/Requests/` and `Models/Responses/` directories within the API project

## `.Produces<T>()` Declarations

- **Every endpoint must declare its response types** using `.Produces<T>()` for OpenAPI documentation
- Include all possible response status codes

```csharp
app.MapGet("/api/emails/{id}", GetEmailByIdAsync)
    .Produces<EmailResponse>(200)
    .Produces(403)
    .Produces(404)
    .RequireAuthorization();
```

## Configuration — No Hard-Coded Fallbacks

- **Never use null-coalescing fallbacks for required configuration values**
- If a config value is missing, throw `InvalidOperationException` at startup — fail fast and loud
- Optional config with sensible defaults should use the Options pattern (see `configuration.md`)

```csharp
// BAD — masks configuration problems
var apiBaseUrl = builder.Configuration["ApiBaseUrl"] ?? "https://localhost:5000";

// GOOD — fails fast if config is missing
var apiBaseUrl = builder.Configuration["ApiBaseUrl"]
    ?? throw new InvalidOperationException("ApiBaseUrl configuration is required");
```

## Internal Endpoints

- Internal/service-to-service endpoints follow the **same rules** as public endpoints — typed DTOs, serialization attributes, no domain models
- Prefix internal endpoints with `/api/internal/` to distinguish from the public API surface
- Internal endpoints may bypass user-level authorization but should still require service-level auth (e.g., client credentials)
- Internal endpoints can be "thick" — performing multiple DB operations in one call to reduce network chattiness
