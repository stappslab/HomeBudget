# Firestore rule tests

These tests use the local Firestore emulator and do not contact the production Firebase project.

Install the test dependencies with `npm --prefix firebase_rules_test install`. Start the emulator with `firebase emulators:start --only firestore --project homebudget-rules-test` from `mobile_flutter`, then run `npm --prefix firebase_rules_test test` in a second terminal. Java 21 is needed by recent Firebase CLI releases; the tests here also ran with Firebase CLI 14 and Java 17.

The CLI reads `../firebase.json` and `../firestore.rules`. Run the tests again after every rule change and publish the verified rules separately to the intended Firebase project.
