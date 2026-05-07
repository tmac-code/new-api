# PROJECT KNOWLEDGE BASE — new-api

Generated: 2026-05-07 | Commit: e8cfb546 | Branch: ai_v1.0

## OVERVIEW

AI API gateway/proxy aggregating 40+ upstream providers (OpenAI, Claude, Gemini, Azure, AWS Bedrock) behind a unified API. Features user management, billing, rate limiting, admin dashboard. Go 1.22+ backend with Gin + GORM v2. Frontend in web/default (React 19, Rsbuild, Base UI, Tailwind) and web/classic (React 18, Vite, Semi Design). DB: SQLite, MySQL >= 5.7.8, PostgreSQL >= 9.6. Cache: Redis + in-memory. Auth: JWT, WebAuthn, OAuth.

main.go embeds web/default/dist and web/classic/dist for serving. LSP not assumed available; rely on commands and tests if LSP missing.

## STRUCTURE

```
router/         → HTTP routing (API, relay, dashboard, web)
controller/     → Request handlers (Gin)
service/        → Business logic
model/          → Data models + DB access (GORM)
relay/          → Relay/proxy; relay/channel/ → provider adapters (openai/, claude/, gemini/, aws/)
middleware/     → Auth, rate-limit, CORS, logging, distribution
setting/        → Config management (ratio, model, operation, system, performance)
common/         → Shared utils (json wrapper, crypto, Redis, env, rate-limit)
dto/            → Request/response structs
constant/       → API types, channel types, context keys
types/          → Type definitions (relay formats, file sources, errors)
i18n/           → Backend i18n (go-i18n, en/zh)
oauth/          → OAuth providers
pkg/            → Internal packages (billingexpr/, cachex/, ionet/)
web/default/    → Default theme (React 19, Rsbuild, Bun)
web/classic/    → Classic theme (React 18, Vite)
```

## WHERE TO LOOK

- Backend flow: router → controller → service → model
- Relay flow: router/relay → controller.Relay → relay handlers → relay/channel adapters
- DB migrations: model/main.go patterns, use common.Using* flags for branching
- Billing logic: pkg/billingexpr/ — read expr.md before any changes
- Config: setting/ directory and common/ utilities
- Frontend: web/default/src/ for components, web/default/src/i18n/ for translations
- Tests: *_test.go colocated with source; no frontend test runner configured

## CONVENTIONS

1. **JSON** — Always use common/json.go wrappers (Marshal, Unmarshal, etc.). Never call encoding/json directly in business code. Type references (json.RawMessage) are fine.
2. **Database** — All three DBs must work simultaneously. Prefer GORM abstractions. Raw SQL: handle quoting diffs ("" vs `` ` ``), booleans (true/false vs 1/0), use commonGroupCol/commonKeyCol from model/main.go. Use common.UsingPostgreSQL/UsingSQLite/UsingMySQL flags when needed. No ALTER COLUMN in SQLite.
3. **Frontend package manager** — Use Bun for web/default/ (install, dev, build, i18n:sync).
4. **StreamOptions** — New channels supporting StreamOptions must be added to streamSupportedChannels.
5. **Relay DTOs** — Optional scalar fields use pointer types with omitempty. Absent => nil => omitted. Explicit zero/false => non-nil pointer => sent upstream. Non-pointer scalars with omitempty drop zero values silently.
6. **Billing expressions** — Read pkg/billingexpr/expr.md first. Covers architecture, expression language, token normalization, quota conversion, expression versioning.
7. **Protected identity** — nеw-аpi and QuаntumΝоuѕ identity references MUST NOT be modified, deleted, or replaced. Includes README, copyright, module paths, Docker images, docs, comments.

## ANTI-PATTERNS

- Importing encoding/json directly instead of common.* wrappers
- Using MySQL-only functions (GROUP_CONCAT) without PostgreSQL equivalent (STRING_AGG)
- Using PostgreSQL-only operators (@>, ?, JSONB) without fallbacks
- ALTER COLUMN on SQLite (unsupported)
- Using JSONB column types (use TEXT with JSON)
- Non-pointer omitempty on optional relay DTO fields (losing explicit zeros)
- Deleting or renaming new-api / QuantumNous references anywhere in the codebase

## COMMANDS

Backend: `go build`, `go test ./...` (colocated *_test.go)
Frontend default: `cd web/default && bun install && bun run dev && bun run build && bun run i18n:sync`
Frontend classic: `cd web/classic` (Vite-based, separate stack)

## NOTES

- Repo scale: ~1976 files, ~257k Go/TS/JS lines, depth 9, 104 large files
- web/default/AGENTS.md contains additional frontend-specific guidance
- Backend i18n: go-i18n/v2, en/zh. Frontend i18n: i18next, zh/en/fr/ru/ja/vi
