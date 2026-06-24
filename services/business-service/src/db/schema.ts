import { pgTable, text, timestamp, boolean, serial, integer, doublePrecision } from 'drizzle-orm/pg-core'

export const user = pgTable('user', {
  id: text('id').primaryKey(),
  name: text('name').notNull(),
  email: text('email'),
  image: text('image'),
  role: text('role').notNull().default('member'),
  isVerified: boolean('isVerified').notNull().default(false),
})

export const category = pgTable('category', {
  id: serial('id').primaryKey(),
  name: text('name').notNull().unique(),
  slug: text('slug').notNull().unique(),
  icon: text('icon').notNull(),
  createdAt: timestamp('createdAt').notNull().defaultNow(),
})

export const business = pgTable('business', {
  id: serial('id').primaryKey(),
  userId: text('userId').notNull(),
  name: text('name').notNull(),
  slug: text('slug').notNull().unique(),
  description: text('description').notNull(),
  categoryId: integer('categoryId').notNull(),
  phone: text('phone'),
  email: text('email'),
  website: text('website'),
  address: text('address'),
  city: text('city'),
  state: text('state'),
  zipCode: text('zipCode'),
  image: text('image'),
  isFeatured: boolean('isFeatured').notNull().default(false),
  isApproved: boolean('isApproved').notNull().default(true),
  views: integer('views').notNull().default(0),
  latitude: doublePrecision('latitude'),
  longitude: doublePrecision('longitude'),
  createdAt: timestamp('createdAt').notNull().defaultNow(),
  updatedAt: timestamp('updatedAt').notNull().defaultNow(),
})

export const review = pgTable('review', {
  id: serial('id').primaryKey(),
  userId: text('userId').notNull(),
  businessId: integer('businessId').notNull(),
  rating: integer('rating').notNull(),
  comment: text('comment'),
  createdAt: timestamp('createdAt').notNull().defaultNow(),
  updatedAt: timestamp('updatedAt').notNull().defaultNow(),
})

export const job = pgTable('job', {
  id: serial('id').primaryKey(),
  userId: text('userId').notNull(),
  title: text('title').notNull(),
  slug: text('slug').notNull().unique(),
  description: text('description').notNull(),
  jobType: text('jobType').notNull().default('full-time'),
  location: text('location'),
  salary: text('salary'),
  contactEmail: text('contactEmail').notNull(),
  image: text('image'),
  isActive: boolean('isActive').notNull().default(true),
  createdAt: timestamp('createdAt').notNull().defaultNow(),
  updatedAt: timestamp('updatedAt').notNull().defaultNow(),
})

export const event = pgTable('event', {
  id: serial('id').primaryKey(),
  userId: text('userId').notNull(),
  title: text('title').notNull(),
  slug: text('slug').notNull().unique(),
  description: text('description').notNull(),
  eventDate: timestamp('eventDate').notNull(),
  location: text('location'),
  image: text('image'),
  isPublished: boolean('isPublished').notNull().default(true),
  createdAt: timestamp('createdAt').notNull().defaultNow(),
  updatedAt: timestamp('updatedAt').notNull().defaultNow(),
})

export const serviceProvider = pgTable('service_provider', {
  id: serial('id').primaryKey(),
  userId: text('userId').notNull(),
  name: text('name').notNull(),
  category: text('category').notNull(),
  description: text('description').notNull(),
  rate: text('rate'),
  location: text('location'),
  phone: text('phone'),
  email: text('email'),
  availability: text('availability'),
  image: text('image'),
  isActive: boolean('isActive').notNull().default(true),
  createdAt: timestamp('createdAt').notNull().defaultNow(),
  updatedAt: timestamp('updatedAt').notNull().defaultNow(),
})

export const booking = pgTable('booking', {
  id: serial('id').primaryKey(),
  businessId: integer('businessId').notNull(),
  name: text('name').notNull(),
  email: text('email').notNull(),
  phone: text('phone'),
  message: text('message').notNull(),
  preferredDate: text('preferredDate'),
  preferredTime: text('preferredTime'),
  status: text('status').notNull().default('pending'),
  isRead: boolean('isRead').notNull().default(false),
  createdAt: timestamp('createdAt').notNull().defaultNow(),
})
