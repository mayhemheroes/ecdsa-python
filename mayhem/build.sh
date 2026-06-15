#!/usr/bin/env bash
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -g}"
: "${CC:=clang}" ; : "${CXX:=clang++}"
: "${MAYHEM_JOBS:=$(nproc)}"
export CC CXX MAYHEM_JOBS

cd "$SRC"

# Test oracle: clean venv (no sanitizers). starkbank-ecdsa is pure-python with
# no declared extras, so just install it editable; its unittest suite is the oracle.
python3 -m venv /mayhem/test-venv
/mayhem/test-venv/bin/pip install --upgrade pip setuptools wheel
(
  export CC=clang CXX=clang++
  unset CFLAGS CXXFLAGS LDFLAGS
  /mayhem/test-venv/bin/pip install -e .
)

# Fuzz build: separate venv with atheris + PyInstaller ELF.
python3 -m venv /mayhem/fuzz-venv
/mayhem/fuzz-venv/bin/pip install --upgrade pip setuptools wheel
export CFLAGS="$SANITIZER_FLAGS" CXXFLAGS="$SANITIZER_FLAGS" LDFLAGS="$SANITIZER_FLAGS"
/mayhem/fuzz-venv/bin/pip install atheris pyinstaller
/mayhem/fuzz-venv/bin/pip install -e .

$CC -shared -fPIC -o /mayhem/asan_defaults.so "$SRC/mayhem/asan_defaults.c"

/mayhem/fuzz-venv/bin/pyinstaller \
  --distpath /tmp/pyinst-out \
  --workpath /tmp/pyinst-work \
  --specpath /tmp/pyinst-spec \
  --onefile \
  --name fuzz_private_key \
  --paths "$SRC/mayhem" \
  --collect-all ellipticcurve \
  --hidden-import fuzz_helpers \
  --hidden-import binascii \
  --hidden-import base64 \
  --hidden-import hashlib \
  --hidden-import hmac \
  --hidden-import secrets \
  --hidden-import random \
  --hidden-import re \
  --hidden-import datetime \
  --hidden-import sys \
  --hidden-import os \
  --add-binary /mayhem/asan_defaults.so:. \
  "$SRC/mayhem/fuzz_private_key.py"

install -m 0755 /tmp/pyinst-out/fuzz_private_key /mayhem/fuzz_private_key
