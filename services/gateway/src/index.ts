import express from 'express'
import cors from 'cors'
import pino from 'pino'
import pinoHttp from 'pino-http'
import helmet from 'helmet'
import rateLimit from 'express-rate-limit'
import { createProxyMiddleware } from 'http-proxy-middleware'

const logger = pino({
  level: process.env.LOG_LEVEL ?? 'info',
  base: { service: 'gateway' },
  timestamp: pino.stdTimeFunctions.isoTime,
})

const app = express()
const PORT = process.env.PORT ?? 4000

const AUTH_URL     = process.env.AUTH_SERVICE_URL     ?? 'http://auth-service:4001'
const BUSINESS_URL = process.env.BUSINESS_SERVICE_URL ?? 'http://business-service:4002'
const REVIEW_URL   = process.env.REVIEW_SERVICE_URL   ?? 'http://review-service:4003'
const INQUIRY_URL  = process.env.INQUIRY_SERVICE_URL  ?? 'http://inquiry-service:4004'

app.use(pinoHttp({ logger }))
app.use(helmet())

const limiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 100,
  standardHeaders: true,
  legacyHeaders: false,
})
app.use(limiter)

app.use(cors({ origin: process.env.FRONTEND_URL ?? 'http://localhost:3000', credentials: true }))

app.get('/health', (_req, res) =>
  res.json({
    status: 'ok',
    service: 'gateway',
    uptime: process.uptime(),
    timestamp: new Date().toISOString(),
  })
)

const bsvc = (path: string) =>
  createProxyMiddleware({ pathFilter: path, target: BUSINESS_URL, changeOrigin: true })

app.use(createProxyMiddleware({ pathFilter: '/api/auth',       target: AUTH_URL,     changeOrigin: true }))
app.use(bsvc('/api/upload'))
app.use(bsvc('/api/categories'))
app.use(bsvc('/api/businesses'))
app.use(bsvc('/api/jobs'))
app.use(bsvc('/api/events'))
app.use(bsvc('/api/bookings'))
app.use(bsvc('/api/members'))
app.use(bsvc('/api/admin'))
app.use(bsvc('/api/stats'))
app.use(bsvc('/api/services'))
app.use(createProxyMiddleware({ pathFilter: '/api/reviews',   target: REVIEW_URL,   changeOrigin: true }))
app.use(createProxyMiddleware({ pathFilter: '/api/inquiries', target: INQUIRY_URL,   changeOrigin: true }))
app.use(bsvc('/uploads'))

const server = app.listen(PORT, () => logger.info(`Gateway running on port ${PORT}`))

process.on('SIGTERM', () => {
  logger.info('SIGTERM received, shutting down gracefully')
  server.close(() => {
    logger.info('Server closed')
    process.exit(0)
  })
})

export { app }
