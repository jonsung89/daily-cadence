# Daily Cadence Architecture

## Project Structure
daily-cadence/
├── apps/
│   └── ios/                    # Swift + SwiftUI iOS app
│       ├── DailyCadence/       # (Will be created by Claude Code)
│       ├── DailyCadence.xcodeproj/
│       └── ...
├── packages/
│   └── backend/                # Firebase Cloud Functions + Firestore
│       ├── functions/
│       ├── models/
│       └── ...
├── design/                      # Design system & branding
│   ├── Daily_Cadence_Design_Branding_Guide.md
│   ├── Cadence_App_Name_Documentation.md
│   └── Daily_Cadence_Marketing_Document.md
├── docs/                        # Documentation
│   ├── ARCHITECTURE.md          # (this file)
│   └── PRODUCT_SPEC.md
└── README.md

## Phase 1: iOS MVP

- Daily timeline view
- Note creation/editing
- Exercise tracking with progress
- Calendar view
- Customizable dashboard
- Firebase backend

## Phase 2: Android

- Port to Android (React Native or native)
- Feature parity with iOS

## Phase 3: Web Dashboard

- Analytics and progress viewing
- Settings management
- Export data

## Development

- iOS: Swift + SwiftUI
- Backend: Firebase (Firestore, Cloud Functions, Auth)
- Version Control: GitHub