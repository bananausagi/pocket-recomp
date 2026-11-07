# Delivered jp.21 to jp.22 managed MOD upgrade

The fixture extracts the actual, SHA-pinned jp.21 APK and compares its installed
Dramaless 2.0.4+jp.15 files with the current bundled .16 ZIP. It does not construct
an approximate old renderer. The jp.18/jp.19 retirement fixture also runs against
its original delivered APKs.

```sh
python3 tests/jp22_mod_upgrade_love/run.py \
  --jp18 /path/to/gen1recomp-jp-0.2.66-jp.18-android.apk \
  --jp19 /path/to/gen1recomp-jp-0.2.66-jp.19-android.apk \
  --jp21 /path/to/gen1recomp-jp-0.2.66-jp.21-android.apk \
  --output /path/to/evidence --love /path/to/love-headless
```

Pristine and disabled managed copies upgrade with an exact old-file backup.
Edited, manually installed, missing, incomplete and duplicate copies remain
untouched. Saved global/game/profile settings, retired-renderer markers and the
six companion MOD archives are preserved. Simulated partial settings-save and
installation failures roll back the MOD bytes, settings witnesses and cache;
retry succeeds and does not repeat on the next launch.

The runner uses isolated temporary LOVE identities and contains no ROM or
personal save data. Passing this fixture verifies installation behavior, not
Android device performance or game playthroughs.
