/** catland 接入的平台目录：名称、登录方式、内嵌登录页与判定登录完成所需的 cookie（来自 catbus docs/guide/login.md）。 */

export type LoginMethod = 'qrcode' | 'cookie'

export interface PlatformSpec {
  id: string
  name: string
  /** 面板里的主登录方式：能扫码就扫码，否则内嵌官方登录页取 cookie。 */
  primaryLogin: LoginMethod
  /** catbus 默认方式不是 cookie 时，cookie 登录要显式加 --method cookie。 */
  catbusDefault: LoginMethod
  /** 内嵌 WebView 打开的官方登录页。 */
  loginUrl: string
  /** 这些 cookie 都出现后视为网页登录完成（任一组满足即可）。空数组表示 catbus 只做在线校验，客户端需提供「我已登录」手动提交。 */
  requiredCookies: string[][]
  /** 板块归属：MVP 只开放 content。 */
  sections: Array<'content' | 'commerce'>
  /** 暂不开放的原因（有值即置灰：不能连接、不进刷刷流）。体验不好的平台先置灰，解决后再开放。 */
  unavailable?: string
}

export const PLATFORMS: readonly PlatformSpec[] = [
  { id: 'xhs', name: '小红书', primaryLogin: 'qrcode', catbusDefault: 'qrcode', loginUrl: 'https://www.xiaohongshu.com', requiredCookies: [['a1', 'web_session']], sections: ['content'] },
  // 抖音：catbus 模拟的网页扫码协议近期常被风控拦下（error_code 2046「请前往 App 完成验证」，换电脑也会复现），
  // 改为在内嵌的抖音官方网页上扫码（真实网页环境，更少被拦），登录后自动取登录态；只读能力不受影响。
  { id: 'douyin', name: '抖音', primaryLogin: 'cookie', catbusDefault: 'qrcode', loginUrl: 'https://www.douyin.com', requiredCookies: [['sessionid']], sections: ['content'] },
  { id: 'bilibili', name: 'B 站', primaryLogin: 'qrcode', catbusDefault: 'qrcode', loginUrl: 'https://www.bilibili.com', requiredCookies: [['SESSDATA', 'bili_jct']], sections: ['content'] },
  { id: 'kuaishou', name: '快手', primaryLogin: 'qrcode', catbusDefault: 'qrcode', loginUrl: 'https://www.kuaishou.com', requiredCookies: [], sections: ['content'] },
  // X、TikTok：大量用户用 Google / Apple 账号登录，而这两家禁止在 App 内嵌窗口里登录；TikTok 还需要特定网络环境。
  // 体验不好先置灰，等「浏览器助手」能把浏览器里的登录态自动交给 catland 后再开放。
  { id: 'x', name: 'X', primaryLogin: 'cookie', catbusDefault: 'cookie', loginUrl: 'https://x.com/i/flow/login', requiredCookies: [['auth_token', 'ct0']], sections: ['content'], unavailable: '暂未开放：Google / Apple 账号无法在 App 内登录，正在做浏览器助手' },
  { id: 'tiktok', name: 'TikTok', primaryLogin: 'cookie', catbusDefault: 'cookie', loginUrl: 'https://www.tiktok.com/login', requiredCookies: [['sessionid'], ['sid_tt'], ['multi_sids']], sections: ['content'], unavailable: '暂未开放：需要特定网络环境，且 Google / Apple 账号无法在 App 内登录' },
  { id: 'weibo', name: '微博', primaryLogin: 'cookie', catbusDefault: 'cookie', loginUrl: 'https://weibo.com/login.php', requiredCookies: [['SUB']], sections: ['content'] },
  { id: 'jd', name: '京东', primaryLogin: 'qrcode', catbusDefault: 'qrcode', loginUrl: 'https://passport.jd.com/new/login.aspx', requiredCookies: [['thor', 'pin'], ['pt_key', 'pin']], sections: ['commerce'] },
  { id: 'taobao', name: '淘宝', primaryLogin: 'cookie', catbusDefault: 'cookie', loginUrl: 'https://login.taobao.com', requiredCookies: [['unb', '_m_h5_tk', 'cookie2']], sections: ['commerce'] },
  { id: 'xianyu', name: '闲鱼', primaryLogin: 'qrcode', catbusDefault: 'qrcode', loginUrl: 'https://www.goofish.com', requiredCookies: [['unb', '_m_h5_tk', 'cookie2']], sections: ['commerce'] },
]

const BY_ID = new Map(PLATFORMS.map((p) => [p.id, p]))

export function getPlatform(id: string): PlatformSpec | undefined {
  return BY_ID.get(id)
}

/** 与 catbus 的账号名规则一致；同时防止以 `-` 开头被当成选项。 */
export const ACCOUNT_NAME_RE = /^[a-z0-9][a-z0-9_-]{0,31}$/
