# Delivered jp.23 to jp.24 managed MOD upgrade

The fixture extracts the actual, SHA-pinned jp.23 APK and compares its installed
Dramaless 2.0.4+jp.17 files with the current bundled .18 ZIP. It does not construct
an approximate old renderer. The jp.18/jp.19 retirement fixture also runs against
its original delivered APKs.

```sh
python3 tests/jp24_mod_upgrade_love/run.py \
  --jp18 /path/to/gen1recomp-jp-0.2.66-jp.18-android.apk \
  --jp19 /path/to/gen1recomp-jp-0.2.66-jp.19-android.apk \
  --jp23 /path/to/gen1recomp-jp-0.2.66-jp.23-android.apk \
  --output /path/to/evidence --love /path/to/love-headless
```

Pristine and disabled managed copies upgrade with an exact old-file backup.
Edited, manually installed, missing, incomplete and duplicate copies remain
untouched. Saved global/game/profile settings, retired-renderer markers and the
six companion MOD archives are preserved. All six shared field blur levels
(0–5), each old battle-only blur value, and jp.23 convenience/analog/color
preferences are checked independently. The new independent move-reminder opt-in
is also retained unchanged through upgrades and rollback. Simulated partial settings-save and
installation failures roll back the MOD bytes, settings witnesses and cache;
retry succeeds and does not repeat on the next launch.

The runner uses isolated temporary LOVE identities and contains no ROM or
personal save data. Passing this fixture verifies installation behavior, not
Android device performance or game playthroughs.
