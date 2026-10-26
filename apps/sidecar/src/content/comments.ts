/** 评论：只读（一级评论 + 楼中楼），写评论不在 MVP 范围内。 */
import type { CatbusClient } from '../accounts/service.ts'
import type { Comment, Page } from '../catbus/types.ts'

export interface CommentPage {
  comments: Comment[]
  cursor: string | null
  hasMore: boolean
}

const PAGE = 20

export class CommentService {
  private readonly catbus: CatbusClient

  constructor(deps: { catbus: CatbusClient }) {
    this.catbus = deps.catbus
  }

  async list(platform: string, itemUrl: string, cursor?: string | null): Promise<CommentPage> {
    return this.page(await this.catbus.run<Comment[]>([platform, 'comment', 'list', itemUrl, '--limit', String(PAGE), ...cursorArgs(cursor)]))
  }

  async replies(platform: string, itemUrl: string, commentId: string, cursor?: string | null): Promise<CommentPage> {
    return this.page(await this.catbus.run<Comment[]>([platform, 'comment', 'replies', itemUrl, commentId, '--limit', String(PAGE), ...cursorArgs(cursor)]))
  }

  private page(r: { data: Comment[]; page: Page | null }): CommentPage {
    return { comments: r.data, cursor: r.page?.cursor ?? null, hasMore: r.page?.has_more ?? false }
  }
}

function cursorArgs(cursor: string | null | undefined): string[] {
  return cursor ? ['--cursor', cursor] : []
}
