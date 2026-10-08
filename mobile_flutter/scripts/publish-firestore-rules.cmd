@echo off
setlocal
cd /d "%~dp0.." || exit /b 1
set "CLI=firebase_rules_test\node_modules\.bin\firebase.cmd"
if not exist "%CLI%" (
  echo Firebase CLI is missing. Run: npm --prefix firebase_rules_test ci
  exit /b 1
)

echo Testing Firestore rules in the local emulator...
call "%CLI%" emulators:exec --only firestore --project homebudget-rules-test "npm --prefix firebase_rules_test test"
if errorlevel 1 (
  echo Firestore emulator tests failed. Rules were not deployed.
  exit /b 1
)

if /i not "%~1"=="--deploy" (
  echo Rules passed local tests. No deployment requested.
  exit /b 0
)

echo Deploying Firestore rules to home-budget-app-c038d...
call "%CLI%" deploy --only firestore:rules --project home-budget-app-c038d --non-interactive
if errorlevel 1 (
  echo Firebase deployment failed. Check CLI login and project access.
  exit /b 1
)
echo Firestore rules deployed to home-budget-app-c038d.
