# Delivered jp.26 to jp.27 managed MOD upgrade

The fixture uses actual SHA-pinned delivered APKs: full jp.26 -> jp.27 behavior,
plus pristine/modified checks for the retained jp.25 migration. It checks edited,
added, deleted, disabled and duplicate installations; all saved options; exact
backups; failed installation and settings-write rollback; and idempotent retry.
All six companion archives must remain byte-identical.

```sh
python3 tests/jp27_mod_upgrade_love/run.py \
  --jp26 /path/to/gen1recomp-jp-0.2.66-jp.26-android.apk \
  --jp25 /path/to/gen1recomp-jp-0.2.66-jp.25-android.apk \
  --output /path/to/evidence --love /path/to/love-headless
```

Each run uses temporary isolated identities and no ROM or personal save data.
Run only after the reviewed final renderer ZIP has been generated.
