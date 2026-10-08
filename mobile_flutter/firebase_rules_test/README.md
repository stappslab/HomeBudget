# Firestore rule tests

These tests use the local Firestore emulator and do not contact the production Firebase project.

From `mobile_flutter`, install the test dependencies with `npm --prefix firebase_rules_test ci`, then run `scripts\publish-firestore-rules.cmd` to start the emulator and execute the tests. The emulator uses port 8081 so it can run beside another local Firestore instance. Java 21 is needed by recent Firebase CLI releases; this project pins Firebase CLI 14 and has been tested with Java 17.

The CLI reads `firebase.json` and `firestore.rules`. To publish only after all tests pass, run `scripts\publish-firestore-rules.cmd --deploy`. It targets `home-budget-app-c038d` explicitly and requires Firebase CLI login with access to that project. Never put credentials in the repository.

## Recurring payment coverage

The suite checks multiple payments by different authors, partial and excess payment records, monthly expectation immutability, category/currency/sharing validation, author-only edits and deletion, unlinking without deleting the monthly plan, atomic owner corrections, historical snapshot protection, rejection of premature future snapshots, legacy upgrades without copied expenses, and compatibility with atomic single-payment legacy records. Calendar-dependent fixtures use the current UTC month.
