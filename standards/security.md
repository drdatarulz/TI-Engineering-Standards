# Security Baseline

## Input Validation

- **Validate at the API boundary only** — endpoints are the trust boundary
- Check: required fields, string lengths, numeric ranges, enum values, temporal constraints
- Match string lengths to DB column widths (e.g., `NVARCHAR(320)` for email → validate ≤ 320 chars)
- Trust internal code — services, repositories, and domain logic do not re-validate

## Authentication

### Production — Azure AD (Entra ID)

- JWT bearer tokens validated by ASP.NET Core middleware
- Configure `Authority` and `Audience` via appsettings / environment variables
- Claims used: `oid` (user object ID), `preferred_username` (email), `name` (display name)

### Development — Dev Bypass

- Toggle: `Authentication:UseDevBypass` (boolean)
- When enabled, a custom authentication handler accepts requests without real tokens
- Dev bypass provides configurable claims for testing different user roles
- **Never enable in production** — enforce via environment-specific configuration

## Middleware Order

Order matters — follow this sequence exactly:

```csharp
app.UseSerilogRequestLogging();
app.UseCors();
app.UseAuthentication();
app.UseAuthorization();
app.UseRateLimiter();
// Custom middleware (user resolution, etc.)
```

## User Resolution

- **Middleware** resolves the authenticated user from JWT claims into a domain user object
- Store the resolved user in `HttpContext.Items` for the duration of the request
- Endpoints access the current user via an extension method (e.g., `HttpContext.GetCurrentUser()`)
- **Auto-provision on first login** — if the user exists in Azure AD but not in the app database, create the user record automatically

## CORS

- **Config-driven** — `Cors:AllowedOrigins` array in appsettings
- Explicit origins only — **no wildcards (`*`) in production**
- `AllowCredentials()` for requests that include authentication

```csharp
builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
    {
        policy.WithOrigins(corsOrigins)
              .AllowAnyHeader()
              .AllowAnyMethod()
              .AllowCredentials();
    });
});
```

## Rate Limiting

- **.NET built-in** `AddRateLimiter()` — no third-party libraries
- **Fixed window** per user, keyed on `oid` claim (fallback to IP for unauthenticated requests)
- Default: 60 requests per minute
- Returns HTTP 429 when exceeded

```csharp
builder.Services.AddRateLimiter(options =>
{
    options.AddFixedWindowLimiter("default", config =>
    {
        config.Window = TimeSpan.FromMinutes(1);
        config.PermitLimit = 60;
        config.QueueLimit = 0;
    });
    options.RejectionStatusCode = 429;
});
```

## Secrets Management

| Layer | What Goes Here |
|-------|---------------|
| appsettings.json | Structure, defaults, non-sensitive values |
| Environment variables | Per-environment overrides (URLs, feature flags) |
| Azure Key Vault | Passwords, client secrets, API keys, private keys |

- **Placeholder pattern** for secrets in appsettings: `"REPLACE_ME_OR_SET_ENV_Section__Key"`
- Never log secrets — see [logging.md](logging.md) for details
- Never commit secrets to source control

## Authorization

- **Every endpoint checks authorization** before returning data
- Use `Results.Forbid()` with no body — don't leak why access was denied
- Don't reveal whether a resource exists to unauthorized users (return 403, not 404)
- Authorization logic lives in a dedicated service (e.g., `IAppAuthorizationService`) — endpoints call it, not inline policy checks
