// 测试替身：按 argv[1] 模拟 catbus 的各种输出。argv[0] 视为平台。
const [platform, mode, arg] = process.argv.slice(2)
const env = (ok, data, error = null) =>
  JSON.stringify({ ok, platform, endpoint: 'web', resource: 'x', action: 'y', account: 'default', data, page: ok ? { cursor: 'c1', has_more: true } : null, error })
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const readStdin = async () => {
  if (process.stdin.isTTY) return null
  let s = ''
  for await (const c of process.stdin) s += c
  return s
}

switch (mode) {
  case 'ok':
    process.stdout.write(env(true, { argv: process.argv.slice(2), env: { NO_COLOR: process.env.NO_COLOR } }))
    break
  case 'stdin':
    process.stdout.write(env(true, { stdin: await readStdin() }))
    break
  case 'fail': {
    const codes = { AUTH_REQUIRED: 3, RISK_CONTROL: 5, NETWORK: 6, USAGE: 2 }
    process.stdout.write(env(false, null, { code: arg, message: `fake ${arg}`, hint: `catbus ${platform} auth login`, detail: { kind: 'captcha' } }))
    process.exitCode = codes[arg] ?? 1
    break
  }
  case 'sleep': {
    const start = Date.now()
    await sleep(Number(arg))
    process.stdout.write(env(true, { start, end: Date.now() }))
    break
  }
  case 'garbage':
    process.stdout.write('not json at all')
    break
  case 'empty':
    process.exitCode = 1
    break
  case 'noisy':
    process.stdout.write('warning: something\n' + env(true, [1, 2, 3]) + '\n')
    break
  case 'stderr':
    process.stderr.write('[catbus] 二维码已生成\n')
    await sleep(20)
    process.stderr.write('[catbus] 已扫码，请在手机上确认\npartial-no-newline')
    process.stdout.write(env(true, { logged_in: true }))
    break
  case 'ignore-term':
    process.on('SIGTERM', () => {})
    await sleep(60_000)
    break
  default:
    process.stdout.write(env(false, null, { code: 'USAGE', message: `unknown mode ${mode}`, hint: null, detail: null }))
    process.exitCode = 2
}
