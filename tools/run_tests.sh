#!/bin/bash
# usage: run_tests.sh <tb_dir> <out.tsv> [grep pattern for subset]
# Runs every tests/**/*_test.lua under luajit (8 parallel, 600s each),
# writing "<exit>\t<path>" lines sorted by path.  Same as the jp91 runner.
cd "$1" || exit 2
if [ -n "$3" ]; then
  LIST=$(grep -lE "$3" $(find tests -name '*_test.lua') | sort)
else
  LIST=$(find tests -name '*_test.lua' | sort)
fi
printf "%s\n" $LIST | xargs -P 8 -I{} bash -c 'timeout 600 luajit "{}" >/dev/null 2>&1; printf "%s\t%s\n" $? "{}"' | sort -t$'\t' -k2 > "$2"
echo "total $(wc -l < "$2") fail $(grep -vc '^0	' "$2")"
