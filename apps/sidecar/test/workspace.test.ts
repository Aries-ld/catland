import { existsSync, mkdirSync, mkdtempSync, readFileSync, statSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, describe, expect, it } from 'vitest'
import { createMemoryLogger } from '../src/log.ts'
import { prepareWorkspace, workspace } from '../src/store/workspace.ts'

describe('prepareWorkspace', () => {
  const saved = process.env.CATLAND_DATA_DIR
  afterEach(() => { process.env.CATLAND_DATA_DIR = saved })

  it('建好目录、把旧版根目录的数据库挪进 data/、从 ~/.catbus 复制登录状态（只复制不移动）', () => {
    const root = mkdtempSync(join(tmpdir(), 'catland-ws-'))
    const legacy = mkdtempSync(join(tmpdir(), 'catbus-home-'))
    process.env.CATLAND_DATA_DIR = root
    writeFileSync(join(root, 'catland.db'), 'db')
    writeFileSync(join(root, 'catland.db-wal'), 'wal')
    mkdirSync(join(legacy, 'auth', 'xhs', 'web'), { recursive: true })
    writeFileSync(join(legacy, 'auth', 'xhs', 'web', 'default.json'), '{}')

    const home = prepareWorkspace(createMemoryLogger(), { legacyCatbusHome: legacy })
    expect(home).toBe(workspace.accounts())
    expect(readFileSync(workspace.db(), 'utf8')).toBe('db')
    expect(readFileSync(`${workspace.db()}-wal`, 'utf8')).toBe('wal')
    expect(existsSync(join(root, 'catland.db'))).toBe(false)
    expect(existsSync(join(home, 'auth', 'xhs', 'web', 'default.json'))).toBe(true)
    expect(existsSync(join(legacy, 'auth', 'xhs', 'web', 'default.json'))).toBe(true) // 原处保留
    expect(statSync(home).mode & 0o777).toBe(0o700)
    expect(readFileSync(join(root, '说明.txt'), 'utf8')).toContain('登录状态')
  })

  it('accounts/ 里已经有登录状态时不再覆盖', () => {
    const root = mkdtempSync(join(tmpdir(), 'catland-ws-'))
    const legacy = mkdtempSync(join(tmpdir(), 'catbus-home-'))
    process.env.CATLAND_DATA_DIR = root
    mkdirSync(join(root, 'accounts', 'auth', 'douyin'), { recursive: true })
    writeFileSync(join(root, 'accounts', 'auth', 'douyin', 'mine.json'), 'new')
    mkdirSync(join(legacy, 'auth', 'xhs'), { recursive: true })
    prepareWorkspace(createMemoryLogger(), { legacyCatbusHome: legacy })
    expect(existsSync(join(root, 'accounts', 'auth', 'xhs'))).toBe(false)
    expect(readFileSync(join(root, 'accounts', 'auth', 'douyin', 'mine.json'), 'utf8')).toBe('new')
  })
})
