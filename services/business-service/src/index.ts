import express from 'express'
import path from 'path'
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

const app = express()
const PORT = process.env.PORT ?? 4002
const UPLOADS_DIR = process.env.UPLOADS_DIR ?? '/uploads'

app.use(express.json())
app.get('/health', (_req, res) => res.json({ status: 'ok', service: 'business-service' }))
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

app.listen(PORT, () => console.log(`business-service running on port ${PORT}`))
