import { NextResponse } from 'next/server'
import { getGitHubActivity } from '@/lib/data'

export const dynamic = 'force-dynamic'

const VALID_SLUG = /^[a-zA-Z0-9_-]+$/

export async function GET(request: Request) {
  try {
    const { searchParams } = new URL(request.url)
    const project = searchParams.get('project') || undefined
    const days = parseInt(searchParams.get('days') ?? '7', 10)
    if (project && !VALID_SLUG.test(project)) {
      return NextResponse.json({ error: 'Invalid project slug' }, { status: 400 })
    }
    const events = getGitHubActivity(isNaN(days) ? 7 : days, project)
    return NextResponse.json({ events })
  } catch {
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}
