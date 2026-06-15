#!/usr/bin/env bash
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

if [ ! -x /mayhem/test-venv/bin/python ]; then
  echo "missing /mayhem/test-venv — build.sh should have built the oracle venv" >&2
  emit_ctrf "unittest" 0 1 0
  exit 1
fi

read -r passed failed skipped <<< "$(/mayhem/test-venv/bin/python << 'PY'
import unittest
loader = unittest.TestLoader()
suite = loader.discover("tests", pattern="test*.py")
runner = unittest.TextTestRunner(verbosity=0, stream=open("/dev/null", "w"))
result = runner.run(suite)
passed = result.testsRun - len(result.failures) - len(result.errors) - len(result.skipped)
failed = len(result.failures) + len(result.errors)
skipped = len(result.skipped)
print(passed, failed, skipped)
PY
)"

emit_ctrf "unittest" "$passed" "$failed" "$skipped"
