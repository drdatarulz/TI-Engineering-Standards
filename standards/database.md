# Database Standards

## Engine

- **SQL Server** — primary database

## Primary Keys

- All tables use **`INT IDENTITY(1,1)`** primary keys
- No GUIDs as primary keys — ever

## Timestamps

- All timestamps are **`DATETIME2`**
- All default to **`SYSUTCDATETIME()`** — store everything in UTC
- Never use `DATETIME`, `GETDATE()`, or local time

## Naming Conventions

- Tables: PascalCase plural (`Users`, `Teams`, `ScheduledEmails`)
- Columns: PascalCase (`CreatedAtUtc`, `SendAsUserId`)
- Foreign keys: `FK_{ChildTable}_{ParentTable}` or `FK_{ChildTable}_{RoleName}`
- Unique constraints: `UQ_{Table}_{Column(s)}`
- Check constraints: `CK_{Table}_{Column}`
- Indexes: `IX_{Table}_{Column(s)}`

## Soft Deletes

- Use soft deletes where audit trail matters (e.g., `RevokedAtUtc DATETIME2 NULL`)
- Hard delete for operational data that doesn't need history

## Indexes

- Filtered indexes where appropriate (e.g., `WHERE Status = 'Pending'`, `WHERE RevokedAtUtc IS NULL`)
- Cover the queries your services actually run — don't index speculatively

## Migrations

- **DbUp** — forward-only SQL migration scripts
- Scripts in `Infrastructure/Migrations/`, numbered: `001_CreateUsersTable.sql`, etc.
- No down migrations — ever
- Each script is idempotent where practical (use `IF NOT EXISTS` for DDL)

## Address/String Fields

- Use appropriate `NVARCHAR(n)` lengths — avoid `NVARCHAR(MAX)` unless truly unbounded content (like email body HTML)
- Semicolon-delimited for multi-value fields (e.g., email addresses) with reasonable max lengths
