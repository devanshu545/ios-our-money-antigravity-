# OurMoney for iOS

Native SwiftUI port of the OurMoney Android app (Kotlin + Jetpack Compose), speaking to the
**same Firebase project** as the Android client: same Auth users, same Firestore documents,
same 6-digit pairing codes, same ledger math.

## Layout

```
OurMoney_iOS/
├── project.yml                 # XcodeGen spec (generates OurMoney.xcodeproj)
├── OurMoney/
│   ├── App/                    # Entry point, root auth-state switch, theme
│   ├── Models/                 # Codable models mirroring the Firestore schema
│   ├── Services/               # Auth, Ledger, User, AI repositories + Gemini + PDF
│   ├── Domain/                 # LedgerCalculator, BudgetAnalytics, AI context engine
│   ├── ViewModels/             # Dashboard, AddExpense, SettleUp, History, Analytics,
│   │                           # Budgets, Goals, AI, Settings
│   ├── Views/                  # SwiftUI screens (auth, 6 tabs, forms, AI chat)
│   └── Resources/              # Info.plist, entitlements, assets, app icon
├── OurMoneyTests/              # XCTest for financial logic
├── tools/generate_icon.py      # Renders the 1024px app icon (stdlib only)
└── .github/workflows/build-ipa.yml
```

## Build the IPA (no Mac required)

1. Push this folder to a **public** GitHub repository (the workflow runs on GitHub's macOS
   runners, free for public repos).
2. GitHub Actions → *Build OurMoney IPA* → wait for green.
3. Download the `OurMoney-unsigned-ipa` artifact → `OurMoney.ipa` (arm64 device build,
   unsigned).
4. Drag the IPA into **Sideloadly** with your Apple ID → install on your iPhone.

The workflow also runs the unit tests on an iOS Simulator before archiving.

## Build locally (Mac)

```bash
brew install xcodegen
cd OurMoney_iOS
xcodegen generate
open OurMoney.xcodeproj   # select the OurMoney scheme, Product → Archive
```

## Before first run (required)

1. **Firebase**: add an iOS app (`com.devanshu.ourmoney.ios`) in the **same** Firebase
   project the Android app uses → download `GoogleService-Info.plist` → drop it into
   `OurMoney/Resources/` (and add it to the Xcode target if not using XcodeGen's
   automatic resource inclusion).
2. **Google Sign-In**: in `Info.plist` replace both `REVERSED_CLIENT_ID_PLACEHOLDER` values
   with the `REVERSED_CLIENT_ID` from `GoogleService-Info.plist` (one for `CFBundleURLSchemes`,
   one for `GIDClientID`).
3. **Gemini**: set the `GEMINI_API_KEY` environment variable when building (CI: repository
   secret; Xcode: build configuration setting) — same key the Android app uses via `.env`.

See `IOS_SETUP.md` for the complete checklist.
