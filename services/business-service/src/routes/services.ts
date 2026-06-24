import { Router } from 'express'
import { db } from '../db'
import { serviceProvider, user } from '../db/schema'
import { and, desc, eq, ilike, or, sql } from 'drizzle-orm'
import { requireAuth } from '../middleware/requireAuth'

const router = Router()

router.get('/', async (req, res) => {
  try {
    const { category, search, limit: lq, offset: oq } = req.query
    const limit = parseInt(lq as string) || 12
    const offset = parseInt(oq as string) || 0

    let where
    if (category) {
      where = and(eq(serviceProvider.isActive, true), eq(serviceProvider.category, category as string))
    } else if (search) {
      where = and(
        eq(serviceProvider.isActive, true),
        or(
          ilike(serviceProvider.name, `%${search}%`),
          ilike(serviceProvider.description, `%${search}%`),
          ilike(serviceProvider.category, `%${search}%`),
          ilike(serviceProvider.location, `%${search}%`)
        )
      )
    } else {
      where = eq(serviceProvider.isActive, true)
    }

    const rows = await db
      .select({ service: serviceProvider, provider: { id: user.id, name: user.name, image: user.image } })
      .from(serviceProvider)
      .leftJoin(user, eq(serviceProvider.userId, user.id))
      .where(where)
      .orderBy(desc(serviceProvider.createdAt))
      .limit(limit)
      .offset(offset)

    res.json(rows)
  } catch { res.status(500).json({ message: 'Internal server error' }) }
})

router.get('/mine', requireAuth, async (req, res) => {
  try {
    res.json(
      await db
        .select({ service: serviceProvider, provider: { id: user.id, name: user.name, image: user.image } })
        .from(serviceProvider)
        .leftJoin(user, eq(serviceProvider.userId, user.id))
        .where(eq(serviceProvider.userId, req.userId!))
        .orderBy(desc(serviceProvider.createdAt))
    )
  } catch { res.status(500).json({ message: 'Internal server error' }) }
})

router.get('/:id', async (req, res) => {
  try {
    const id = parseInt(req.params.id as string)
    const [row] = await db
      .select({ service: serviceProvider, provider: { id: user.id, name: user.name, image: user.image } })
      .from(serviceProvider)
      .leftJoin(user, eq(serviceProvider.userId, user.id))
      .where(eq(serviceProvider.id, id))
    if (!row) { res.status(404).json({ message: 'Not found' }); return }
    res.json(row)
  } catch { res.status(500).json({ message: 'Internal server error' }) }
})

router.post('/', requireAuth, async (req, res) => {
  try {
    const data = req.body as {
      name: string; category: string; description: string
      rate?: string; location?: string; phone?: string; email?: string
      availability?: string; image?: string
    }
    const [created] = await db.insert(serviceProvider).values({
      userId: req.userId!,
      name: data.name,
      category: data.category,
      description: data.description,
      rate: data.rate,
      location: data.location,
      phone: data.phone,
      email: data.email,
      availability: data.availability,
      image: data.image,
    }).returning()
    res.status(201).json(created)
  } catch { res.status(500).json({ message: 'Internal server error' }) }
})

router.put('/:id', requireAuth, async (req, res) => {
  try {
    const id = parseInt(req.params.id as string)
    const [existing] = await db.select().from(serviceProvider).where(eq(serviceProvider.id, id))
    if (!existing) { res.status(404).json({ message: 'Not found' }); return }
    if (existing.userId !== req.userId) { res.status(403).json({ message: 'Unauthorized' }); return }
    const data = req.body
    const [updated] = await db.update(serviceProvider)
      .set({ ...data, updatedAt: sql`NOW()` })
      .where(eq(serviceProvider.id, id))
      .returning()
    res.json(updated)
  } catch { res.status(500).json({ message: 'Internal server error' }) }
})

router.delete('/:id', requireAuth, async (req, res) => {
  try {
    const id = parseInt(req.params.id as string)
    const [existing] = await db.select().from(serviceProvider).where(eq(serviceProvider.id, id))
    if (!existing) { res.status(404).json({ message: 'Not found' }); return }
    if (existing.userId !== req.userId) { res.status(403).json({ message: 'Unauthorized' }); return }
    await db.delete(serviceProvider).where(eq(serviceProvider.id, id))
    res.json({ success: true })
  } catch { res.status(500).json({ message: 'Internal server error' }) }
})

export default router
