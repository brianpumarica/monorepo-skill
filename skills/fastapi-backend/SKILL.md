---
name: fastapi-backend
description: Production standard, async architectural patterns, and container setup for FastAPI backends with Python in full-stack monorepos. Covers Pydantic v2 schemas, async lifespan handlers, SQLAlchemy 2.0 async engine with asyncpg, get_db dependency injection, CORS middleware for Vercel/Cloudflare, and Uvicorn hot-reloading in Docker. Use whenever creating or maintaining a Python FastAPI service.
---

# FastAPI Async Backend Production Runbook

This skill establishes the production standard for developing high-performance, asynchronous **FastAPI** backend services with Python 3.11+ inside full-stack monorepos.

---

## 1. Directory Structure

```
apps/api/
├── app/
│   ├── api/
│   │   ├── v1/
│   │   │   ├── endpoints/
│   │   │   │   ├── auth.py
│   │   │   │   └── users.py
│   │   │   └── router.py
│   │   └── deps.py             # Dependency injection (get_db, current_user)
│   ├── core/
│   │   ├── config.py           # Pydantic BaseSettings
│   │   └── database.py         # Async SQLAlchemy engine & session maker
│   ├── models/                 # SQLAlchemy 2.0 Declarative Models
│   ├── schemas/                # Pydantic v2 DTO schemas
│   └── main.py                 # Lifespan app initialization
├── Dockerfile
├── entrypoint.sh               # Alembic migration runner
└── pyproject.toml              # (or requirements.txt)
```

---

## 2. Modern Async Database Engine & Lifespan (`app/core/database.py` & `main.py`)

### `app/core/database.py`:
```python
from collections.abc import AsyncGenerator
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from app.core.config import settings

# Async PostgreSQL URL: postgresql+asyncpg://user:pass@host:5432/dbname
engine = create_async_engine(
    str(settings.DATABASE_URL),
    pool_pre_ping=True,
    pool_size=5,          # Optimal for Raspberry Pi memory constraints
    max_overflow=10,
    echo=settings.DEBUG,
)

async_session_maker = async_sessionmaker(
    engine, class_=AsyncSession, expire_on_commit=False
)

async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with async_session_maker() as session:
        try:
            yield session
        finally:
            await session.close()
```

### `app/main.py` (Modern Lifespan Pattern):
```python
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.api.v1.router import api_router
from app.core.config import settings
from app.core.database import engine

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: Verify DB connection / initialize pools
    yield
    # Shutdown: Dispose DB connection pools cleanly
    await engine.dispose()

app = FastAPI(
    title=settings.PROJECT_NAME,
    openapi_url=f"{settings.API_V1_STR}/openapi.json" if settings.DEBUG else None,
    docs_url="/docs" if settings.DEBUG else None,
    lifespan=lifespan,
)

# CORS setup for Vercel and Cloudflare Tunnel
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(api_router, prefix=settings.API_V1_STR)

@app.get("/health", tags=["Health"])
async def health_check():
    return {"status": "healthy", "service": "fastapi-backend"}
```

---

## 3. Docker Compose & Hot-Reload Integration

In `docker-compose.yml` (Development):
```yaml
  backend:
    build:
      context: .
      dockerfile: apps/api/Dockerfile
      target: development
    volumes:
      - ./apps/api:/app
    ports:
      - "3004:3004"
    environment:
      - DATABASE_URL=postgresql+asyncpg://postgres:postgres@database:5432/app_db
    # Hot-reload with uvicorn listening on 0.0.0.0
    command: uvicorn app.main:app --host 0.0.0.0 --port 3004 --reload --reload-dir /app
```

---

## 4. Multi-Stage Dockerfile (`apps/api/Dockerfile`)

```dockerfile
FROM python:3.11-slim AS base
WORKDIR /app
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

FROM base AS builder
RUN apt-get update && apt-get install -y --no-install-recommends gcc libpq-dev && rm -rf /var/lib/apt/lists/*
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
COPY apps/api/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

FROM base AS production
RUN groupadd -r appgroup && useradd -r -g appgroup -s /sbin/nologin -d /app appuser
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
COPY --chown=appuser:appgroup apps/api /app
USER appuser
EXPOSE 3004
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "3004", "--workers", "2"]
```
