# PROJECT KNOWLEDGE BASE — new-api/relay

Generated: 2026-05-07 | Commit: e8cfb546 | Branch: ai_v1.0

## OVERVIEW

Relay/proxy layer that routes requests to 40+ upstream providers and returns normalized responses. Core flow: init relay info, model mapping, convert request, marshal, remove disabled fields, apply param override, send request, handle response, post-consume billing. All three DB variants (SQLite/MySQL/PostgreSQL) must work simultaneously.

## STRUCTURE

```
channel/        → Provider adapters (openai/, claude/, aws/, gemini/, etc.)
common/         → RelayInfo, BillingSettler, param override, stream status
constant/       → Relay-specific mode constants (chat, embed, image, etc.)
helper/         → Stream scanner/writer, price calc, request validation
reasonmap/      → Reasoning-effort-to-model mapping
*handler.go     → Endpoint handlers (compatible, claude, gemini, responses, etc.)
relay_adaptor.go → Adaptor registry (GetAdaptor by ApiType)
relay_task.go    → Async task polling flow (TaskAdaptor)
```

## WHERE TO LOOK

- Handler dispatch: `compatible_handler.go` (TextHelper), `responses_handler.go`, `claude_handler.go`, `gemini_handler.go`
- Adapter registry: `relay_adaptor.go`
- Adapter interfaces: `channel/adapter.go` (Adaptor + TaskAdaptor)
- Relay context: `common/relay_info.go` (RelayInfo, supportStreamOptions, init flow)
- Stream pipeline: `helper/stream_scanner.go` (StreamScannerHandler, shared scanner, writeMutex)
- Billing lifecycle: `common/billing.go` (BillingSettler interface: Settle/Refund/Reserve)
- Price calculation: `helper/price.go`; Model mapping: `helper/model_mapped.go`
- Param override: `common/override.go`; Disabled fields: `common/relay_utils.go`

## CONVENTIONS

1. **Handler flow** — `InitChannelMeta` → `ModelMappedHelper` → StreamOptions handling → `GetAdaptor` → `adaptor.Init` → convert/marshal → `RemoveDisabledFields` → `ApplyParamOverride` → `adaptor.DoRequest` → `adaptor.DoResponse` → `PostTextConsumeQuota`/`PostAudioConsumeQuota`.
2. **Adaptor interfaces** — Implement `Adaptor` (sync) or `TaskAdaptor` (async polling). Each converter method returns the provider-native payload for that endpoint type.
3. **StreamSupportedChannels** — New channels supporting StreamOptions must be added to `streamSupportedChannels` in `common/relay_info.go`. Without registration, `info.SupportStreamOptions` stays false and StreamOptions is stripped.
4. **Shared stream scanner** — Use `helper.StreamScannerHandler` with a `dataHandler` callback; do not hand-roll SSE scanning. Writers are protected by `sync.Mutex`. Ping, timeout, and stop channels are managed centrally.
5. **Billing** — Use `BillingSettler` (stored on RelayInfo): `Settle(actualQuota)` for post-consumption, `Refund(c)` on error/abort, `Reserve(targetQuota)` to bump pre-charge. Do not hand-roll quota logic in channel adapters.

## ANTI-PATTERNS

- Hand-rolling SSE scanners instead of using `StreamScannerHandler`
- Forgetting to add channel type to `streamSupportedChannels` when it supports streaming
- Hand-rolling billing/quota logic outside the `BillingSettler` lifecycle
- Modifying `streamSupportedChannels` without testing upstream provider compatibility
