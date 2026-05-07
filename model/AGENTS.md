# MODEL PACKAGE — new-api

## OVERVIEW

Data models + GORM database access layer. Central hub for DB initialization, migrations, and cross-DB compatibility. Supports SQLite, MySQL >= 5.7.8, PostgreSQL >= 9.6 simultaneously.

## WHERE TO LOOK

- **DB bootstrap & migrations** — `main.go` (`InitDB`, `migrateDB`, `migrateDBFast` — parallel migrations, `migrateLOGDB`). 24+ models registered in `AutoMigrate` list. `SubscriptionPlan` handled separately (SQLite manual table vs AutoMigrate).
- **Manual migrations** — `migrateTokenModelLimitsToText`, `migrateSubscriptionPlanPriceAmount`, `ensureSubscriptionPlanTableSQLite`. Always idempotent: check metadata before ALTER.
- **Cross-DB helpers** — Package-level vars in `main.go`: `commonGroupCol`, `commonKeyCol`, `commonTrueVal`, `commonFalseVal`, `logKeyCol`, `logGroupCol`. Set in `initCol()` based on `common.UsingPostgreSQL`.
- **DB-specific timestamps** — `db_time.go` shows raw SQL branching for PostgreSQL/SQLite/MySQL.
- **Model-to-channel mapping** — `ability.go` (Ability struct, chunked upserts, priority/weight routing). `TRUNCATE` vs `DELETE` branching for SQLite.
- **Channel memory cache** — `channel_cache.go` (`group2model2channels`, `channelsIDM`, `sync.RWMutex`, `InitChannelCache` full reload, `GetRandomSatisfiedChannel` priority+weight selection).
- **Hybrid cache** — `subscription.go` + `pkg/cachex`: `HybridCache[T]` with Redis backend + samber/hot memory LRU, namespace-scoped keys, TTL/capacity from env vars.
- **Legacy Redis cache** — `user_cache.go`, `token_cache.go`: direct `common.RedisHSetObj`, `RedisDelKey`, `RedisIncr` calls.

## CONVENTIONS

1. **Model structs** — Plain GORM structs. Use `gorm:"type:..."` for column types, `gorm:"default:..."` for defaults, `gorm:"index"` for indexes. Composite primaries via `gorm:"primaryKey"` on multiple fields. Soft deletes: embed `gorm.DeletedAt`. Runtime-only fields: `gorm:"-"`.
2. **TableName()** — Override only when GORM pluralization produces wrong names (e.g., `SubscriptionPlan` → `subscription_plans` is correct by default).
3. **Cross-DB raw SQL** — Use `commonGroupCol`/`commonKeyCol` for reserved words. SQLite: backtick `` `col` ``. PostgreSQL: double-quote `"col"`. Booleans: use `commonTrueVal`/`commonFalseVal` (1/0 for SQLite+MySQL, true/false for PostgreSQL).
4. **No ALTER COLUMN in SQLite** — Use DDL probe (`PRAGMA table_info`) + `ADD COLUMN` only, or full `CREATE TABLE` recreation. See `ensureSubscriptionPlanTableSQLite`.
5. **Cache patterns** — Three tiers coexist:
   - **Legacy Redis** (`user_cache.go`, `token_cache.go`): direct Redis calls, simple keys.
   - **Memory channel cache** (`channel_cache.go`): full in-memory maps, RWMutex, periodic full reload.
   - **Hybrid cache** (`subscription.go`, `pkg/cachex`): `cachex.NewHybridCache`, Redis fallback + memory LRU, namespaced, TTL-env-configurable. New code should prefer `cachex`.
6. **Chunked operations** — Use `lo.Chunk(slice, 50)` for batch inserts (see `ability.go`). Prevents oversized transactions.

## ANTI-PATTERNS

- Hardcoding column names that conflict with reserved words (use `commonGroupCol`, not `'"group"'`)
- `ALTER COLUMN` on SQLite (use `ADD COLUMN` or manual table recreation)
- Mixing MySQL `MODIFY COLUMN` and PostgreSQL `ALTER COLUMN ... TYPE` without `common.Using*` guards
- Using JSONB columns (use TEXT with JSON string)
- Adding new models without registering in `AutoMigrate` in `migrateDB`
- Forgetting `SubscriptionPlan` SQLite special handling (separate from main AutoMigrate list)
- Bypassing `cachex` hybrid cache for new caches when Redis is enabled

## NOTES

- See root `AGENTS.md` for project-wide conventions (JSON wrappers, DB branching flags, protected identity).
- `migrateDBFast` runs migrations in parallel goroutines with error channel aggregation.
- `LOG_DB` can be same as `DB` (default) or separate (when `LOG_SQL_DSN` set).
- `checkMySQLChineseSupport` validates charset/collation on MySQL startup.
