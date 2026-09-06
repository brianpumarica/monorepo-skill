# Database Lifecycle & Entrypoint Runner

---

## 0. Reglas Innegociables del Arranque

Hechos que condicionan todo lo demás. Son agnósticos de ORM y de lenguaje: valen igual para
Prisma, Alembic, Flyway o SQL a mano.

| Regla | Consecuencia si se ignora |
| :--- | :--- |
| **El entrypoint corre en CADA arranque del contenedor**, producción incluida | Cualquier operación destructiva que viva ahí se dispara sola, sin que nadie la pida |
| **`docker start` reejecuta el ENTRYPOINT** — no es un "resume" | Parar y arrancar un contenedor "para no tocar nada" ejecuta el arranque completo otra vez |
| **El seeder nunca borra ni sobrescribe**: sólo crea lo que falta | Un `deleteMany` o un `update` no vacío revierte el trabajo real de los usuarios en cada deploy |
| **El comando de migraciones no lleva `\|\| true`** | La app arranca contra un schema desactualizado y el error queda escondido en el log |
| **El script de inicialización sólo corre con el volumen vacío** | Con un volumen ya existente no se ejecuta: los datos nuevos nunca llegan (ver §4) |
| **Las variables de entorno se fijan al crear el contenedor** | `restart` no toma los cambios; hace falta recrear |
| **El chequeo de readiness no garantiza que la base acepte consultas** | Durante la inicialización responde un servidor temporal: consultar ahí da resultados falsos |
| **El binario de readiness tiene que existir DENTRO de la imagen** | `pg_isready` no viene en `node:*-alpine` ni en `python:*-slim`: sin `postgresql-client` el arranque agota los reintentos y culpa a la base de un paquete faltante |
| **Las rutas del entrypoint se resuelven contra la carpeta de la app, no contra el `WORKDIR`** | En un monorepo (`WORKDIR /app`, app en `/app/apps/api`) ningún `if` matchea: migraciones y seed se saltean **en silencio** |

---

## 1. Idempotent `entrypoint.sh`

Vale igual para `apps/api/entrypoint.sh` (monorepo pnpm) y para `backend/entrypoint.sh` (layout
npm): **se ancla solo**, sin editar rutas por proyecto.

