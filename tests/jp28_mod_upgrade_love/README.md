# Delivered jp.27 to jp.28 managed MOD upgrade

The fixture uses actual SHA-pinned delivered APKs: full jp.27 -> jp.28 behavior,
plus pristine/modified checks for the retained jp.26 migration. It checks edited,
added, deleted, disabled and duplicate installations; all saved options; exact
backups; failed installation and settings-write rollback; and idempotent retry.
All six companion archives must remain byte-identical.

```sh
python3 tests/jp28_mod_upgrade_love/run.py \
  --jp27 /path/to/gen1recomp-jp-0.2.66-jp.27-android.apk \
  --jp26 /path/to/gen1recomp-jp-0.2.66-jp.26-android.apk \
  --output /path/to/evidence --love /path/to/love-headless
```

Each run uses temporary isolated identities and no ROM or personal save data.
Run only after the reviewed final renderer ZIP has been generated.
