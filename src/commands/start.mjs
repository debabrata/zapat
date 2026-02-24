import { execFileSync } from 'child_process';
import { join } from 'path';

export function registerStartCommand(program) {
  program
    .command('start')
    .description('Start the Zapat pipeline (tmux, cron, dashboard)')
    .option('--seed-state', 'Force re-seed state files with current open issues/PRs')
    .action((opts) => {
      const root = process.env.AUTOMATION_DIR;
      const args = [];
      if (opts.seedState) args.push('--seed-state');

      try {
        execFileSync(join(root, 'bin', 'startup.sh'), args, {
          stdio: 'inherit',
          env: { ...process.env, AUTOMATION_DIR: root },
        });
      } catch (err) {
        process.exit(err.status || 1);
      }
    });
}
