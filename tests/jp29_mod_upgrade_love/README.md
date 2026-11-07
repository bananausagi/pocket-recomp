# Delivered jp.28 to jp.29 managed MOD upgrade

The fixture uses the actual SHA-pinned delivered jp.28 APK for full jp.28 -> jp.29 behavior. It checks edited,
added, deleted, disabled and duplicate installations; all saved options; exact
backups; failed installation and settings-write rollback; and idempotent retry.
All six companion archives must remain byte-identical.

```sh
python3 tests/jp29_mod_upgrade_love/run.py \
  --jp28 /path/to/gen1recomp-jp-0.2.66-jp.28-android.apk \
  --output /path/to/evidence --love /path/to/love-headless
```

Each run uses temporary isolated identities and no ROM or personal save data.
Run only after the reviewed final renderer ZIP has been generated.
