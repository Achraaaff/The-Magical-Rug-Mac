#!/bin/bash
set -euo pipefail
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
mkdir -p "$root/build/tests"
"${CXX:-c++}" -std=c++17 -O2 "$root/Tests/model.cpp" -o "$root/build/tests/model"
"$root/build/tests/model"
