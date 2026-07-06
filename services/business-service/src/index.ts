import express from 'express'
import path from 'path'
import pino from 'pino'
import pinoHttp from 'pino-http'
import helmet from 'helmet'
import rateLimit from 'express-rate-limit'
import categoriesRouter from './routes/categories'
import businessesRouter from './routes/businesses'
import jobsRouter from './routes/jobs'
import eventsRouter from './routes/events'
import bookingsRouter from './routes/bookings'
import membersRouter from './routes/members'
import adminRouter from './routes/admin'
import uploadRouter from './routes/upload'
import statsRouter from './routes/stats'
import servicesRouter from './routes/services'

const logger = pino({
  level: process.env.LOG_LEVEL ?? 'info',
  base: { service: 'business-service' },
  timestamp: pino.stdTimeFunctions.isoTime,
})

const app = express()
const PORT = process.env.PORT ?? 4002
const UPLOADS_DIR = process.env.UPLOADS_DIR ?? '/uploads'

app.use(pinoHttp({ logger }))
app.use(helmet())
app.use(rateLimit({ windowMs: 15 * 60 * 1000, max: 100, standardHeaders: true, legacyHeaders: false }))
app.use(express.json())

app.get('/health', (_req, res) => {
  res.json({ status: 'ok', service: 'business-service', uptime: process.uptime(), timestamp: new Date().toISOString() })
})

app.use('/uploads', express.static(UPLOADS_DIR))
app.use('/api/upload', uploadRouter)
app.use('/api/categories', categoriesRouter)
app.use('/api/businesses', businessesRouter)
app.use('/api/jobs', jobsRouter)
app.use('/api/events', eventsRouter)
app.use('/api/bookings', bookingsRouter)
app.use('/api/members', membersRouter)
app.use('/api/admin', adminRouter)
app.use('/api/stats', statsRouter)
app.use('/api/services', servicesRouter)

const server = app.listen(PORT, () => logger.info(`business-service running on port ${PORT}`))

process.on('SIGTERM', () => {
  logger.info('SIGTERM received, shutting down gracefully')
  server.close(() => { logger.info('Server closed'); process.exit(0) })
})

export { app }
