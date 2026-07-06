import express from 'express'
import pino from 'pino'
import pinoHttp from 'pino-http'
import helmet from 'helmet'
import rateLimit from 'express-rate-limit'
import { auth } from './auth'

const logger = pino({
  level: process.env.LOG_LEVEL ?? 'info',
  base: { service: 'auth-service' },
  timestamp: pino.stdTimeFunctions.isoTime,
})

const app = express()
const PORT = process.env.PORT ?? 4001

app.use(pinoHttp({ logger }))
app.use(helmet())

const limiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 100,
  standardHeaders: true,
  legacyHeaders: false,
})
app.use(limiter)

app.use(express.json())

app.get('/health', (_req, res) =>
  res.json({
    status: 'ok',
    service: 'auth-service',
    uptime: process.uptime(),
    timestamp: new Date().toISOString(),
  })
)

app.all('/api/auth/*', async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`)
  const headers = new Headers(req.headers as Record<string, string>)
  const body =
    req.method !== 'GET' && req.method !== 'HEAD' ? JSON.stringify(req.body) : undefined

  const response = await auth.handler(
    new Request(url.toString(), { method: req.method, headers, body })
  )

  res.status(response.status)
  response.headers.forEach((value, key) => res.setHeader(key, value))
  res.send(await response.text())
})

const server = app.listen(PORT, () => logger.info(`auth-service running on port ${PORT}`))

process.on('SIGTERM', () => {
  logger.info('SIGTERM received, shutting down gracefully')
  server.close(() => {
    logger.info('Server closed')
    process.exit(0)
  })
})

export { app }
