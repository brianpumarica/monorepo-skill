# Deployment Environment Profile

Hechos del entorno real donde se despliega. El agente los da por ciertos y **no vuelve a
preguntarlos**: son la mitad de las decisiones que de otro modo terminarían en una pregunta obvia
(SKILL.md §3).

> [!IMPORTANT]
> **Los campos son fijos; los valores son de cada operador.** Esta skill es pública: lo que se
> versiona acá son *placeholders*. Los valores reales —dominios, nombre del runner, usuarios,
> rutas del servidor— van en el `AGENTS.md` del proyecto (repositorio privado) o en un
> `deployment-profile.local.md` ignorado por git. Publicar el dominio de una terminal web, el
> nombre del runner y la ruta exacta del almacén de `.env` es entregarle a cualquier escáner el
> mapa de la infra a cambio de nada.

---

## 1. Plantilla del perfil

Copiar esta tabla al `AGENTS.md` del proyecto y completarla una sola vez.

| Campo | Valor | Notas |
| :--- | :--- | :--- |
| **Alcance del runner** | `<organización \| cuenta personal>` | Si es organización, un repo creado en la cuenta personal **no ve el runner**: el job queda `Queued` para siempre. Transferirlo antes del primer deploy (ci-cd §5.1) |
| **Nombre del runner** | `<nombre-del-runner>` | Servicio `actions.runner.<org>.<runner>.service` |
| **Etiquetas del runner** | `[self-hosted, linux, <arch>]` | Tienen que coincidir con el `runs-on` del workflow |
| **Canal de acceso al servidor** | `<SSH \| terminal web \| ninguno>` | Si es terminal web de copiar/pegar: no hay transferencia de archivos; para traer un volcado, `database-lifecycle.md` §7. Si la terminal web corre en el mismo túnel de Cloudflare, reiniciar el servicio corta momentáneamente el WebSocket ("Press enter to reconnect"): presionar Enter tras 2 segundos para reconectar. |
| **Verificación desde el repo** | `gh` CLI autenticado | Canal preferido para PRs, estado del runner y seguimiento de deploys — antes que la web y antes que la terminal del servidor |
| **Host compartido** | `<sí \| no>` | Si es sí, aplican las prohibiciones de §2 |
| **Exposición pública** | `<Cloudflare Tunnel \| reverse proxy \| puertos abiertos>` | Patrón de dominios: `<proyecto>.<dominio>` y `api-<proyecto>.<dominio>`. **Regla Cloudflare:** usar SIEMPRE guion (`api-<proyecto>`), nunca dos puntos (`api.<proyecto>`), ya que Universal SSL gratuito solo cubre comodines de un solo nivel (`*.<dominio>`); dos puntos causan fallo de handshake TLS (`SEC_E_ILLEGAL_MESSAGE`). |
| **Almacén de entorno** | `<ruta>/<nombre-del-repo>/.env` | Permisos `600`, dueño = usuario del runner. **Una carpeta por repositorio** (ci-cd §5.2) |
| **Ruta de los proyectos** | `<actions-runner/_work/<repo>/<repo>>` | El runner autogestiona el workspace. **No clonar manualmente** en `~/Documents` si el proyecto corre mediante el runner: duplica código y gasta espacio en disco. |
| **Máquina de desarrollo** | `<Windows \| macOS \| Linux>` | En Windows, CRLF es un riesgo real y no teórico: `.gitattributes` obligatorio |

---

## 2. Reglas de host compartido

Aplican cuando el servidor hospeda más de un proyecto a la vez. No son recomendaciones.

| Prohibido | Por qué |
| :--- | :--- |
| `docker system prune` / `docker container prune` | Se lleva contenedores e imágenes de los otros proyectos |
| `docker compose down` sin `-f docker-compose.prod.yml` desde el directorio del proyecto | Actúa sobre lo que Compose cree que es "el proyecto actual" |
| `docker compose down -v` | Borra el volumen de datos productivo. No es un rollback (`database-lifecycle.md` §6) |
| Reusar puertos sin verificar | Colisión silenciosa con otro proyecto ya desplegado |
| Publicar Postgres al host en producción | Expone la base a todo lo que corra en la máquina (`docker-compose-recipes.md` §2) |
| Compose de producción sin rotación de logs | Un proyecto sin rotación llena el disco de todos (`docker-compose-recipes.md` §4.1) |

Antes de asignar los puertos de un proyecto nuevo:

```bash
docker ps --format 'table {{.Names}}\t{{.Ports}}'
```

### 2.1 Poda periódica del host (crontab de root)

El deploy de cada proyecto poda solo sus imágenes (`docker-compose-recipes.md` §4.8). Un
`docker system prune -af --volumes` semanal en el crontab de root, que es la receta común, rompe
esa convivencia aunque corra a una hora tranquila. Esto borra cada vez:

- **Todo contenedor parado** en ese momento (una caída, un deploy a medias, un `docker stop` a
  mano) y, por el `-a`, **su imagen**. Una imagen construida en el servidor no se recupera con un
  `pull`: vuelve recién con otro deploy. Si la imagen es de terceros con `:latest`, el próximo `up`
  baja la versión nueva sin que nadie la haya probado.
- **Todas las imágenes sin contenedor**: las versiones anteriores de cada proyecto, que la poda del
  deploy guarda 30 días.
- **Toda la caché de build**: el próximo build de cada proyecto arranca de cero.
- **Con `--volumes`**: desde Docker 23 solo los volúmenes **anónimos** sin usar (los que tienen
  nombre quedan). Pero un volumen anónimo de un contenedor parado queda sin usar y se va con él.
- Con `> /dev/null 2>&1` no queda registro de qué se borró.

Reemplazo seguro, una línea en el crontab de root:

```cron
0 4 * * 0 /usr/bin/docker image prune -f --filter until=168h >> /var/log/docker-poda.log 2>&1; /usr/bin/docker builder prune -af --filter until=720h >> /var/log/docker-poda.log 2>&1
```

- `image prune` **sin `-a`**: solo imágenes colgadas (`<none>`) de más de 7 días. Nunca una con
  tag, así que un tag puesto a mano (por ejemplo, la versión anterior de un servicio de terceros
  antes de actualizarlo) queda a salvo.
- `builder prune -a --filter until=720h`: la caché de build sin usar hace más de 30 días. No toca
  contenedores ni imágenes.
- Contenedores parados, redes y volúmenes huérfanos no se podan solos: se revisan a mano, uno por
  uno. Para ver qué hay: `docker volume ls --filter dangling=true` y
  `docker ps -a --filter status=exited`.
- Antes de cambiarlo, guardar el crontab: `sudo crontab -l -u root > ~/crontab-root.bak-<fecha>`.
  Después del primer domingo, revisar `/var/log/docker-poda.log` (cada comando termina con
  `Total reclaimed space`).

---

## 3. Dónde corre cada modo

`/inspecciona` se ejecuta **en la máquina de desarrollo**, como los demás modos. El servidor no
tiene agente ni herramientas de IA: es sólo un host de contenedores. El agente trabaja por dos
canales:

- **Directo desde la máquina local:** `gh` para el estado del runner, las corridas y sus logs;
  `curl` contra los dominios públicos.
- **Copiar y pegar:** todo lo que sea `docker` en el servidor — el agente redacta el comando de
  una línea, el operador lo pega y devuelve la salida.
