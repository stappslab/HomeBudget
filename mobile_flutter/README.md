# Home Budget for Android

This directory contains the Flutter application. For an overview of its features and data model, see the [repository README](../README.md).

## Requirements

- Flutter and a compatible Android SDK
- A Firebase project with Email/Password Authentication and Cloud Firestore
- The Android Firebase configuration at `android/app/google-services.json`
- Firestore Security Rules from [`firestore.rules`](firestore.rules), deployed to the intended Firebase project
- Firestore indexes from [`firestore.indexes.json`](firestore.indexes.json), deployed to the same project

The Android application ID is defined in [`android/app/build.gradle.kts`](android/app/build.gradle.kts). Keep it consistent with the registered Firebase Android app. Choose a permanent, unique ID before publishing to an app store.

## Run and verify

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

To build an Android debug APK:

```bash
flutter build apk --debug
```

The APK is written to `build/app/outputs/flutter-apk/app-debug.apk`. Debug builds are for testing and are considerably larger than release builds.

The Firestore rule tests use the Firebase Local Emulator Suite. See [`firebase_rules_test/README.md`](firebase_rules_test/README.md) for the commands and prerequisites.

The home screen and Insights listen to the latest six months of expenses. Activity loads up to 100 expenses at a time for the selected period; its search and displayed total cover the loaded entries. Older pages can be loaded on demand. Shared spending since reset uses Firestore sum queries across the full history, so it needs a connection and the deployed indexes. Current-month totals continue to use cached expense documents while offline.

## Recurring payments and insights

In **Expenses → Recurring**, the owner manages monthly obligations: expected amount, currency, category, sharing, due day and grace period. Nothing is added to spending until a real expense is recorded. An obligation can have several payments, including payments by different members. Its status shows expected, paid, remaining and overpaid amounts in its original currency. Insights warns only about the overdue remainder. Home and budgets include actual converted expenses, never the expected recurring amounts.

On saving an ordinary expense, an exact normalized name match plus category, currency and sharing offers a link confirmation. A blank description offers matching candidates for the user to choose; a nonmatching description does not imply a link. Nothing is linked silently. The confirmation compares a new payment with the remaining balance, warns about partial or excess amounts, and excludes the expense itself during edits. **Link existing** attaches an author-owned expense without copying it. A payment month can be chosen separately from the expense date. Deletion removes actual spending; unlinking preserves the expense but removes its recurring contribution.

Each monthly plan stores an immutable expected amount and currency snapshot. Template changes apply to future monthly plans. For a category or name correction, the owner can also update all current-month linked payments if they own every affected expense and currency/sharing remain unchanged. The selected payments are updated atomically; earlier months stay unchanged. A payment created concurrently after the correction screen loaded can require an author review, which the recurring card flags if its fields differ from the monthly plan. Currency and sharing changes apply only to future plans. For mixed authors, each author can unlink and correct their own expense. Existing legacy single-payment markers are upgraded on demand without copying expenses. Their original expected historical amount was not stored and is therefore reconstructed from the template available during upgrade.

Recurring status listens to all linked expenses for the selected obligation month, without the Activity page limit. Grouping costs O(P + R) for that month’s payments and templates. Matching runs once on Save, never on each keystroke, and does not search the household’s entire history. The first snapshot for a month and legacy upgrades require a connection; existing monthly snapshots and payment streams can use Firestore’s cache. A queued write is not confirmed by the server until reconnection. For simultaneous payments by different phones, the confirmation shows the balance known at that moment; realtime status reconciles all accepted payments, including any resulting overpayment.

Insights includes category warnings at 90% and above, a multi-category trend and shared spending by member. Records without a conversion rate are excluded from converted totals. There are no automatically created expenses or background notifications.

Deploy the matching [`firestore.rules`](firestore.rules) before testing linked payments against a Firebase project. Update the [Local Emulator Suite tests](firebase_rules_test/README.md) when changing recurring behavior.

For rule changes, run `npm --prefix firebase_rules_test ci` once, then `scripts\publish-firestore-rules.cmd --deploy` after each edit. The command runs all local rule tests and only publishes if they pass. It uses the Firebase CLI login stored on this computer and targets `home-budget-app-c038d` explicitly. Running the script without `--deploy` tests without changing Firebase.

When indexes change, review the remote index list before deploying `firebase deploy --only firestore:indexes --project <project-id>`. Firestore may need time to finish building new indexes. Settings includes a private account-deletion request; fulfillment requires an administrator to remove the Firebase Auth account and associated data. Configure that processing and an external deletion-request page before public release.

## Release signing

Create an upload key and keep it outside source control. Copy `android/key.properties.example` to `android/key.properties` and fill in the path and credentials for your key. The release configuration enables Android code and resource shrinking.

```bash
flutter build appbundle --release
```

The Android App Bundle is written to `build/app/outputs/bundle/release/`. Before distribution, verify the application ID, target Android API level, Firebase configuration, signing certificate, privacy disclosures, and account-deletion flow.

## Tutorial and contextual help

The start screen opens the full 14-step tutorial. The question-mark button in Home, Activity, Plan, Recurring, Insights, Settings, account and household screens opens a relevant subset of the same slides. Expense, recurring and budget forms also provide help. Opening help pushes a separate route: closing it or pressing Android Back returns to the same screen with the draft or filter selection preserved. **More help → Full tutorial** replaces the help route, so closing the full tour still returns directly to the original screen.

Slides use fictional example data and illustrative Flutter previews; they do not fetch real household data or store screenshots of private expenses. The previews share the current app theme and scale to the available space. Explanatory text can scroll, and Previous/Next controls and a step counter support navigation. See the [user guide](docs/user-guide.md) for the complete usage reference.
