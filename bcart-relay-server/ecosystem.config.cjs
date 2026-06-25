// PM2 設定。XServer VPS 上で `pm2 start ecosystem.config.cjs` で常駐起動する。
module.exports = {
  apps: [
    {
      name: 'bcart-relay',
      script: 'src/server.js',
      instances: 1,
      autorestart: true,
      max_restarts: 10,
      watch: false,
      env: {
        NODE_ENV: 'production',
      },
    },
  ],
};
