import dotenv from 'dotenv';
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import morgan from 'morgan';
import { json } from 'express';
import { createDreamsRouter } from './routes/dreams';
import { createAuthRouter } from './routes/auth';
import { createVisualsRouter } from './routes/visuals';

dotenv.config();

const app = express();

app.use(helmet());
app.use(cors());
app.use(json());
app.use(morgan('dev'));

app.get('/health', (_req, res) => {
  res.json({ status: 'ok', service: 'mengji-server', version: '0.1.0' });
});

app.use('/api/auth', createAuthRouter());
app.use('/api/dreams', createDreamsRouter());
app.use('/api/visuals', createVisualsRouter());

const PORT = process.env.PORT || 3000;

app.listen(PORT, () => {
  console.log(`mengji-server listening on port ${PORT}`);
});

