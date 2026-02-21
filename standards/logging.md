# Logging & Observability

## Framework — Serilog

- **Serilog** for all projects — consistent structured logging
- Always `Enrich.FromLogContext()` for scoped properties
- Use `ILogger<T>` via DI throughout all services

### API Projects

```csharp
builder.Host.UseSerilog((context, config) =>
    config.ReadFrom.Configuration(context.Configuration));

app.UseSerilogRequestLogging();
```

### Console Apps

```csharp
Log.Logger = new LoggerConfiguration()
    .ReadFrom.Configuration(configuration)
    .Enrich.FromLogContext()
    .WriteTo.Console()
    .CreateLogger();
```

## Log Level Guidelines

| Level | Usage |
|-------|-------|
| Debug | Dev internals, detailed diagnostics (SQL queries, full payloads) |
| Information | Normal operations, business events (email sent, user logged in, job completed) |
| Warning | Degraded but functional — retries, fallbacks, suppression list hits |
| Error | Operation failed but service continues (send failure, parse error) |
| Fatal | Service cannot continue (missing config, DB unreachable at startup) |

## Structured Properties

- **Named placeholders** — never string interpolation in log messages

```csharp
// Good — structured, searchable
_logger.LogInformation("Sent email {EmailId} to {Count} recipients in {Elapsed}ms",
    email.Id, recipients.Count, elapsed);

// Bad — interpolated, loses structure
_logger.LogInformation($"Sent email {email.Id} to {recipients.Count} recipients");
```

### Standard Property Names

Use these consistently across all projects:

- `{CorrelationId}` — request/operation correlation
- `{UserId}` — acting user
- `{EmailId}` — email entity reference
- `{Count}` — quantity of items processed
- `{Elapsed}` — operation duration in milliseconds
- `{Status}` — result status (enum or string)
- `{Service}` — service/component name

## Correlation ID

- **Generate at the API boundary** or use an entity ID (e.g., EmailId) as the natural correlation ID
- Pass through queues as a message property
- Attach via `ILogger.BeginScope()` with a dictionary — all logs within scope include it automatically

```csharp
using (_logger.BeginScope(new Dictionary<string, object>
{
    ["CorrelationId"] = correlationId,
    ["EmailId"] = emailId
}))
{
    // All logs here include CorrelationId and EmailId
}
```

## What NOT to Log

- Connection strings, passwords, tokens, API keys
- Full email bodies or PII (names, personal email content)
- Log **identifiers and counts** instead of sensitive payloads

```csharp
// Good — identifiers only
_logger.LogInformation("Processing email {EmailId} with {AttachmentCount} attachments", id, count);

// Bad — sensitive content
_logger.LogInformation("Processing email with body: {Body}", email.HtmlBody);
```

## Level Defaults

### Production

```json
{
  "Serilog": {
    "MinimumLevel": {
      "Default": "Information",
      "Override": {
        "Microsoft.AspNetCore": "Warning",
        "System": "Warning"
      }
    }
  }
}
```

### Development

```json
{
  "Serilog": {
    "MinimumLevel": {
      "Default": "Debug",
      "Override": {
        "Microsoft.AspNetCore": "Information"
      }
    }
  }
}
```

## Health Checks

### API Projects

- **`/health/live`** — liveness probe. Returns 200 if the process is running. No dependency checks.
- **`/health/ready`** — readiness probe. Checks DB connectivity, returns 503 if unhealthy.

```csharp
builder.Services.AddHealthChecks()
    .AddSqlServer(connectionString, name: "database");

app.MapHealthChecks("/health/live", new HealthCheckOptions
{
    Predicate = _ => false // No checks — just "am I running?"
});
app.MapHealthChecks("/health/ready");
```

### CRON / Console Services

- No HTTP health endpoints — use **exit code** (0 = success, non-zero = failure)
- Container orchestrators use exit code for restart/alerting decisions
