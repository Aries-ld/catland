/** 真机冒烟：账号面板数据 + 登录态体检 + 扫码登录拿到二维码后立即取消（不改动任何账号）。 */
import { AccountService } from '../src/accounts/service.ts'
import { CatbusRunner } from '../src/catbus/runner.ts'
import { createFileLogger } from '../src/log.ts'

const logger = createFileLogger()
const svc = new AccountService({ catbus: new CatbusRunner({ logger }), logger })

const platforms = await svc.refresh()
for (const p of platforms) console.log(`${p.connected ? '●' : '○'} ${p.name.padEnd(6)} ${p.primaryLogin.padEnd(6)} ${p.current?.user?.name ?? ''}`)

for (const p of platforms.filter((x) => x.connected)) console.log('health', p.id, await svc.checkHealth(p.id))

const qrPlatform = process.argv[2] ?? 'douyin'
const t0 = performance.now()
await svc
  .loginQrcode(qrPlatform, {
    onEvent: (e) => {
      if (e.type === 'qrcode') {
        console.log(`qrcode received after ${Math.round(performance.now() - t0)}ms, png bytes=${Buffer.from(e.png, 'base64').length}`)
        svc.cancelLogin(qrPlatform)
      } else console.log('progress:', e.message)
    },
  })
  .then(() => console.log('unexpected: login completed'))
  .catch((e) => console.log('login ended:', e.code))
