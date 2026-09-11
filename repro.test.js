import { writeFileSync } from 'node:fs'
import { test } from 'vitest'

test('worker outlives its parent, then an out-of-test error triggers the report path', async () => {
  writeFileSync('worker.pid', String(process.pid))
  // Out-of-test uncaught exception ~8s in. By then repro.sh has SIGKILLed the
  // main process, so catchError reports into a dead IPC channel.
  setTimeout(() => { throw new Error('uncaught after main death') }, 8000)
  // Keep the event loop and the test alive well past the throw.
  await new Promise(resolve => setTimeout(resolve, 30000))
}, 60000)
