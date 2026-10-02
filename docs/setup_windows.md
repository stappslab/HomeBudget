# Windows setup

1. Install Python 3.13.
2. Create and activate `backend/.venv`.
3. Install `backend/requirements.txt`.
4. Start the API with `uvicorn app.main:app --reload` from `backend`.
5. Kivy desktop testing can be installed from `mobile/requirements.txt`; Android packaging will be configured after the local MVP is stable.

## Android APK

Buildozer is normally run inside WSL2/Linux on Windows. From the project root in WSL:

```bash
cd /mnt/c/Dev/Expense\ App/mobile
sudo apt update
sudo apt install -y build-essential git zip unzip openjdk-17-jdk python3-pip
python3 -m pip install --user buildozer cython
buildozer -f buildozer/buildozer.spec android debug
```

The debug APK is created under the Buildozer `bin` directory. The first build downloads the Android toolchain and can take a while.
