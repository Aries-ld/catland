/**
 * 本地工作区：catland 需要长期保存的东西都放在一个文件夹里（默认 ~/Library/Application Support/catland，
 * 可用 CATLAND_DATA_DIR 覆盖）。删掉 App、重新下载安装都不会动它，登录状态、点赞收藏一直都在。
 *
 *   data/catland.db   点赞、收藏、浏览历史、设置
 *   covers/           收藏的封面（平台的封面地址会过期）
 *   accounts/         各平台登录凭证（catbus 的数据目录，CATBUS_HOME 指到这里；只有本人可读）
 *   说明.txt          这个文件夹里都是什么、怎么彻底清除
 *
 * 图片缓存和日志不在这里：缓存在 ~/Library/Caches/app.catland（系统空间紧张时可以清），日志在 ~/Library/Logs/catland。
 */
import { chmodSync, cpSync, existsSync, mkdirSync, readdirSync, renameSync, writeFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'
import type { Logger } from '../log.ts'

export function workspaceDir(): string {
  return process.env.CATLAND_DATA_DIR ?? join(homedir(), 'Library', 'Application Support', 'catland')
}

export const workspace = {
  data: () => join(workspaceDir(), 'data'),
  db: () => join(workspaceDir(), 'data', 'catland.db'),
  covers: () => join(workspaceDir(), 'covers'),
  accounts: () => join(workspaceDir(), 'accounts'),
}

const README = `这是 catland 的本地工作区，所有内容只存在这台 Mac 上，不会上传。

data/catland.db   点赞、收藏、浏览历史和设置
covers/           收藏帖子的封面
accounts/         各平台的登录状态（只有你本人的账户能读）

删除或重新安装 catland 不会动这个文件夹，下次打开时登录状态、点赞收藏都还在。
平台的登录过期后，在 catland 的「连接」页重新登录就行。

想彻底清除 catland 的所有数据：先退出 catland，再删除这个文件夹。
`

/**
 * 启动时准备工作区：建好目录；把旧版放在根目录的数据库挪进 data/；
 * accounts/ 还是空的时，从 ~/.catbus（catbus 命令行的默认位置）复制一份已有的登录状态过来——
 * 只复制不移动，命令行那边照常可用，用户也不用重新登录。返回给 catbus 用的数据目录。
 */
export function prepareWorkspace(logger: Logger, opts: { legacyCatbusHome?: string } = {}): string {
  const log = logger.child({ mod: 'workspace' })
  const root = workspaceDir()
  for (const dir of [root, workspace.data(), workspace.covers(), workspace.accounts()]) mkdirSync(dir, { recursive: true })
  chmodSync(workspace.accounts(), 0o700)

  // 旧版：catland.db（及 -wal / -shm）在根目录
  for (const suffix of ['', '-wal', '-shm']) {
    const from = join(root, `catland.db${suffix}`), to = `${workspace.db()}${suffix}`
    if (existsSync(from) && !existsSync(to)) {
      renameSync(from, to)
      log.info('moved database into data/', { file: `catland.db${suffix}` })
    }
  }

  // 登录状态：accounts/ 里还没有时，从 ~/.catbus 复制
  const legacy = opts.legacyCatbusHome ?? join(homedir(), '.catbus')
  const target = workspace.accounts()
  const hasAuth = existsSync(join(target, 'auth')) && readdirSync(join(target, 'auth')).length > 0
  if (!hasAuth && existsSync(join(legacy, 'auth'))) {
    cpSync(join(legacy, 'auth'), join(target, 'auth'), { recursive: true, preserveTimestamps: true })
    if (existsSync(join(legacy, 'config.toml'))) cpSync(join(legacy, 'config.toml'), join(target, 'config.toml'))
    log.info('copied existing logins into accounts/', { platforms: readdirSync(join(target, 'auth')).length })
  }

  writeFileSync(join(root, '说明.txt'), README)
  return target
}
