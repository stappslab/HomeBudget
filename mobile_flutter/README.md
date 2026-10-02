# HomeBudget 2.0

Shared household expense tracking for Android. Firebase Authentication identifies
members and Cloud Firestore stores households, budgets and expenses. Firestore's
offline cache handles temporary disconnections. Amounts are stored as integer
minor units; foreign-currency expenses keep their original amount and use a
user-entered conversion rate for totals in the household's main currency.

The app includes category pocket budgets, searchable and editable expenses,
six-month spending insights, and an optional device PIN and biometric lock.
The local-only household, SQLite database and its backup/import flow have been
removed. Device lock settings remain on the phone in encrypted storage.

## Development

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
cp build/app/outputs/flutter-apk/app-debug.apk "/mnt/c/Dev/Expense App/homebudget-v2-debug.apk"
```

## Production Android release

The current application ID remains `com.example.homebudget_flutter` so this APK
updates the version already installed on your phone. The former SQLite household
is no longer opened by the app; cloud households remain in Firestore.
Choose a permanent unique ID before the first public store release; changing it
later creates a separate Android app, so it must be paired with a data migration.
Create a private upload key once, outside source control, then create `android/key.properties` from
`android/key.properties.example` with the real values.

```bash
keytool -genkeypair -v -keystore ~/homebudget-upload.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000
flutter build appbundle --release
flutter build apk --release --split-per-abi
```

The release configuration enables R8 and Android resource shrinking. The split
APK command creates a smaller APK per device architecture; use the `arm64-v8a`
APK for most current Android phones.

Android cloud backup and cleartext network traffic are disabled in the
production manifest. Household data is stored in Firestore; the device PIN
verifier and theme preferences stay on the phone.