```bash
#!/bin/sh
set -e

# --- Anclaje de rutas -------------------------------------------------------------------
# El WORKDIR de la imagen NO siempre es la carpeta de la app: en un monorepo la API vive en
# /app/apps/api mientras el WORKDIR es /app. Si las rutas relativas se resuelven contra el
# WORKDIR, ningun `if` de aca abajo matchea y las migraciones se saltean EN SILENCIO (§0).
# Se ancla todo a la ubicacion real del script, pero el proceso final se ejecuta con el
# WORKDIR original para no cambiarle el contexto al CMD.
APP_DIR="${APP_DIR:-$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)}"
echo "==> App directory: $APP_DIR"

DB_HOST="${DB_HOST:-database}"
DB_PORT="${DB_PORT:-5432}"
DB_USER="${POSTGRES_USER:-postgres}"
DB_NAME="${POSTGRES_DB:-postgres}"
MAX_TRIES="${DB_WAIT_TRIES:-30}"

# --- Requisitos de la imagen ------------------------------------------------------------
if ! command -v pg_isready >/dev/null 2>&1; then
  echo "ERROR: falta pg_isready en la imagen."
  echo "       Instalar postgresql-client en la etapa 'base' del Dockerfile"
  echo "       (dockerfile-recipes.md 7.3). Abortando."
  exit 1
fi

# --- Espera de base ---------------------------------------------------------------------
# pg_isready tambien responde OK contra el servidor temporal de inicializacion (§0). Cuando
# hay credenciales y psql disponible, se confirma con una consulta real antes de migrar.
db_ready() {
  pg_isready -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" >/dev/null 2>&1 || return 1
  if [ -n "${POSTGRES_PASSWORD:-}" ] && command -v psql >/dev/null 2>&1; then
    PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" \
      -d "$DB_NAME" -tAc 'SELECT 1' >/dev/null 2>&1 || return 1
  fi
  return 0
}

echo "==> Waiting for database at ${DB_HOST}:${DB_PORT}/${DB_NAME}..."
TRY=1
until db_ready; do
  if [ "$TRY" -ge "$MAX_TRIES" ]; then
    echo "ERROR: la base no acepto consultas tras ${MAX_TRIES} intentos. Abortando."
    exit 1
  fi
  echo "    not ready yet (${TRY}/${MAX_TRIES}). Retrying in 1s..."
  TRY=$((TRY + 1))
  sleep 1
done
echo "==> Database accepting queries."

# --- Migraciones ------------------------------------------------------------------------
# Sin "|| true" (§0): una migracion fallida aborta el arranque en lugar de dejar la app
# sirviendo contra un schema desactualizado.
if [ -f "$APP_DIR/prisma/schema.prisma" ]; then
  echo "==> Running Prisma migrations..."
  ( cd "$APP_DIR" && \
    if [ -x ./node_modules/.bin/prisma ]; then ./node_modules/.bin/prisma migrate deploy
    elif command -v pnpm >/dev/null 2>&1; then pnpm exec prisma migrate deploy
    else npx --no-install prisma migrate deploy
    fi )
elif [ -f "$APP_DIR/alembic.ini" ]; then
  echo "==> Running Alembic migrations..."
  ( cd "$APP_DIR" && alembic upgrade head )
else
  echo "==> No migration tool detected in $APP_DIR (skipping)."
fi

# --- Seed idempotente -------------------------------------------------------------------
# El entrypoint corre en CADA arranque, produccion incluida (§0): el seeder solo crea lo que
# falta. Nunca borra ni sobrescribe.
if [ -f "$APP_DIR/dist/prisma/seed.js" ]; then
  echo "==> Running compiled seed (dist/prisma/seed.js)..."
  ( cd "$APP_DIR" && node dist/prisma/seed.js )
elif [ -f "$APP_DIR/dist/seed.js" ]; then
  echo "==> Running compiled seed (dist/seed.js)..."
  ( cd "$APP_DIR" && node dist/seed.js )
elif [ -f "$APP_DIR/prisma/seed.ts" ] && [ "${NODE_ENV:-}" != "production" ]; then
  echo "==> Running TypeScript seed (dev only)..."
  ( cd "$APP_DIR" && \
    if [ -x ./node_modules/.bin/tsx ]; then ./node_modules/.bin/tsx prisma/seed.ts
    else npx --no-install tsx prisma/seed.ts
    fi )
else
  echo "==> No seed script found (skipping)."
fi

echo "==> Starting main process: $*"
exec "$@"
```

### Por qué está escrito así

| Detalle | Motivo |
| :--- | :--- |
| `APP_DIR` derivado de `$0` | Un único archivo sirve para monorepo pnpm y para layout npm sin editar rutas |
| `( cd "$APP_DIR" && ... )` en subshell | El `cd` no se filtra al `exec "$@"` final: el CMD conserva el `WORKDIR` de la imagen |
| `command -v pg_isready` antes del loop | Distingue "falta un paquete" de "la base está caída" — 30 s de reintentos no lo hacían |
| `TRY -ge MAX_TRIES` **dentro** del loop | La versión con `[ $COUNT -eq $MAX_TRIES ]` después del `until` abortaba aunque la base hubiera respondido justo en el último intento |
| `psql -tAc 'SELECT 1'` | Es lo único que descarta el servidor temporal de inicialización (§0) |
| `node_modules/.bin` antes que `npx` | Binario local, sin red: `npx` sin `--no-install` descarga en cada arranque (§2.6) |

---

## 2. Secure Production Seeder Standard (`seed.ts`)

### Security Rules for Database Seeders:
1. **Never hardcode default admin passwords in source code**: Avoid `admin / admin123` defaults that can be leaked to git or deployed unconfigured.
2. **Mandatory Environment Variables**: Read initial administrative credentials strictly from `process.env`. Throw an error if missing.
3. **Idempotency**: Use `upsert` or check existence before creating records.
4. **Nunca destructivo** (§0): nada de `deleteMany`, `TRUNCATE`, ni `update` con campos en un
   `upsert`. Sólo crea lo que falta.
5. **Una sola fuente de datos**: el seeder no carga un volcado paralelo (`seed-data.json` y
   similares) que pueda divergir del estado real. Si hace falta poblar una instancia nueva, eso
   es trabajo del script de inicialización (§4), no del seeder.
