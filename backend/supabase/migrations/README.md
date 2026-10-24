# Incremental migrations

New schema changes belong here as sequentially numbered files:

```
00034_short_description.sql
00035_next_change.sql
```

The fresh-install baseline is `../schema/001_fresh_schema.sql`. It already contains everything through migration `00033`; the original files are preserved in `../archive/migrations/` for history.

## Rules

1. Never edit a migration that has already been applied to a production project.
2. Prefer idempotent DDL: `CREATE TABLE IF NOT EXISTS`, `CREATE OR REPLACE FUNCTION`, `DROP POLICY IF EXISTS`, `ALTER TABLE ... ADD COLUMN IF NOT EXISTS`.
3. Keep business writes inside `SECURITY DEFINER` RPC functions. Do not grant direct client writes to financial or ledger tables.
4. If a migration changes RLS or grants, state the affected roles and tables in a header comment.
5. Add a matching row to `schema_migrations` at the end of the migration:

```sql
INSERT INTO schema_migrations (version, description)
VALUES ('00034', 'short description')
ON CONFLICT (version) DO NOTHING;
```

6. Reload the PostgREST schema cache when you add or change exposed objects:

```sql
NOTIFY pgrst, 'reload schema';
```

7. Do not renumber or rewrite history. If a migration was wrong, fix it in the next numbered file.
