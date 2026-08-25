---
name: nestjs-backend
description: Production-ready architectural patterns, boilerplate templates, and container workflows for NestJS backends in full-stack monorepos. Covers modular monoliths, global exception filters, standardized response interceptors, DTO validation pipelines, Swagger OpenAPI docs, Docker hot-reload with nodemon legacy polling, and minimal-overhead Alpine deployment. Use whenever creating, restructuring, or maintaining a NestJS API.
---

# NestJS Modular Backend Production Runbook

This skill establishes the production standard for developing scalable, modular **NestJS** backend APIs inside full-stack monorepos.

---

## 1. Modular Directory Layout

```
apps/api/src/
├── common/
│   ├── filters/
│   │   └── all-exceptions.filter.ts   # Global standardized error handler
│   ├── interceptors/
│   │   └── transform.interceptor.ts    # Standardizes output: { success, data, error }
│   └── pipes/
│       └── validation.pipe.ts          # Strips unwhitelisted properties & validates
├── modules/
│   ├── auth/                           # Authentication, JWT, guards
│   ├── users/                          # User CRUD & service layer
│   └── health/                         # Liveness/readiness probes for Docker
├── app.module.ts                       # Root application module
└── main.ts                             # Bootstrap file with CORS & Swagger
```

---

## 2. Standardized Response Interceptor & Exception Filter

Ensure all endpoints return a consistent JSON contract that the frontend (`apps/web`) can reliably consume:

### `src/common/interceptors/transform.interceptor.ts`:
```typescript
import { CallHandler, ExecutionContext, Injectable, NestInterceptor } from '@nestjs/common';
import { Observable, map } from 'rxjs';

export interface ApiResponse<T> {
  success: boolean;
  data: T;
  error: null;
  timestamp: string;
}

@Injectable()
export class TransformInterceptor<T> implements NestInterceptor<T, ApiResponse<T>> {
  intercept(context: ExecutionContext, next: CallHandler): Observable<ApiResponse<T>> {
    return next.handle().pipe(
      map((data) => ({
        success: true,
        data,
        error: null,
        timestamp: new Date().toISOString(),
      })),
    );
  }
}
```

### `src/common/filters/all-exceptions.filter.ts`:
```typescript
import { ExceptionFilter, Catch, ArgumentsHost, HttpException, HttpStatus } from '@nestjs/common';
import { Response } from 'express';

@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  catch(exception: unknown, host: ArgumentsHost) {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();

    const status =
      exception instanceof HttpException
        ? exception.getStatus()
        : HttpStatus.INTERNAL_SERVER_ERROR;

    const message =
      exception instanceof HttpException
        ? (exception.getResponse() as any)?.message || exception.message
        : 'Internal server error';

    response.status(status).json({
      success: false,
      data: null,
      error: {
        statusCode: status,
        message,
      },
      timestamp: new Date().toISOString(),
    });
  }
}
```

---

## 3. Production Bootstrap (`src/main.ts`)

```typescript
import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { AppModule } from './app.module';
import { TransformInterceptor } from './common/interceptors/transform.interceptor';
import { AllExceptionsFilter } from './common/filters/all-exceptions.filter';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  // CORS configured for Cloudflare Tunnel and Vercel domains
  const allowedOrigins = process.env.CORS_ALLOWED_ORIGINS
    ? process.env.CORS_ALLOWED_ORIGINS.split(',')
    : ['http://localhost:8084', 'http://localhost:3000'];

  app.enableCors({
    origin: (origin, callback) => {
      if (!origin || allowedOrigins.includes(origin) || origin.endsWith('.vercel.app')) {
        callback(null, true);
      } else {
        callback(new Error('Blocked by CORS'));
      }
    },
    credentials: true,
  });

  // Global validation pipeline
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );

  // Global filters and interceptors
  app.useGlobalInterceptors(new TransformInterceptor());
  app.useGlobalFilters(new AllExceptionsFilter());

  // Swagger OpenAPI Documentation
  if (process.env.NODE_ENV !== 'production') {
    const config = new DocumentBuilder()
      .setTitle('Monorepo API')
      .setDescription('Modular NestJS Backend Documentation')
      .setVersion('1.0')
      .addBearerAuth()
      .build();
    const document = SwaggerModule.createDocument(app, config);
    SwaggerModule.setup('docs', app, document);
  }

  const port = process.env.PORT || 3004;
  await app.listen(port, '0.0.0.0');
  console.log(`🚀 API running on http://0.0.0.0:${port}`);
}
bootstrap();
```

---

## 4. Docker Hot-Reload Configuration (`nodemon.json`)

To prevent file watch drops inside Docker mounted volumes:

`apps/api/nodemon.json`:
```json
{
  "watch": ["src"],
  "ext": "ts",
  "ignore": ["src/**/*.spec.ts"],
  "legacyWatch": true,
  "exec": "nest start --watch"
}
```