6. **La herramienta de migraciones va en `dependencies`, no en `devDependencies`.** Tanto
   `pnpm --prod deploy` como `npm ci --omit=dev` podan las devDependencies, y `npm ci` además
   **rearma `node_modules` de cero**: por eso el cliente de Prisma se genera *después* de la poda
   (ver [`dockerfile-recipes.md`](./dockerfile-recipes.md) §2). Si el binario no queda en la
   imagen, el entrypoint lo descarga en cada arranque —y falla en silencio cuando no hay red.

```typescript
// apps/api/prisma/seed.ts
import { PrismaClient } from '@prisma/client';
import * as bcrypt from 'bcrypt';

const prisma = new PrismaClient();

async function main() {
  const adminEmail = process.env.ADMIN_EMAIL || process.env.ADMIN_USERNAME;
  const adminPassword = process.env.ADMIN_PASSWORD;

  if (!adminEmail || !adminPassword) {
    console.warn('⚠️ ADMIN_EMAIL / ADMIN_PASSWORD not set. Skipping default admin seed.');
    return;
  }

  const hashedPassword = await bcrypt.hash(adminPassword, 10);

  await prisma.user.upsert({
    where: { email: adminEmail },
    update: {},
    create: {
      email: adminEmail,
      name: 'System Admin',
      password: hashedPassword,
      role: 'ADMIN',
    },
  });

  console.log('✅ Admin user verified/seeded successfully.');
}

main()
  .catch((e) => {
    console.error('❌ Seeding error:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
```

---

## 3. Line Ending Safety (`.gitattributes`)

Always include `.gitattributes` at the monorepo root to prevent Windows CRLF issues in Linux containers:

```gitattributes
* text=auto
*.sh text eol=lf
*.sql text eol=lf
Dockerfile* text eol=lf
```
---

## 4. Script de Inicialización de la Base (`docker/init-db.sql`)

**Sólo se ejecuta cuando el volumen de datos está vacío.** Es así como funciona
`/docker-entrypoint-initdb.d`: con un volumen ya poblado, el archivo se ignora por completo.

- Sirve para: levantar entornos nuevos y **reconstruir producción desde cero**.
- **No sirve para**: llevar datos a un entorno existente en un deploy normal. Para eso hace falta
  una migración o un script puntual e idempotente.

Si el archivo se genera desde un volcado de producción, verificar antes de confiar en él:

1. **Contadores y secuencias** en `max(id) + 1`. Si quedan atrasados, la primera alta revienta por
   clave duplicada.
2. **Migraciones pre-marcadas** con sus checksums reales, no con valores inventados (§5).
3. **Sin columnas que ya no existan** en el schema actual.
4. **Cero huérfanos** en cada relación de clave foránea.
5. Levantarlo contra una base limpia y descartable, y comparar conteos con el origen.

---

## 5. Checksums de Migraciones y Saltos de Línea

Las herramientas que validan las migraciones por hash lo calculan sobre el **contenido con LF**.
En una máquina de desarrollo Windows, el mismo archivo con CRLF da un hash **distinto**.

- El `.gitattributes` de §3 es la prevención — pero **sólo aplica a los archivos que entran después**.
  Los que ya estaban en disco conservan sus CRLF: hay que renormalizarlos explícitamente
  (`git add --renormalize .`).
- Al comparar checksums contra los guardados en la base, normalizar a LF primero. Compararlos
  crudos desde Windows da diferencias que no existen.

---

## 6. Volcados y Restauraciones Seguras

- **No hay que parar la aplicación para hacer un volcado.** `pg_dump` toma un snapshot
  transaccional consistente con la app escribiendo. Peor aún: parar el backend y volver a
  arrancarlo **reejecuta el entrypoint** (§0), que es justamente el riesgo que se quería evitar.
- **Nunca `docker exec -t` con redirección a archivo.** La TTY convierte LF en CRLF y corrompe el
  volcado. Usar `docker exec` sin `-t`.
- **Restaurar siempre primero en una instancia descartable** y comparar conteos tabla por tabla
  antes de dar el respaldo por bueno.
- **`down -v` no es un rollback**: borra el volumen de datos. El rollback es restaurar un volcado.
---

## 7. Traer un Volcado desde un Servidor sin SSH ni Transferencia de Archivos

