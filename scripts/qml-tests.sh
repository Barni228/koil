#!/usr/bin/env bash
# Runs the QML tests (tests/) as CI does: some fail now and then for
# timing alone (on a busy machine, or a slow CI runner), so a test that
# fails is run again, alone, up to twice, and fails the run only if it
# fails every time. With windows, unless QT_QPA_PLATFORM=offscreen is set.
# Arguments go to qmltestrunner, like test functions to run only those:
#   scripts/qml-tests.sh
#   QT_QPA_PLATFORM=offscreen scripts/qml-tests.sh Vim::test_wrapRows
# (macOS' bash is 3.2: no mapfile, and no set -u, which takes an empty
# array for an unset one.)
set -o pipefail

cd "$(dirname "$0")/.." || exit 1
tries=3
log="$(mktemp)"
trap 'rm -f "$log"' EXIT

# Lines as GitHub shows them on the run's page, in CI.
annotate() {
    if [ "$GITHUB_ACTIONS" = true ]; then
        echo "::$1 title=$2::$3"
    fi
}

run=("$@")
flaky=""
for ((try = 1; try <= tries; try++)); do
    if ((try > 1)); then
        echo
        echo "Try $try of $tries: ${run[*]:-all the tests}"
    fi
    qmltestrunner -input tests "${run[@]}" 2>&1 | tee "$log"
    if [ "${PIPESTATUS[0]}" = 0 ]; then
        for name in $flaky; do
            echo "$name failed, then passed when run again."
            annotate warning "Flaky test" "$name failed, then passed when run again."
        done
        exit 0
    fi
    # Like Vim::test_wrapRows, once each (a data-driven one fails a row at
    # a time). The \r is Windows'.
    failed="$(sed -n 's/^FAIL!  : qmltestrunner::\([^(]*\)(.*/\1/p' "$log" | tr -d '\r' | sort -u)"
    flaky="$(printf '%s\n' $flaky $failed | sort -u)"
    # A crash, or a failed initTestCase, keeps the tests after it from
    # running: all of them again, then.
    if ! grep -q '^Totals:' "$log" || [ -z "$failed" ] || echo "$failed" | grep -qE '::(init|cleanup)TestCase$'; then
        run=("$@")
    else
        run=($failed)
    fi
done

for name in ${failed:-qmltestrunner}; do
    echo "$name failed $tries times."
    annotate error "Test failed" "$name failed $tries times."
done
exit 1
