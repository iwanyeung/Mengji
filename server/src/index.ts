import dotenv from 'dotenv';
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import morgan from 'morgan';
import fs from 'fs';
import { json } from 'express';
import { createDreamsRouter } from './routes/dreams';
import { createAuthRouter } from './routes/auth';
import { createVisualsRouter } from './routes/visuals';
import { createMeRouter } from './routes/me';
import { createInviteRouter } from './routes/invite';
import { env, hasCos, isPublicHttps } from './config/env';
import { initDb } from './db';

dotenv.config();

const app = express();

// HTTP 内测（如 CVM 公网 IP）勿发 HSTS / upgrade-insecure-requests，否则 iOS URLSession 会强制走 HTTPS 导致 TLS 失败
app.use(
  isPublicHttps()
    ? helmet()
    : helmet({
        strictTransportSecurity: false,
        contentSecurityPolicy: {
          useDefaults: true,
          directives: {
            upgradeInsecureRequests: null,
          },
        },
      }),
);
app.use(cors());
app.use(json({ limit: '2mb' }));
app.use(morgan('dev'));

fs.mkdirSync(env.uploadsDir, { recursive: true });
if (!hasCos()) {
  app.use('/uploads', express.static(env.uploadsDir));
}

app.get('/health', (_req, res) => {
  res.json({
    status: 'ok',
    service: 'mengji-server',
    version: '0.3.0',
    aiMock: env.aiMock,
    database: env.mysqlUrl ? 'mysql' : 'sqlite',
    storage: hasCos() ? 'cos' : 'local',
  });
});

app.use('/api/auth', createAuthRouter());
app.use('/api/me', createMeRouter());
app.use('/api/invite', createInviteRouter());
app.use('/api/dreams', createDreamsRouter());
app.use('/api/visuals', createVisualsRouter());

app.use((err: Error, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  console.error(err);
  res.status(500).json({ error: err.message || '服务器错误' });
});

async function main(): Promise<void> {
  await initDb();
  app.listen(env.port, () => {
    console.log(`mengji-server listening on port ${env.port}`);
    console.log(`public base: ${env.publicBaseUrl} (helmet HSTS ${isPublicHttps() ? 'on' : 'off'})`);
    console.log(`storage: ${hasCos() ? 'COS' : env.uploadsDir}`);
    console.log(`AI mock mode: ${env.aiMock}`);
  });
}

main().catch((err) => {
  console.error('Failed to start server', err);
  process.exit(1);
});
