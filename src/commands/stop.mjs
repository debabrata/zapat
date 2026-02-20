import { execFileSync } from 'child_process';
import { join } from 'path';

export function registerStopCommand(program) {
  program
    .command('stop')
    .description('Stop the Zapat pipeline (kills sessions, cron, dashboard)')
    .option('-f, --force', 'Skip confirmation prompt')
    .option('--keep-cron', 'Keep crontab entries')
    .option('--keep-worktrees', 'Keep active worktrees')
    .option('-q, --quiet', 'Minimal output')
    .action((opts) => {
      const root = process.env.AUTOMATION_DIR;
      const args = [];
      if (opts.force) args.push('--force');
      if (opts.keepCron) args.push('--keep-cron');
      if (opts.keepWorktrees) args.push('--keep-worktrees');
      if (opts.quiet) args.push('--quiet');

      try {
        execFileSync(join(root, 'bin', 'shutdown.sh'), args, {
          stdio: 'inherit',
          env: { ...process.env, AUTOMATION_DIR: root },
        });
      } catch (err) {
        process.exit(err.status || 1);
      }
    });
}
