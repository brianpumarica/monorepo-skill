# Puertos: tu máquina y el servidor

> Una sola página para responder "¿en qué puerto va este proyecto?" en los dos lugares donde
> pasa. Los detalles viven en los documentos enlazados; acá está el mapa.

El problema es el mismo en los dos sitios — **dos proyectos eligen el mismo número** — pero se
resuelve distinto, porque lo que está en juego es distinto:

| | Tu máquina de desarrollo | Servidor (Raspberry Pi) |
| :--- | :--- | :--- |
| **Qué choca** | El 3000 / 5173 / 8080 de todos los proyectos de prueba; los servidores de desarrollo **se mueven solos** al puerto siguiente y no avisan | Dos contenedores publicando el mismo puerto: el `up` falla con "port is already allocated", con el contenedor viejo ya bajado |
| **Herramienta** | [`puerto.sh`](./puerto.sh) — se instala **una vez por máquina** como `puerto` | [`chequear-host.sh`](./chequear-host.sh) — se copia a `scripts/` **en cada repo** |
| **Quién decide el número** | La herramienta: un bloque fijo de 10 puertos por proyecto, derivado de su nombre (rango 4000-4999) | La herramienta lo **sugiere** (`alta`); lo escribe una persona en el `.env` del servidor |
| **Dónde queda anotado** | `~/.puertos`, fuera de todo repo | En ningún archivo: el servidor mismo es el registro (contenedores, `.env` de cada proyecto, `crontab`) |
| **Cuándo actúa** | Al crear el proyecto (`puerto asignar`) y a demanda (`puerto listar`) | Al dar de alta (`alta`) y **en cada deploy**, antes de tocar nada |
| **Detalle** | [`docker-compose-recipes.md`](./docker-compose-recipes.md) §0.2 | [`ci-cd-deployment-pipeline.md`](./ci-cd-deployment-pipeline.md) §2.4 |

Las dos son independientes: el `.env` local está en `.gitignore` y nunca viaja al servidor, y el
servidor solo mira sus propios contenedores. Los rangos están separados a propósito (4000-4999 en
tu máquina; 3000-3999 backend, 8000-8999 frontend y 5400-5499 base en el servidor), así un número
copiado de uno al otro no choca con nada.

---

## 1. En tu máquina

```bash
# Una sola vez por máquina (en Git Bash, ~/bin suele estar en el PATH):
cp puerto.sh ~/bin/puerto && chmod +x ~/bin/puerto

puerto asignar            # en la carpeta del proyecto: escribe los puertos en el .env
puerto listar             # tus proyectos, sus puertos y cuáles están corriendo AHORA
puerto quien 4661         # de quién es ese puerto
puerto liberar <nombre>   # devuelve el bloque de un proyecto que ya no existe
```

- Funciona **con y sin Docker**: el mismo número vale por fuera y por dentro del contenedor, así
  `npm run dev` y `docker compose up` comparten un solo `.env`.
- Para que un servidor **falle en vez de moverse** hay que darle el puerto explícito y estricto
  (`strictPort` en Vite, `-p` en Next, `listen(PORT)` en Node): ejemplo en
  [`docker-compose-recipes.md`](./docker-compose-recipes.md) §0.2.
- Un proyecto que ya existía conserva sus puertos hasta que corras `puerto asignar` en él.

## 2. En el servidor

Un proyecto nuevo, en orden:

1. **Primer push.** Falla a propósito en el paso del `.env` (todavía no existe), pero deja el repo
   en el workspace del runner.
2. **Elegir puertos y horario libres**, desde el workspace:
   ```bash
   sudo -u github-runner bash /home/github-runner/actions-runner/_work/<repo>/<repo>/scripts/chequear-host.sh alta
   ```
   Imprime `BACKEND_HOST_PORT`, `DB_HOST_PORT` (y `FRONTEND_HOST_PORT` si el frontend va en
   contenedor) que nadie usa ni tiene reservados, y el próximo horario de backup libre.
3. **Crear el `.env`** con `crear-env.sh`: **él mismo asigna esos puertos libres** a las
   `*_HOST_PORT` que están vacías en `.env.example` (no hay que escribirlos). Dejar esas variables
   vacías en la plantilla, y con valor solo las que de verdad son fijas. Si el frontend va a Vercel,
   no dejar `FRONTEND_HOST_PORT=` en la plantilla: se le asignaría un puerto que nadie publica
   (`docker-compose-recipes.md`, nota de «Puertos»). El horario va en la línea de `scripts/crontab`.
4. **Volver a correr el deploy.** El paso `chequear-host.sh` verifica que nada cambió desde el
   paso 2 y **falla antes de bajar nada** si un puerto ya es de otro proyecto.

`alta` es una foto de ese momento: no reserva nada hasta que el `.env` existe en
`env-backups/<repo>/`. Si pasan días entre `alta` y el primer deploy, volver a correrlo.

Un puerto cuenta como **de otro proyecto** si: lo publica un contenedor que no empieza con
`$PROJECT_PREFIX-`; está en el `.env` guardado de otro repo (aunque ese proyecto esté detenido);
o lo escucha un proceso que no es un contenedor. Un redeploy del mismo proyecto no es conflicto.

## 3. Lo que NO hacen

- **No garantizan nada entre las dos máquinas**: si un proyecto usa 4661 en tu PC y 3016 en el
  servidor, está bien; no hay un número "global" por proyecto.
- **El servidor no reserva puertos**: `alta` dos veces seguidas para dos proyectos nuevos sugiere
  el mismo número. Crear el `.env` del primero antes de pedir el del segundo.
- **No miran el Tunnel de Cloudflare.** Cambiar un puerto obliga a cambiar el `service:` de su
  ruta en el `ingress` (Runbook de proyecto nuevo, Fase B).
- **Solo conoce la convención.** Ve todos los contenedores del host y los `.env` de
  `env-backups/<repo>/`; un proyecto desplegado a mano, con su `.env` en otro lado y detenido,
  no lo ve hasta que levanta.
