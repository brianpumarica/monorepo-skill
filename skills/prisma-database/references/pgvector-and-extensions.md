# Prisma ORM, pgvector & PostgreSQL Extension Standard

---

## 1. Enabling `pgvector` & Database Extensions with Prisma

When building AI capabilities (embeddings, semantic search, RAG) with PostgreSQL:

### A. Database Initialization (`docker/init-db.sql`)
```sql
-- Enable vector extensions and uuid generators
CREATE EXTENSION IF NOT EXISTS "vector";
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
```

### B. Prisma Schema with Unsupported Vector Type (`apps/api/prisma/schema/embedding.prisma`)
```prisma
model DocumentChunk {
  id         String                 @id @default(uuid())
  content    String                 @db.Text
  metadata   Json?
  embedding  Unsupported("vector(1536)")? # OpenAI text-embedding-3-small dimension
  createdAt  DateTime               @default(now()) @map("created_at")

  @@map("document_chunks")
}
```

---

## 2. Querying Vector Embeddings via Prisma Raw SQL

Prisma supports vector search operations via type-safe `$queryRaw`:

```typescript
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

export interface SimilarChunk {
  id: string;
  content: string;
  similarity: number;
}

export async function findSimilarChunks(
  queryEmbedding: number[],
  limit = 5,
  threshold = 0.7,
): Promise<SimilarChunk[]> {
  const vectorString = `[${queryEmbedding.join(',')}]`;

  // Cosine distance operator (<=>) in pgvector
  const results = await prisma.$queryRaw<SimilarChunk[]>`
    SELECT 
      id, 
      content, 
      1 - (embedding <=> ${vectorString}::vector) AS similarity
    FROM document_chunks
    WHERE 1 - (embedding <=> ${vectorString}::vector) > ${threshold}
    ORDER BY similarity DESC
    LIMIT ${limit};
  `;

  return results;
}
```

---

## 3. High-Performance Connection Pool Sizing for Raspberry Pi

To avoid exhausting RAM or PostgreSQL connection slots on edge hardware (Raspberry Pi 5):

```typescript
// apps/api/src/db.ts
import { Pool } from 'pg';
import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from '@prisma/client';

const connectionString = process.env.DATABASE_URL;

const pool = new Pool({
  connectionString,
  max: 5,                  // Max 5 clients per container on Raspberry Pi
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000,
});

const adapter = new PrismaPg(pool);
export const prisma = new PrismaClient({ adapter });
```
