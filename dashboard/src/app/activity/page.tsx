'use client'

import { Suspense, useEffect } from 'react'
import { ActivityTable } from '@/components/ActivityTable'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { usePolling } from '@/hooks/usePolling'
import { useProject } from '@/hooks/useProject'
import { pipelineConfig } from '../../../pipeline.config'
import type { MetricEntry, GitHubEvent } from '@/lib/types'

const EVENT_LABELS: Record<string, { label: string; color: string }> = {
  pr_created:      { label: 'PR Created',   color: 'bg-blue-100 text-blue-700 dark:bg-blue-900/40 dark:text-blue-300' },
  pr_merged:       { label: 'PR Merged',    color: 'bg-purple-100 text-purple-700 dark:bg-purple-900/40 dark:text-purple-300' },
  pr_reviewed:     { label: 'PR Reviewed',  color: 'bg-amber-100 text-amber-700 dark:bg-amber-900/40 dark:text-amber-300' },
  pr_approved:     { label: 'PR Approved',  color: 'bg-green-100 text-green-700 dark:bg-green-900/40 dark:text-green-300' },
  issue_triaged:   { label: 'Triaged',      color: 'bg-zinc-100 text-zinc-700 dark:bg-zinc-700 dark:text-zinc-300' },
  issue_researched:{ label: 'Researched',   color: 'bg-indigo-100 text-indigo-700 dark:bg-indigo-900/40 dark:text-indigo-300' },
  issue_closed:    { label: 'Issue Closed', color: 'bg-green-100 text-green-700 dark:bg-green-900/40 dark:text-green-300' },
}

function timeAgo(ts: string): string {
  const diff = Date.now() - new Date(ts).getTime()
  const mins = Math.floor(diff / 60000)
  if (mins < 60) return `${mins}m ago`
  const hours = Math.floor(mins / 60)
  if (hours < 24) return `${hours}h ago`
  return `${Math.floor(hours / 24)}d ago`
}

function EventFeed({ events, loading }: { events: GitHubEvent[]; loading: boolean }) {
  if (loading) {
    return (
      <div className="space-y-3">
        {[...Array(5)].map((_, i) => (
          <div key={i} className="h-12 animate-pulse rounded-lg bg-zinc-200 dark:bg-zinc-700" />
        ))}
      </div>
    )
  }
  if (events.length === 0) {
    return (
      <p className="py-8 text-center text-sm text-zinc-400">
        No GitHub activity found in the last 7 days.
      </p>
    )
  }
  return (
    <ul className="divide-y divide-zinc-200 dark:divide-zinc-700">
      {events.map((event) => {
        const meta = EVENT_LABELS[event.type] ?? { label: event.type, color: 'bg-zinc-100 text-zinc-600' }
        const repoShort = event.repo.split('/').pop()
        const isPr = event.type.startsWith('pr_')
        const itemPath = isPr ? 'pull' : 'issues'
        return (
          <li key={event.id} className="flex items-start gap-3 py-3">
            <span className={`mt-0.5 shrink-0 rounded px-1.5 py-0.5 text-xs font-medium ${meta.color}`}>
              {meta.label}
            </span>
            <div className="min-w-0 flex-1">
              <a
                href={event.url}
                target="_blank"
                rel="noopener noreferrer"
                className="block truncate text-sm font-medium text-zinc-900 hover:underline dark:text-white"
              >
                {event.title}
              </a>
              {event.summary && (
                <p className="mt-0.5 truncate text-xs text-zinc-500 dark:text-zinc-400">
                  {event.summary}
                </p>
              )}
              <div className="mt-0.5 flex items-center gap-2 text-xs text-zinc-400">
                <a
                  href={`https://github.com/${event.repo}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="hover:underline"
                >
                  {repoShort}
                </a>
                <span>·</span>
                <a
                  href={`https://github.com/${event.repo}/${itemPath}/${event.number}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="hover:underline"
                >
                  #{event.number}
                </a>
                <span>·</span>
                <span>{timeAgo(event.timestamp)}</span>
              </div>
            </div>
          </li>
        )
      })}
    </ul>
  )
}

function ActivityContent() {
  const { project, projectName } = useProject()
  const projectParam = project ? `&project=${encodeURIComponent(project)}` : ''

  useEffect(() => {
    document.title = project ? `Activity - ${projectName}` : 'Activity - Zapat'
  }, [project, projectName])

  const { data: activityData, isLoading: activityLoading } = usePolling<{ events: GitHubEvent[] }>({
    url: `/api/activity?days=7${projectParam}`,
    interval: pipelineConfig.refreshInterval,
  })

  const { data, isLoading } = usePolling<{ metrics: MetricEntry[] }>({
    url: `/api/metrics?days=7${projectParam}`,
    interval: pipelineConfig.refreshInterval,
  })

  const events = activityData?.events || []
  const metrics = data?.metrics || []
  const sorted = [...metrics].reverse().slice(0, 50)

  return (
    <div className="space-y-6 py-8">
      <div>
        <h1 className="text-2xl font-bold text-zinc-900 dark:text-white">
          Activity
        </h1>
        <p className="mt-1 text-sm text-zinc-500 dark:text-zinc-400">
          What Zapat has done in the last 7 days
        </p>
      </div>

      <Card className="border-0 bg-zinc-50 shadow-none dark:bg-zinc-800/50">
        <CardHeader>
          <CardTitle className="text-base">GitHub Activity</CardTitle>
        </CardHeader>
        <CardContent className="px-6 pb-6">
          <EventFeed events={events} loading={activityLoading} />
        </CardContent>
      </Card>

      <Card className="border-0 bg-zinc-50 shadow-none dark:bg-zinc-800/50">
        <CardHeader>
          <CardTitle className="text-base">Pipeline Jobs</CardTitle>
        </CardHeader>
        <CardContent className="p-6">
          <ActivityTable metrics={sorted} loading={isLoading} />
        </CardContent>
      </Card>
    </div>
  )
}

export default function ActivityPage() {
  return (
    <Suspense>
      <ActivityContent />
    </Suspense>
  )
}
