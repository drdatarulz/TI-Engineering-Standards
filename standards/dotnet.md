# .NET Conventions

## Runtime

- **.NET LTS releases** — always target the current LTS version
- Currently: .NET 10 LTS (net10.0)

## API Style — Minimal APIs

- **No controllers, no MVC** — use `MapGet`, `MapPost`, etc.
- Organize endpoints into extension method classes, one per resource group

### Pattern

```csharp
// Program.cs
app.MapEmailEndpoints();
app.MapUserEndpoints();
app.MapTeamEndpoints();

// Each in its own file: Endpoints/EmailEndpoints.cs, etc.
public static class EmailEndpoints
{
    public static void MapEmailEndpoints(this WebApplication app)
    {
        var group = app.MapGroup("/api/emails").RequireAuthorization();
        group.MapPost("/", ScheduleEmail);
        group.MapGet("/", ListEmails);
        // etc.
    }
}
```

## Data Access — Dapper

- **Dapper only** — raw SQL, no Entity Framework, no LINQ-to-SQL
- SQL lives in the repository classes in Infrastructure
- No stored procedures — all SQL inline in C# (keep queries near the code that uses them)

## Database Migrations — DbUp

- **DbUp** — plain SQL migration scripts
- Numbered sequentially: `001_CreateUsersTable.sql`, `002_CreateTeamsTable.sql`, etc.
- **Forward-only** — no down migrations
- Scripts live in `Infrastructure/Migrations/`
- Migrator is a standalone console app that runs DbUp

## Configuration

- `appsettings.json` for defaults and structure
- Environment variables for environment-specific overrides
- Azure Key Vault (or equivalent) for secrets only
- .NET configuration layering: environment variables override appsettings, secrets override both

## Logging

- **Serilog** — structured logging with appropriate sinks per environment
- Use `ILogger` throughout all services
- Include correlation IDs for cross-service tracing

## Container Strategy

- **One Dockerfile per project** in each project's folder
- **Multi-stage builds** — SDK image for build, slim runtime image for final
- `.dockerignore` at solution root excludes test projects, build artifacts, git history
- Blazor WASM projects use nginx with `docker-entrypoint.sh` for runtime config injection
- Images built once and promoted through environments — never rebuilt
