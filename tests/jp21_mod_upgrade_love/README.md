# jp.21 MOD upgrade regression

Uses the exact signed, delivered jp.18, jp.19, and jp.20 APKs as archive inputs;
the runner checks their SHA-256 before extracting `assets/game.love`. No ROM or
personal save is required. Run after regenerating the final jp.21 MOD catalog.

```sh
python3 tests/jp21_mod_upgrade_love/run.py \
  --jp18 /absolute/path/gen1recomp-jp-0.2.66-jp.18-android.apk \
  --jp19 /absolute/path/gen1recomp-jp-0.2.66-jp.19-android.apk \
  --jp20 /absolute/path/gen1recomp-jp-0.2.66-jp.20-android.apk \
  --output /absolute/path/verification/jp21/migration \
  --love /absolute/path/love-headless
```

The retained jp.20 fixture first checks the jp.18/jp.19 renderer retirement,
manual files, missing fallback repair, profiles, and options-save rollback.
The new fixture then checks that pristine jp.20 Dramaless .14 upgrades to .15,
its backup matches the delivered .14 bytes, and the other six archives are
unchanged. All settings and profile choices remain unchanged except the managed
version marker. Modified, added, manual, deleted, and duplicate copies are
preserved. Installation and partial settings-write failures remain retryable;
options witnesses and every installed MOD byte are restored.

`real.json` records both test groups, input APK hashes, and the exact candidate
runtime/catalog/archive/fixture hashes used. These are filesystem migration
tests in real LÖVE; they do not assert Android runtime or frame-rate behavior.
