# HomeBudget

HomeBudget is a Flutter app for managing a shared household budget on Android. Members can record expenses, set category limits, and follow spending together. Firebase Authentication and Cloud Firestore keep the household in sync across devices, while Firestore's offline cache supports temporary loss of connectivity.

## Features

- **Shared households:** create a household, invite members with a single-use code, approve requests, and manage membership.
- **Expenses:** add, search, edit, and filter shared or personal expenses. Each expense retains its original amount and currency.
- **Multiple currencies:** enter a conversion rate when recording an expense in a currency other than the household's main currency. Household totals use the converted amount.
- **Budgets and insights:** set monthly and category limits, filter the six-month trend by multiple categories, compare shared spending by member, and see current-month budget warnings.
- **Recurring expenses:** define a monthly amount, category, due day, and grace period. Record or link multiple payments, track partial and excess amounts, and see unpaid remainders in Insights.
- **Device security:** optional PIN and biometric lock. The device PIN is never stored in Firestore.
- **Appearance and guidance:** light and dark themes and a fourteen-step walkthrough and screen-specific help, covering setup, budgets, search, currencies, recurring payments and corrections.

## Getting started

The Flutter application is in [`mobile_flutter/`](mobile_flutter/). To run it, you need a current Flutter SDK, the Android SDK, and a Firebase project with Email/Password Authentication and Cloud Firestore enabled.

1. Register the Android app in Firebase using the application ID in [`mobile_flutter/android/app/build.gradle.kts`](mobile_flutter/android/app/build.gradle.kts).
2. Place the Firebase Android configuration at `mobile_flutter/android/app/google-services.json` and deploy [`mobile_flutter/firestore.rules`](mobile_flutter/firestore.rules) to your Firebase project. Review the rules and project ID before deployment.
3. From `mobile_flutter`, run:

   ```bash
   flutter pub get
   flutter analyze
   flutter test
   flutter run
   ```

For a walkthrough of the app, see the [user guide](mobile_flutter/docs/user-guide.md). Select **?** on a screen for its relevant tutorial slides, or open the full tutorial from the start screen.

For Android build and signing details, see the [Flutter project guide](mobile_flutter/README.md). Firestore rule tests are documented in [`mobile_flutter/firebase_rules_test/README.md`](mobile_flutter/firebase_rules_test/README.md).

## How data is handled

Households, members, categories, budgets, recurring templates, monthly obligation snapshots, and expenses are stored in Cloud Firestore. Access is controlled by Firestore Security Rules and verified Firebase accounts. App preferences and the optional device lock remain on the device. Firestore can cache household data locally for offline use and synchronize pending changes when connectivity returns.

Monetary amounts are stored as integer minor units to avoid floating-point rounding in expense records. For a foreign-currency expense, the app records the original amount and the conversion rate entered by the user.

Recurring templates do not create expenses automatically. One or more actual expenses can pay an obligation for a selected month. Deleting or unlinking a payment recalculates the remaining balance. Expected amounts are saved per month so later changes do not rewrite history. Overdue reminders appear while the app is open, without push notifications or a background scheduler.

## Project structure

| Path | Purpose |
| --- | --- |
| [`mobile_flutter/lib/app/`](mobile_flutter/lib/app/) | Screens, navigation, themes, and forms |
| [`mobile_flutter/lib/data/`](mobile_flutter/lib/data/) | Firebase services, cloud totals, and device settings |
| [`mobile_flutter/lib/utils/`](mobile_flutter/lib/utils/) | Money parsing and formatting |
| [`mobile_flutter/test/`](mobile_flutter/test/) | Flutter tests |
| [`mobile_flutter/firebase_rules_test/`](mobile_flutter/firebase_rules_test/) | Firestore Security Rules tests |

HomeBudget is currently distributed as an Android build from source; it is not listed on Google Play.
