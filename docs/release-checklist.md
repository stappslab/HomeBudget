# HomeBudget release checklist

## 1) Functional validation
- Backend API test suite passes.
- Core household, member, category, budget, and expense flows are verified.
- Kivy app loads without startup errors.

## 2) UI/UX final pass
- Use the approved dark premium style.
- Confirm readability, spacing, contrast, and action buttons are consistent.
- Verify all major screens keep the same look and feel.

## 3) Packaging readiness
- Packaging is done in Linux/WSL2, not native Windows.
- Buildozer requires a Linux environment for Android APK generation.

## 4) Android build steps (WSL2/Linux)
```bash
sudo apt update
sudo apt install -y python3-venv build-essential git zip unzip openjdk-17-jdk
python3 -m venv .venv
. .venv/bin/activate
pip install --upgrade pip
pip install cython buildozer
cd /workspace/Expense\ App/mobile
buildozer android debug
```

## 5) Release approval
- Confirm APK installs on device.
- Check startup screen, dashboard, add expense flow, stats screen, and settings.
- Validate a real household workflow end-to-end.

## 6) Optional next improvements
- cloud sync
- real login/auth flow
- import/export
- recurring expenses
- user onboarding polish
