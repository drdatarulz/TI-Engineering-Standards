# UI Standards

## Framework

- **Blazor WebAssembly** — client-side SPA
- **MudBlazor** — Material Design component library
- Code-behind pattern: `.razor` for markup, `.razor.cs` for logic

## Rich Text Editing

- **Radzen.Blazor HtmlEditor** — free rich text editor (Quill.js), no API key required
- No paid editor components

## Component Patterns

### State Management

- Use a shared `AppState` service for cross-component state
- Components must subscribe to `AppState.OnChange` and implement `IDisposable` to unsubscribe
- This prevents race conditions where components read stale state

### Authentication

- `DevBypassAuthStateProvider` for development/testing — no real Azure AD required
- MSAL for production authentication
- `BaseAddressAuthorizationMessageHandler` auto-attaches tokens to HTTP requests

### API Services

- One API service class per resource (e.g., `EmailApiService`, `TeamApiService`)
- Services use `HttpClient` injected via DI
- All API calls go through typed service classes — no raw `HttpClient` in components

## Blazor WASM Hosting

- Served via nginx in Docker
- `docker-entrypoint.sh` for runtime config injection (replaces `appsettings.json` values at container start)
- Separate `appsettings.json` and `appsettings.Development.json` for environment-specific config

## Playwright Testing

- Page Object Model with helper classes (`BlazorPage`, `AddinPage`, etc.)
- Each test creates a fresh `IBrowserContext` for cookie/storage isolation
- Dev auth bypass — no real Azure AD in tests
- Route interception to inject test configuration
