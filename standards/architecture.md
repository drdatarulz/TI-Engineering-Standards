# Architecture Standards

## Dependency Inversion (Non-Negotiable)

- **Domain project has ZERO dependencies** — no NuGet packages, no project references
- All interfaces live in `{Project}.Domain/Interfaces/`
- All models live in `{Project}.Domain/Models/`
- Business logic depends ONLY on interfaces from Domain, NEVER on concrete implementations
- Infrastructure types (`DbConnection`, `HttpClient`, `SmtpClient`, `SslStream`, `TcpClient`) NEVER appear in interfaces — only in concrete classes in Infrastructure

## Interface-First Design

All infrastructure is abstracted behind provider-agnostic interfaces:
- Name interfaces for what they do, not what they use: `IEmailQueue` not `IAzureStorageQueue`
- Domain and service projects have ZERO cloud SDK knowledge
- Azure/AWS/GCP implementations live only in Infrastructure

## Project Layering

Every project follows this layered structure:

```
src/
  {Project}.Domain/           # Zero dependencies. Models + Interfaces only.
  {Project}.Infrastructure/   # All concrete implementations.
  {Project}.Api/              # Minimal API. Endpoints, DI registration, auth middleware.
  {Project}.Migrator/         # Console app. Runs DbUp migrations.
  ... additional service projects as needed ...

tests/
  {Project}.Domain.Tests/
  {Project}.Api.Tests/
  {Project}.Integration.Tests/
  {Project}.Playwright.Tests/
  {Project}.Fakes/            # Shared hand-rolled fakes for all test projects.
```

## Build Order

Follow this general sequence — each layer builds on the previous:

1. **Domain** — Models, interfaces, enums. Zero dependencies.
2. **Fakes** — Hand-rolled fakes for every interface. Grows with each step.
3. **Infrastructure** — Dapper repos, cloud queue/blob, external service clients. Write tests alongside.
4. **DbUp Migrator** — All SQL migration scripts. Verify schema creation.
5. **API** — Endpoints, DI, auth, validation. Test with fakes.
6. **Workers/Services** — Background services, CRON jobs. Test all paths.
7. **Client** — Blazor WASM + MudBlazor admin UI.
8. **Playwright Tests** — UI e2e tests.
9. **Dockerfiles + docker-compose.yml** — One Dockerfile per project, multi-stage builds.

## SOLID Principles

- **Dependency Inversion** is the foundation — all business logic depends on abstractions
- **Interface Segregation** — keep interfaces small and focused. If a fake is painful to write, the interface is too big
- All infrastructure concerns hidden behind interfaces

## Dependency Injection

- Use .NET built-in `Microsoft.Extensions.DependencyInjection` — no third-party IoC containers
- Register services in `Program.cs`
- Tests bypass the DI container entirely — new up classes with fakes directly
