# Configuration Management

## Options Pattern

- **Strongly-typed options classes** bound from configuration sections
- Each options class has a `public const string SectionName` for the config key
- Register via `services.Configure<T>(config.GetSection(T.SectionName))`
- Inject via `IOptions<T>` (singleton), `IOptionsSnapshot<T>` (scoped), or `IOptionsMonitor<T>` (live reload)

```csharp
public class SmtpOptions
{
    public const string SectionName = "Smtp";

    public int Port { get; set; } = 25;
    public int TimeoutSeconds { get; set; } = 30;
    public int MaxRetries { get; set; } = 3;
}

// Registration
builder.Services.Configure<SmtpOptions>(
    builder.Configuration.GetSection(SmtpOptions.SectionName));
```

## Class Convention

- Lives in the project that owns the configuration (e.g., `SmtpOptions` in Infrastructure, `AuthOptions` in Api)
- Auto-properties with sensible defaults
- Parameterless constructor (implicit or explicit)
- No validation logic in the options class — validate at usage site if needed

## Configuration Layering

Sources are loaded in order — last wins:

1. **appsettings.json** — defaults, structure, non-sensitive values
2. **appsettings.{Environment}.json** — environment-specific overrides (Development, Staging, Production)
3. **Environment variables** — deployment-time overrides
4. **Azure Key Vault** — production secrets (loaded via `AddAzureKeyVault()`)

## Environment Variable Naming

- Double-underscore replaces colon for nested sections: `Smtp:Port` → `Smtp__Port`
- Case-insensitive on Windows, case-sensitive on Linux — use exact casing to be safe

```bash
# Example: override SMTP port
export Smtp__Port=587

# Example: override connection string
export ConnectionStrings__DefaultConnection="Server=..."
```

## What Goes Where

| Location | Contents |
|----------|----------|
| appsettings.json | Structure, defaults, non-sensitive values (timeouts, page sizes, feature flags) |
| appsettings.Development.json | Local connection strings, verbose logging, dev bypass toggles |
| Environment variables | Per-environment URLs, feature flags, non-secret overrides |
| Azure Key Vault | Passwords, client secrets, API keys, DKIM private keys |

## Feature Flags

- **Simple boolean config** — e.g., `Authentication:UseDevBypass`, `Features:EnableGraphRelay`
- Read at startup for DI branching (register real vs. fake implementation)
- No feature flag framework needed — `IConfiguration.GetValue<bool>()` is sufficient

```csharp
if (builder.Configuration.GetValue<bool>("Authentication:UseDevBypass"))
{
    // Register dev bypass auth handler
}
else
{
    // Register Azure AD auth handler
}
```

## Console App Configuration Loading

Console apps build configuration manually (no `WebApplicationBuilder`):

```csharp
var configuration = new ConfigurationBuilder()
    .AddJsonFile("appsettings.json", optional: false)
    .AddJsonFile($"appsettings.{environment}.json", optional: true)
    .AddEnvironmentVariables()
    .Build();
```

- Same layering order as API projects
- Environment determined by `DOTNET_ENVIRONMENT` or `ASPNETCORE_ENVIRONMENT` variable
