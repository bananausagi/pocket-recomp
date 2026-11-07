#!/bin/bash
# Personal-line test gate: full suite on game/ + tests/, compared against
# tools/base.tsv (the failure set recorded for the jp.91 line: 887 tests,
# 100 known failures).  Pass = no NEW failures beyond that set.
set -u
cd "$(dirname "$0")/.." || exit 2
command -v luajit >/dev/null || { echo "luajit not found -- gate cannot run"; exit 4; }
python3 tools/setup_tb.py build/tb_new >/dev/null || exit 3
bash tools/run_tests.sh build/tb_new "$PWD/build/new.tsv"
echo "lines: $(wc -l < build/new.tsv)"
awk -F'\t' '$1!=0{print $2}' tools/base.tsv | sort > build/f_base.txt
awk -F'\t' '$1!=0{print $2}' build/new.tsv | sort > build/f_new.txt
echo "fail new: $(wc -l < build/f_new.txt)  fail base: $(wc -l < build/f_base.txt)"
echo "NEW FAILURES:"
comm -13 build/f_base.txt build/f_new.txt
echo "END"
test -z "$(comm -13 build/f_base.txt build/f_new.txt)"
