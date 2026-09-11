#!/bin/bash
# Repro for vitest-dev/vitest#11241 — forks worker orphaned by a main process
# that dies without pool teardown.
set -u
rm -f worker.pid

# Invoke node directly so $! is the real vitest main process (an npx/npm
# wrapper pid would make the SIGKILL below miss it).
node ./node_modules/vitest/vitest.mjs run --pool=forks repro.test.js >/dev/null 2>&1 &
MAIN=$!

for i in $(seq 1 120); do [ -f worker.pid ] && break; sleep 0.5; done
if [ ! -f worker.pid ]; then echo "worker never started"; exit 1; fi
WORKER=$(cat worker.pid)
echo "main=$MAIN worker=$WORKER — SIGKILLing main (simulates EPIPE death / crash without pool teardown)"
kill -9 "$MAIN"

# The test throws an uncaught error at t≈8s. Watch the worker until t=15s:
#  - worker exits            -> the process 'error' path (onError guard) won the race
#  - worker alive, RSS flat  -> orphan lingers (no teardown ever happens)
#  - worker alive, RSS grows -> the catchError re-entry loop (the OOM path)
for i in $(seq 1 15); do
  if kill -0 "$WORKER" 2>/dev/null; then
    STAT=$(ps -o rss=,%cpu= -p "$WORKER" | tr -s ' ')
    echo "t=${i}s  worker alive  rss(KB)/%cpu:$STAT"
  else
    echo "t=${i}s  worker exited"
    exit 0
  fi
  sleep 1
done
echo "RESULT: worker still alive 15s after its parent died — orphan. Cleaning up."
kill -9 "$WORKER"
