# Firestore rules workflow

When `firestore.rules` or its tests change, run `scripts/publish-firestore-rules.cmd --deploy` before reporting the change complete. The script runs the local Firestore emulator tests and deploys rules to the fixed Firebase project only if they pass. With no argument it only tests. If Firebase CLI authentication or connectivity is unavailable, report clearly that the local rules changed but the remote rules were not deployed. Never bypass failing tests by invoking `firebase deploy` directly.

After a verified debug APK build, copy it to `C:\Dev\Expense App\homebudget-v2-debug.apk`.
