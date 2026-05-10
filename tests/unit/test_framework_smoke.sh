#!/usr/bin/env bash
# Sanity test on the assertion library itself.
source "$(dirname "${BASH_SOURCE[0]}")/../framework.sh"

assert_eq "abc" "abc" "string equality"
assert_neq "abc" "xyz" "string inequality"
assert_contains "the quick brown fox" "quick" "substring"
assert_not_contains "the quick brown fox" "lazy"
assert_match "version 4.8.0" "^version [0-9]+"
assert_zero 0 "exit zero"
assert_nonzero 7 "exit nonzero"
assert_dir_exists "$(dirname "${BASH_SOURCE[0]}")/.."
