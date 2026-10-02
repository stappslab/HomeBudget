# Android build audit

## Application dependencies

| Dependency | Used by | Android requirement |
| --- | --- | --- |
| `kivy` | `mobile/main.py`, `mobile/components/charts.py` | Buildozer/p4a recipe |
| `python3` | Python runtime | Buildozer/p4a recipe |
| `sqlite3` | `mobile/local_db/local_db.py` | Python standard library / p4a Python build |
| `urllib` | `mobile/services/api.py` | Python standard library |
| `json`, `datetime`, `pathlib`, `uuid`, `dataclasses`, `typing` | Mobile source | Python standard library |

`requests` and `kivymd` are not imported by the mobile code. Kivy 2.3.1 declares Requests as a transitive packaging dependency, so the Android build must handle Kivy's metadata dependencies through a compatible p4a resolver.

## WSL tools required

```bash
sudo apt update
sudo apt install -y \
  build-essential cmake ninja-build autoconf automake libtool libtool-bin pkg-config \
  libssl-dev zlib1g-dev libffi-dev libbz2-dev liblzma-dev \
  libreadline-dev libsqlite3-dev libncurses-dev libgdbm-dev \
  libgdbm-compat-dev libnss3-dev uuid-dev patchelf zip unzip \
  openjdk-17-jdk rsync
```

The active Buildozer environment should use Python 3.12 with working SSL:

```bash
source "$HOME/homebudget-venv312/bin/activate"
python --version
python -c 'import ssl; print(ssl.OPENSSL_VERSION)'
python -m pip show buildozer cython
```

## Clean source sync and stale-cache check

Run this before the next build. It copies the current Windows source into the Linux workspace and verifies that removed packages are absent from the actual build copy.

```bash
rm -rf "$HOME/homebudget-mobile/.venv" "$HOME/homebudget-mobile/venv"

rsync -a --delete \
  --exclude='.buildozer' \
  --exclude='.venv' \
  --exclude='venv' \
  --exclude='__pycache__' \
  "/mnt/c/Dev/Expense App/mobile/" \
  "$HOME/homebudget-mobile/"

cd "$HOME/homebudget-mobile/buildozer"
grep -R -n -E '(^|[^[:alnum:]_])(requests|kivymd)([^[:alnum:]_]|$)' \
  --exclude-dir='.buildozer' \
  --exclude-dir='.venv' \
  --exclude-dir='venv' \
  --exclude-dir='__pycache__' \
  "$HOME/homebudget-mobile" || true

grep '^ requirements' buildozer.spec
```

The final command must print:

```text
 requirements = python3,kivy

The spec pins python-for-android to the Kivy fork's `develop` branch because the older resolver can pass Kivy's Android `charset-normalizer` wheel to host pip, which rejects it as an unsupported platform wheel.
```

The grep command should return no application import/config matches. It may still find the explanatory audit text itself if the audit document is included in the search scope; this does not affect the Android source because the document is outside `mobile/`.

## Rebuild after the audit

```bash
rm -rf .buildozer

test "$(grep '^ requirements' buildozer.spec | tr -d '[:space:]')" = "requirements=python3,kivy"
! grep -R -n -E '(^|[^[:alnum:]_])(requests|kivymd)([^[:alnum:]_]|$)' \
  --include='*.py' --include='*.txt' --include='*.spec' \
  --exclude-dir='__pycache__' \
  --exclude-dir='.buildozer' \
  "$HOME/homebudget-mobile"

buildozer android debug
```

Do not remove `$HOME/.buildozer`; that directory contains the downloaded Android SDK and NDK.

## Expected build outputs

```text
$HOME/homebudget-mobile/buildozer/bin/*.apk
```
