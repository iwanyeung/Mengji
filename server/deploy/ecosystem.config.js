/** PM2 进程配置 — 在 server 目录下执行: pm2 start deploy/ecosystem.config.js */
module.exports = {
  apps: [
    {
      name: 'mengji-api',
      script: 'dist/index.js',
      cwd: __dirname + '/..',
      instances: 1,
      exec_mode: 'fork',
      env: {
        NODE_ENV: 'production',
      },
      max_memory_restart: '512M',
      error_file: '/var/log/mengji/error.log',
      out_file: '/var/log/mengji/out.log',
      merge_logs: true,
      time: true,
    },
  ],
};
