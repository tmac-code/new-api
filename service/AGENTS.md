# service/ — Business Logic Layer

## OVERVIEW

The service layer owns business lifecycle logic: billing sessions, quota management, channel selection, format conversion, and user notifications. It does NOT own HTTP response formatting (controller/relay responsibility) or DB schema definitions (model/ responsibility). Service functions are called by controllers and relay handlers.

## WHERE TO LOOK

- **Billing lifecycle** — `billing_session.go` (BillingSession: preConsume/Settle/Refund), `billing.go` (PreConsumeBilling, SettleBilling entry points)
- **Funding abstraction** — `funding_source.go` (FundingSource interface, WalletFunding, SubscriptionFunding)
- **Tiered billing** — `tiered_settle.go` (TryTieredSettle, BuildTieredTokenParams); expressions in `pkg/billingexpr/expr.md`
- **Quota operations** — `quota.go` (PreConsumeTokenQuota, PostConsumeQuota, audio/text quota calc), `pre_consume_quota.go`
- **Conversion hotspots** — `convert.go` (Claude↔OpenAI, Gemini↔OpenAI format transforms)
- **Channel selection** — `channel_select.go` (CacheGetRandomSatisfiedChannel, cross-group retry), `channel_affinity.go` (affinity cache, rule matching, override templates)
- **Async task billing** — `task_billing.go` (separate conventions for async billing flows)

## CONVENTIONS

1. **BillingSession lifecycle** — Create via `NewBillingSession` → `preConsume` → `Settle` or `Refund`. Session is stored on `relayInfo.Billing`. Never call quota functions directly when a BillingSession exists.
2. **FundingSource** — Wallet and subscription are abstracted behind `FundingSource` interface (PreConsume/Settle/Refund). `WalletFunding.Refund` is non-idempotent (quota += N); `SubscriptionFunding.Refund` has requestId idempotent protection and retry logic.
3. **Tiered billing** — Must use frozen `BillingSnapshot` from `relayInfo.TieredBillingSnapshot`. Expression rules in `pkg/billingexpr/expr.md` govern `len` for tier conditions and token normalization. `BuildTieredTokenParams` normalizes GPT vs Claude semantic differences.
4. **Trust bypass** — `BillingSession.shouldTrust` skips pre-consume for wallet only; subscriptions cannot use trust bypass because `PreConsumeUserSubscription` requires `amount > 0` to lock subscription records.
5. **Channel affinity** — Rule-based cache keyed by model/path/user-agent. Match rules in `channel_affinity.go`, apply override templates via `ApplyChannelAffinityOverrideTemplate`. Usage stats tracked per-rule with hybrid Redis+memory cache.

## ANTI-PATTERNS

- Calling `PostConsumeQuota` directly when `relayInfo.Billing` (BillingSession) exists — use `SettleBilling` instead.
- Modifying `funding_source.go` retry logic — `refundWithRetry` is for transactional refunds only; wallet refunds cannot safely retry.
- Using non-pointer omitempty on optional relay DTO fields in service-to-relay data (see root AGENTS).
- Mutating `TieredBillingSnapshot` after creation — it is frozen at request time for consistent tier evaluation.

## NOTES

- Subscription trust-bypass is intentionally disabled (see `shouldTrust` in `billing_session.go`).
- `IncreaseUserQuota` is non-idempotent; refunding wallet quota must not be retried.
- `convert.go` handles cross-provider stream state machines (Claude SSE blocks, Gemini candidates). Do not break stream state transitions.
- See root `AGENTS.md` for project-wide conventions (JSON wrappers, multi-DB support, protected identity).
