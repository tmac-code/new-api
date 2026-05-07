# system-settings Feature

Settings admin domain with nested section routing, driven by a shared `SettingsPage` shell and per-domain section registries.

## OVERVIEW

Each sub-domain (auth, models, billing, etc.) is a settings "page" containing multiple sections navigated via sidebar. Pages are driven by a generic `SettingsPage` component that fetches system options and delegates rendering to a section registry. Sections are registered in a `section-registry.tsx` file per domain, each with `id`, `titleKey`, `descriptionKey`, and a `build()` factory returning JSX.

## STRUCTURE

```
system-settings/
├── index.tsx                  # Root wrapper (Outlet for router)
├── types.ts                   # All settings DTOs (AuthSettings, ModelSettings, BillingSettings, etc.)
├── api.ts                     # API calls (getOptions, updateOption)
├── components/                # Shared shell components
│   ├── settings-page.tsx      # Generic page: fetches options, resolves active section, renders content
│   ├── settings-section.tsx   # Card wrapper for individual sections
│   ├── settings-accordion.tsx # Collapsible section layout
│   └── ...
├── hooks/                     # Shared hooks
│   ├── use-system-options.ts  # Fetches /api/system/options via React Query
│   ├── use-settings-form.ts   # Form state + save mutation
│   ├── use-update-option.ts   # Single option update mutation
│   └── ...
├── utils/
│   └── section-registry.ts    # createSectionRegistry() factory
├── content/                   # Content settings domain
│   ├── index.tsx              # Domain page (default values + SettingsPage wiring)
│   └── section-registry.tsx   # Section definitions (dashboard, announcements, chat, etc.)
├── auth/ models/ billing/ general/ operations/ security/ site/ request-limits/ integrations/ maintenance/
│   └── Each follows the same pattern: index.tsx + section-registry.tsx + domain-specific cards
└── models/
    └── tiered-pricing-editor.tsx  # Large hotspot: billing expression editor (1800+ lines)
```

## WHERE TO LOOK

- **Add a new settings domain**: Copy an existing domain's `index.tsx` + `section-registry.tsx` pattern, register route in `src/routes/`.
- **Add a section to an existing domain**: Edit that domain's `section-registry.tsx`, add an entry to the sections array with `id`, `titleKey`, `descriptionKey`, `build()`.
- **Settings data flow**: `use-system-options` → `getOptionValue(data, defaultSettings)` → resolved settings object → passed to `build()` functions.
- **Form save logic**: `use-settings-form` hook handles collect → submit via `api.ts`, invalidates query cache on success.
- **New settings option**: Add field to the matching type in `types.ts`, set default in domain's `index.tsx`, ensure backend returns the key.

## CONVENTIONS

1. **Section registries** — Each domain has a `section-registry.tsx` using `createSectionRegistry()` from `utils/section-registry.ts`. Exports: `*_SECTION_IDS`, `*_DEFAULT_SECTION`, `get*SectionNavItems`, `get*SectionContent`.
2. **SettingsPage** — Generic wrapper accepting `routePath`, `defaultSettings`, `defaultSection`, `getSectionContent`. Handles loading, option resolution, and active section dispatch.
3. **SettingsCard / SettingsSection** — Domain sections are wrapped in `SettingsCard` (header + description + content) or `SettingsSection`. Keep layout consistent.
4. **i18n** — Use `useTranslation()` in components; `titleKey`/`descriptionKey` in section definitions are i18n keys (e.g., `'Basic Authentication'`). Register dynamic keys in `src/i18n/static-keys.ts` when adding new user-facing strings.
5. **Forms** — Use `use-settings-form` for domain-level forms. Complex forms use React Hook Form + Zod validation patterns (see `web/default/AGENTS.md` section 3.7).
6. **JSON settings** — Many settings are JSON strings (ratios, model configs). Use `utils/json-parser.ts` and `utils/json-validators.ts` for safe parse/validate. Never parse untrusted JSON without try/catch.
7. **Billing expressions** — Changes to `models/tiered-pricing-editor.tsx` or `billing/` must follow root `pkg/billingexpr/expr.md` guidance. Read it before modifying billing logic, condition builders, or expression parsing.
8. **Type defaults** — `types.ts` defines the shape of each settings domain. Default values are set in each domain's `index.tsx`. Keep them in sync with backend option keys.

## ANTI-PATTERNS

- Do not bypass `SettingsPage` with ad-hoc data fetching; use the registry pattern.
- Do not add section entries without `titleKey` and `descriptionKey` (they feed the sidebar navigation).
- Do not hardcode i18n strings in JSX. Always use `t()` and register keys in `static-keys.ts`.
- Do not parse JSON strings from settings without the utilities in `utils/json-parser.ts` or `utils/json-validators.ts`.
- Do not modify billing expression logic without reading `pkg/billingexpr/expr.md` first.
