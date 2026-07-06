import express from 'express'
import pino from 'pino'
import pinoHttp from 'pino-http'
import helmet from 'helmet'
import rateLimit from 'express-rate-limit'
import inquiriesRouter from './routes/inquiries'

const logger = pino({
  level: process.env.LOG_LEVEL ?? 'info',
  base: { service: 'inquiry-service' },
  timestamp: pino.stdTimeFunctions.isoTime,
})

const app = express()
const PORT = process.env.PORT ?? 4004

app.use(pinoHttp({ logger }))
app.use(helmet())
app.use(rateLimit({ windowMs: 15 * 60 * 1000, max: 100, standardHeaders: true, legacyHeaders: false }))
app.use(express.json())

app.get('/health', (_req, res) => {
  res.json({ status: 'ok', service: 'inquiry-service', uptime: process.uptime(), timestamp: new Date().toISOString() })
})

app.use('/api/inquiries', inquiriesRouter)

const server = app.listen(PORT, () => logger.info(`inquiry-service running on port ${PORT}`))

process.on('SIGTERM', () => {
  logger.info('SIGTERM received, shutting down gracefully')
  server.close(() => { logger.info('Server closed'); process.exit(0) })
})

export { app }