Cuando el único acceso al servidor es una **terminal web de copiar y pegar** (ttyd y similares),
no hay `scp`, ni `rsync`, ni carpeta compartida. Subir el volcado a un servicio en la nube o a un
panel web para bajarlo desde ahí expone datos productivos a un tercero y agrega un punto de
fallo. La alternativa es **transportarlo por el propio canal de texto**: comprimir, codificar en
base64, imprimir entre delimitadores, copiar y reconstruir en la máquina local.

Funciona porque base64 es texto ASCII plano: sobrevive intacto al portapapeles y al render de la
terminal, que es exactamente lo que corrompe a un `.sql` crudo.

### 7.1 En el servidor — generar el bloque

Un solo comando, pegable de una vez:

```bash
echo "--- INICIO DUMP ---"; docker exec <contenedor-db> pg_dump -U <usuario> -d <base> | gzip -9 | base64 -w 200; echo "--- FIN DUMP ---"
```

- **`docker exec` sin `-t`.** Con `-t` la TTY convierte LF en CRLF y corrompe el volcado (§6).
- **`gzip -9` antes de codificar.** base64 infla un 33%; comprimir primero suele dejar el texto
  en torno a un tercio del `.sql` original.
- **`-w 200`** parte la salida en líneas: un único renglón de millones de caracteres cuelga
  terminales y editores. Al decodificar, los saltos de línea se ignoran.
- **Los delimitadores no son decorativos:** marcan exactamente qué seleccionar, y al reconstruir
  hay que borrarlos junto con cualquier prompt que la terminal haya intercalado.

Antes de copiar, dejar registrado el hash del original para poder verificar del otro lado.

> [!IMPORTANT]
> **Hashear el volcado crudo no sirve: da distinto en cada corrida.** Desde PostgreSQL 16.10 /
> 17.6, `pg_dump` emite un par de líneas `\restrict <token>` / `\unrestrict <token>` con un
> **token aleatorio por ejecución**. Dos volcados de exactamente los mismos datos producen
> hashes distintos, y el operador termina creyendo que el pegado se corrompió cuando está
> perfecto. Hay que excluir esas dos líneas **de los dos lados**.

```bash
docker exec <contenedor-db> pg_dump -U <usuario> -d <base> \
  | grep -vE '^\\(restrict|unrestrict)' | sha256sum
```

### 7.2 En la máquina local — reconstruir y verificar

Pegar el bloque (sin los delimitadores) en `dump.b64` y decodificar:

```bash
base64 -d dump.b64 | gunzip > dump.sql
grep -vE '^\\(restrict|unrestrict)' dump.sql | sha256sum   # debe coincidir con el del servidor
grep -c '' dump.sql                                        # sanity check: cantidad de lineas
```

**No suprimir los errores de `gunzip`.** Un `2>/dev/null` de más convierte un volcado truncado
en un archivo a medias que parece válido: el `.sql` abre, tiene SQL adentro, y le faltan filas.

Y además del hash, contar lo que importa —es la verificación que un operador entiende de un
vistazo, y la que detecta un volcado de la base equivocada:

```bash
for t in products categories users _prisma_migrations; do
  printf '%-22s %s\n' "$t" "$(sed -n "/^COPY public.$t /,/^\\\\\.$/p" dump.sql | grep -vc '^COPY\|^\\\.$')"
done
```

> En Windows, correr esto desde Git Bash. La alternativa en PowerShell es
> `[IO.File]::WriteAllBytes('dump.gz', [Convert]::FromBase64String((Get-Content dump.b64 -Raw)))`
> y descomprimir después.

**El hash es la parte que no se saltea.** Es la única prueba de que el pegado no perdió ni
alteró nada, y es barato: si no coincide, se repite antes de construir nada encima.

### 7.3 Si el bloque es demasiado grande para un solo pegado

Partirlo en el servidor y emitir una parte por vez:

```bash
docker exec <contenedor-db> pg_dump -U <usuario> -d <base> | gzip -9 | base64 -w 200 | split -l 5000 - parte_
cat parte_aa   # repetir con cada parte, copiando de a una
```

Localmente se concatenan **en orden** antes de decodificar (`cat parte_* > dump.b64`). El hash
final valida el conjunto: si una parte quedó pegada dos veces o fuera de orden, no coincide.

### 7.4 Cuándo NO usar esto

Es la vía para bases de decenas de MB. Por encima de eso, o si el volcado tiene que viajar de
forma recurrente, la respuesta correcta es habilitar un canal real de transferencia — no partir
el pegado en cincuenta pedazos.
