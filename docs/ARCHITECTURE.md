# DailyCadence Architecture

## Project Structure

```
daily-cadence/
├── apps/
│   └── ios/                    # Swift + SwiftUI iOS app
│       └── DailyCadence/       # Xcode project (created in Xcode)
├── packages/
│   └── backend/                # Reserved for a future Node/Next.js service (not used in Phase 1)
├── supabase/
│   └── migrations/             # SQL schema migrations (created when schema work begins)
├── design/                     # Design system & branding
│   └── Daily_Cadence_Design_Branding_Guide.md
├── docs/
│   └── ARCHITECTURE.md         # this file
└── README.md
```

## Phase 1: iOS MVP

**Scope**
- Daily timeline view
- Note creation / editing with typed cards (Workout, Meal, Sleep, Mood, Activity)
- Exercise tracking with Swift Charts progress visualization
- Calendar view
- Customizable dashboard
- Supabase auth + data sync

**iOS stack**
- SwiftUI, Swift 5.9+
- iOS 26.0 minimum deployment target (raised from 17.6 in Phase E.2 — needed for the native `TextEditor(text: $attributedString, selection: $selection)` API and `AttributedString.transformAttributes(in: &selection)` used by rich-text note bodies)
- `@Observable` macro for view models
- `NavigationStack` for navigation
- SwiftData for offline / local cache
- Swift Charts for progress graphs
- `async`/`await` for all I/O

**Backend (Phase 1 = Supabase direct, no middle-tier)**
- Supabase Postgres with Row-Level Security per user
- Supabase Auth: Sign in with Apple (`AuthenticationServices`) + Google (via Supabase OAuth)
- Supabase Swift SDK (`supabase-community/supabase-swift`) called directly from iOS
- Schema maintained as SQL migrations in `supabase/migrations/`

**Deployment**
- iOS → TestFlight
- DB / auth → Supabase cloud (free tier)

## Phase 2+: backend service

When server-side logic is needed (scheduled jobs, aggregations, webhooks, integrations), add a **Next.js (App Router) service on Vercel** as the recommended path. Express remains acceptable. The `packages/backend/` folder is the home for this service when it's introduced.

## Phase 3+: other surfaces

- Android port (native or React Native — to be decided)
- Web dashboard for analytics / settings (likely the same Next.js app as the backend)

## Development tooling

- Xcode 15+ on macOS
- Swift Package Manager for iOS dependencies (Supabase Swift SDK)
- Supabase CLI for local DB + migrations
- GitHub for version control
