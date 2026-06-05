require('dotenv').config();
const express = require('express');
const cors = require('cors');
const postRoutes = require('./routes/posts');
const commentRoutes = require('./routes/comments');
const db = require('./db');
const { register, metricsMiddleware } = require('./metrics');

const app = express();
const PORT = process.env.PORT || 5000;

// Middleware
app.use(cors());
app.use(express.json());
app.use(metricsMiddleware);

// Prometheus scrape endpoint — not behind /api so Prometheus can reach it directly
app.get('/metrics', async (_req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// Health check
app.get('/api/health', (_req, res) => {
  res.json({ status: 'ok', message: 'Jerney API is vibing ✨' });
});

// Routes
app.use('/api/posts', postRoutes);
app.use('/api/comments', commentRoutes);

// Initialize database and start server
async function start() {
  try {
    await db.initDB();
    app.listen(PORT, '0.0.0.0', () => {
      console.log(`🚀 Jerney backend running on port ${PORT}`);
    });
  } catch (err) {
    console.error('Failed to start server:', err);
    process.exit(1);
  }
}

start();
