# Reproduction for vitest-dev/vitest#11241

A `--pool=forks` worker orphaned by a main process that dies **without pool
teardown** never exits, and the `onError` guard in `init-forks`
([L55–61](https://github.com/vitest-dev/vitest/blob/2ce29d5fa758046e5453bd92b8ed6c9da9709bb5/packages/vitest/src/runtime/workers/init-forks.ts#L55-L61))
does not fire even when the worker later reports an error into the dead IPC
channel.

## Run

```bash
pnpm install   # or npm install — vitest ^4.1.11
bash repro.sh
```

`repro.sh` starts `vitest run --pool=forks` with a single test that writes its
pid, schedules an **out-of-test uncaught throw at t≈8s**, and sleeps. The script
SIGKILLs the *main* process as soon as the worker announces itself (simulating
the incident's EPIPE death from `vitest run | head -120`, or any crash that
skips pool teardown), then samples the worker every second.

## Observed (macOS 15 / node 24.15.0 / vitest 4.1.11)

```
main=13994 worker=13998 — SIGKILLing main
t=1s   worker alive  rss(KB)/%cpu: 71536 8.8
...
t=8s   worker alive  rss(KB)/%cpu: 71536 0.0
t=9s   worker alive  rss(KB)/%cpu: 66080 2.2   <- uncaught throw reported into dead channel
...
t=15s  worker alive  rss(KB)/%cpu: 66080 0.0
RESULT: worker still alive 15s after its parent died — orphan
```

Two facts, deterministic here:

1. **The worker outlives its parent indefinitely** (it runs to whatever its
   test/event loop holds open — jsdom/react-query timers in the original
   incident hold it forever).
2. **The uncaught error at t≈9s goes through `catchError` →
   `rpc.onUnhandledError` → `process.send` on the dead channel, and the worker
   neither exits nor receives a process `'error'` event** — the guard is
   bypassed; the rejection is simply lost.

Whether the lost rejection then **loops** (re-entering `catchError` as an
`unhandledRejection` → another send → another rejection…) is
timing/platform-dependent — the issue's Linux core dump (~874k iterations,
~3.5 GB) is the case where it does. On this macOS run it settles as a silent
swallow + immortal orphan instead. Either way the guard never fires, because it
hangs off `process.on('error')` only, and this path never raises that event.
