# Delivered jp.24 to jp.25 managed MOD upgrade

This fixture extracts the actual SHA-pinned delivered APKs. It verifies the full
jp.24 Dramaless 2.0.4+jp.18 upgrade to 2.0.5+jp.18, plus pristine/modified-copy
behavior through the retained jp.23 migration.

```sh
python3 tests/jp25_mod_upgrade_love/run.py \
  --jp24 /path/to/gen1recomp-jp-0.2.66-jp.24-android.apk \
  --jp23 /path/to/gen1recomp-jp-0.2.66-jp.23-android.apk \
  --output /path/to/evidence --love /path/to/love-headless
```

Pristine and disabled managed copies upgrade, retaining an exact backup. Edited,
added-file, manually installed, missing, incomplete and duplicate installations
remain untouched. All six companion ZIPs and installed files remain identical.
Whole saved option tables are compared, including per-game/per-profile choices,
new follower/repel opt-ins and opt-outs, blur boundaries and retirement markers.
Partial settings writes and failed installation roll back files, persisted
witnesses and cached options; retry succeeds and a second launch is idempotent.

Each run uses isolated temporary LOVE identities. It contains no ROM or personal
save data and does not establish Android device performance or playthroughs.
