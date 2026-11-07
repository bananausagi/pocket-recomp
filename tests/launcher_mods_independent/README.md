# Independent MOD service integration checks

Run from the repository root with LÖVE 11.x and Python 3:

```sh
python3 tests/launcher_mods_independent/make_fixtures.py
JP_SOURCE="$PWD" love tests/launcher_mods_independent
```

Optional: set `JP_ORIGINAL_MODS` to a folder containing the nine original-author ZIPs listed in `main.lua`. This verifies their unchanged manifests, compressed contents, and both slash styles. Those ZIPs are not downloaded by this test.

The harness uses the separate `gen1recomp-jp-independent-mods-qa` LÖVE identity and clears only that identity's test MODs/options. It does not need ROM data or the game launcher. Generated `fixtures/` ZIPs contain synthetic test strings and should be omitted from release archives.

Coverage: valid install and duplicate rejection; malformed manifests and missing entrypoints; traversal, drive paths, symlinks, aliases and case collisions; safe `./` and Windows separator normalization; preservation of private local imports and settings; injected activation failure rollback; setting schemas, translations and profiles; uninstall; all six bundled MOD archives. The optional original-author set adds nine checks.
