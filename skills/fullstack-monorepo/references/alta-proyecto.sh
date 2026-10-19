#!/usr/bin/env bash
# Alta de un proyecto nuevo, TODO desde la consola de tu maquina de desarrollo: pasa el repo a la
# organizacion del runner, crea y enlaza el proyecto de Vercel y carga los secrets de GitHub.
# NO va dentro de un repo: se instala una vez en el PATH (como `puerto`, ver puertos.md) y se
# corre desde la carpeta del proyecto, que ya tiene `git init` y un remoto en GitHub.
#
#   alta-proyecto.sh --simular        # imprime cada paso y NO ejecuta nada (empezar siempre por aca)
#   alta-proyecto.sh                  # ejecuta los pasos 1 a 3, pidiendo confirmacion antes de CADA
#                                     # accion que sale de tu maquina
#   alta-proyecto.sh --paso 1 --paso 3   # solo esos pasos (1 = organizacion, 2 = Vercel: enlace, Root Directory y desconexion
#                                      #   de la integracion de Git si el repo ya desplegaba por ahi, 3 = secrets)
#   alta-proyecto.sh --verificar      # comprueba la configuracion y el token SIN mostrarlo
#
# Configuracion (nunca va en un repo publico). Se escribe UNA vez en un archivo personal:
#   ~/.config/alta-proyecto.env      (o la ruta de ALTA_CONFIG)
#     ORG_RUNNER=<organizacion duena del runner self-hosted>        (obligatoria)
#     DOMINIO=<dominio publico de tus proyectos, ej. midominio.com>  (obligatoria)
#     VERCEL_TOKEN=<token de Vercel>   MISMO para todos los proyectos; el script lo carga como
#                                      secret de cada repo nuevo (obligatoria para el paso 3)
#     FRONTEND_DIR=frontend            (opcional)
# Lo ya exportado en la terminal tiene prioridad. Solo se leen esas claves; el archivo no se
# ejecuta. Crearlo (pide el token oculto, no queda en el historial; en Git Bash):
#   mkdir -p ~/.config && printf 'ORG_RUNNER=mi-organizacion\nDOMINIO=midominio.com\n' > ~/.config/alta-proyecto.env \
#     && read -rsp "Token de Vercel: " t && printf '\nVERCEL_TOKEN=%s\n' "$t" >> ~/.config/alta-proyecto.env \
#     && chmod 600 ~/.config/alta-proyecto.env; unset t
# Por que un archivo y no una variable de entorno de usuario: la variable la heredan todos los
# procesos que lanzas (cada `npm run dev`, cada script de un paquete de terceros); el archivo solo
# lo lee este script.
#   VERCEL_CMD   como llamar a la CLI de Vercel (default: npx --yes vercel@latest)
#
# Por que NO un secret de la organizacion: en el plan Free de GitHub, los secrets de organizacion
# no llegan a los repos PRIVADOS (aparecen listados pero el job los recibe vacios). Verificado
# en una prueba real: `VERCEL_TOKEN:` vacio en el log y "No existing credentials found".
# El token viaja por stdin a `gh secret set`: no se imprime ni queda en el historial ni en la
# lista de procesos.
set -uo pipefail

SIMULAR=0
VERIFICAR=0
PASOS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --simular) SIMULAR=1 ;;
    --verificar) VERIFICAR=1 ;;
    --paso) shift; PASOS="$PASOS ${1:-}" ;;
    *) echo "Uso: alta-proyecto.sh [--simular|--verificar] [--paso 1|2|3]..." >&2; exit 1 ;;
  esac
  shift
done
[ -n "$PASOS" ] || PASOS="1 2 3"

# Configuracion personal, FUERA de todo repo: ORG_RUNNER, DOMINIO, VERCEL_TOKEN (y FRONTEND_DIR).
# Se lee solo esas claves (el archivo no se ejecuta) y lo ya exportado en la terminal tiene
# prioridad. Crearlo una vez, con el token por entrada oculta (ver la cabecera).
CONFIG=${ALTA_CONFIG:-$HOME/.config/alta-proyecto.env}
if [ -f "$CONFIG" ]; then
  while IFS='=' read -r k v || [ -n "$k" ]; do
    v=${v%$'\r'}; v=${v#\"}; v=${v%\"}; v=${v#\'}; v=${v%\'}
    case "$k" in
      ORG_RUNNER | DOMINIO | VERCEL_TOKEN | FRONTEND_DIR) [ -n "${!k:-}" ] || export "$k=$v" ;;
    esac
  done < "$CONFIG"
fi
FRONTEND_DIR=${FRONTEND_DIR:-frontend}
VERCEL_CMD=${VERCEL_CMD:-npx --yes vercel@latest}

# --verificar: ¿esta bien la configuracion? Nunca imprime el token: solo su largo y si Vercel lo acepta.
if [ "$VERIFICAR" -eq 1 ]; then
  echo "Configuracion: $CONFIG"
  if [ -f "$CONFIG" ]; then echo "   ✅ el archivo existe"; else echo "   ❌ no existe (ver la cabecera del script para crearlo)"; fi
  [ -n "${ORG_RUNNER:-}" ] && echo "   ✅ ORG_RUNNER = $ORG_RUNNER" || echo "   ❌ falta ORG_RUNNER"
  [ -n "${DOMINIO:-}" ] && echo "   ✅ DOMINIO = $DOMINIO" || echo "   ❌ falta DOMINIO"
  if [ -z "${VERCEL_TOKEN:-}" ]; then
    echo "   ❌ falta VERCEL_TOKEN"
  else
    echo "   VERCEL_TOKEN: ${#VERCEL_TOKEN} caracteres$(case "$VERCEL_TOKEN" in *' '*) echo ', ⚠️  contiene espacios: no parece un token' ;; esac)"
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 -H "Authorization: Bearer $VERCEL_TOKEN" https://api.vercel.com/v2/user || true)
    case "$code" in
      200) echo "   ✅ Vercel acepta el token" ;;
      401 | 403) echo "   ❌ Vercel RECHAZA el token (HTTP $code): esta mal pegado, vencio o fue revocado" ;;
      *) echo "   ⚠️  No se pudo comprobar con Vercel (HTTP ${code:-sin respuesta})" ;;
    esac
  fi
  command -v gh >/dev/null && gh auth status >/dev/null 2>&1 && echo "   ✅ gh con sesion" || echo "   ❌ gh sin sesion"
  exit 0
fi

die() { echo "❌ $*" >&2; exit 1; }
paso() { echo; echo "━━ $* ━━"; }
quiere() { case " $PASOS " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# Pregunta antes de cada accion que sale de la maquina. En --simular nunca ejecuta.
confirmar() {
  if [ "$SIMULAR" -eq 1 ]; then echo "   [simulacion] $1"; return 1; fi
  read -r -p "   ¿$1? [s/N] " r
  [ "$r" = s ] || [ "$r" = S ] || { echo "   (omitido)"; return 1; }
}

json() { node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log(eval("(j)=>"+process.argv[1])(JSON.parse(s))))' "$1"; }

# --- Antes de nada: que este todo lo necesario (no cambia nada) ----------------
paso "0. Verificacion previa"
[ -n "${ORG_RUNNER:-}" ] || die "Falta ORG_RUNNER (la organizacion duena del runner)."
[ -n "${DOMINIO:-}" ] || die "Falta DOMINIO (el dominio publico de tus proyectos)."
command -v gh >/dev/null || die "Falta la CLI de GitHub (gh)."
command -v node >/dev/null || die "Falta Node (se usa para leer JSON)."
[ "$SIMULAR" -eq 1 ] || gh auth status >/dev/null 2>&1 || die "gh no tiene sesion: gh auth login"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Esta carpeta no es un repositorio git."

if repo_json=$(gh repo view --json name,owner 2>/dev/null); then
  NOMBRE=$(printf '%s' "$repo_json" | json 'j.name')
  DUENO=$(printf '%s' "$repo_json" | json 'j.owner.login')
else
  [ "$SIMULAR" -eq 1 ] || die "Este repo no tiene remoto en GitHub (crearlo: gh repo create)."
  NOMBRE=$(basename "$PWD"); DUENO="(sin remoto)"
fi
[ -d "$FRONTEND_DIR" ] || echo "ℹ️  No existe ./$FRONTEND_DIR: el Root Directory de Vercel quedara en la raiz (ajustar FRONTEND_DIR)."
echo "   proyecto: $NOMBRE   dueño actual: $DUENO   organizacion del runner: $ORG_RUNNER   pasos: $PASOS"
REPO="$ORG_RUNNER/$NOMBRE"

# --- 1. Transferir a la organizacion del runner --------------------------------
if quiere 1; then
  paso "1. Repo en la organizacion del runner"
  if [ "$DUENO" = "$ORG_RUNNER" ]; then
    echo "   ✅ Ya esta en $ORG_RUNNER."
  else
    echo "   Sin esto el job de la Pi queda 'Queued' para siempre y sin ningun mensaje (ci-cd §5.1)."
    if confirmar "transferir $DUENO/$NOMBRE a la organizacion $ORG_RUNNER"; then
      gh api -X POST "repos/$DUENO/$NOMBRE/transfer" -f "new_owner=$ORG_RUNNER" >/dev/null \
        || die "La transferencia fallo (¿sos owner de la organizacion?)."
      git remote set-url origin "https://github.com/$REPO.git"
      echo "   ✅ Transferido. Remoto actualizado a $REPO."
    fi
  fi
fi

# --- 2. Proyecto de Vercel -----------------------------------------------------
if quiere 2; then
  paso "2. Proyecto de Vercel"
  if confirmar "crear y enlazar el proyecto '$NOMBRE' en Vercel"; then
    $VERCEL_CMD link --yes --project "$NOMBRE" || die "vercel link fallo (¿iniciaste sesion? npx vercel login)."
    [ -f .vercel/project.json ] || die "No aparecio .vercel/project.json."
    echo "   ✅ Enlazado (projectId y orgId quedaron en .vercel/project.json)."
    grep -qxF '.vercel' .gitignore 2>/dev/null || { echo '.vercel' >> .gitignore; echo "   .vercel agregado a .gitignore."; }

    # `vercel api` usa la sesion de la propia CLI: no hace falta ningun token en el entorno.
    # MSYS_NO_PATHCONV evita que Git Bash reescriba "/v9/..." como una ruta de archivo.
    PROJECT_ID=$(node -p 'require("./.vercel/project.json").projectId')
    ORG_ID=$(node -p 'require("./.vercel/project.json").orgId')
    q=""; case "$ORG_ID" in team_*) q="?teamId=$ORG_ID" ;; esac
    # Imprime un campo del JSON que devuelve la API (vacio si no existe o no hay JSON).
    vercel_api() {
      MSYS_NO_PATHCONV=1 $VERCEL_CMD api "$@" 2>/dev/null \
        | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const v=process.argv[1].split(".").reduce((o,k)=>o&&o[k],JSON.parse(s.slice(s.indexOf("{"))));console.log(v===undefined||v===null?"":v)}catch(e){}})' "$FIELD"
    }

    # `link --yes` NO fija el Root Directory. Sin esto, `vercel build` corre en la raiz del
    # monorepo y no encuentra la app (pitfall 2 de ci-cd §4).
    if [ -d "$FRONTEND_DIR" ]; then
      if confirmar "fijar Root Directory = $FRONTEND_DIR en el proyecto de Vercel"; then
        RD=$(FIELD=rootDirectory vercel_api "/v9/projects/$PROJECT_ID$q" -X PATCH -F "rootDirectory=$FRONTEND_DIR")
        if [ "$RD" = "$FRONTEND_DIR" ]; then echo "   ✅ Root Directory = $FRONTEND_DIR"
        else echo "   ⚠️  No se pudo fijar: ponerlo a mano en Vercel > $NOMBRE > Settings > General > Root Directory."; fi
      fi
    fi

    # Un repo que YA desplegaba por la integracion de Git de Vercel sigue compilando cada push por
    # esa via, en paralelo al workflow: checks rojos de Vercel en cada PR y, en el plan Hobby,
    # bloqueos por commits con coautores (ci-cd §3). El deploy va por la CLI desde el workflow, asi
    # que la integracion se desconecta (`DELETE /v9/projects/<id>/link`). Sin integracion, no hace nada.
    GIT_LINK=$(FIELD=link.type vercel_api "/v9/projects/$PROJECT_ID$q")
    if [ -z "$(FIELD=id vercel_api "/v9/projects/$PROJECT_ID$q")" ]; then
      echo "   ⚠️  No se pudo consultar el proyecto en Vercel: revisar a mano Settings > Git."
    elif [ -n "$GIT_LINK" ]; then
      if confirmar "desconectar la integracion de Git de Vercel ($GIT_LINK) del proyecto: el deploy va por la CLI"; then
        vercel_api "/v9/projects/$PROJECT_ID/link$q" -X DELETE >/dev/null
        if [ -z "$(FIELD=link.type vercel_api "/v9/projects/$PROJECT_ID$q")" ]; then echo "   ✅ Integracion de Git desconectada."
        else echo "   ⚠️  No se pudo desconectar: Vercel > $NOMBRE > Settings > Git > Disconnect."; fi
      fi
    else
      echo "   ✅ El proyecto no tiene la integracion de Git de Vercel conectada: nada que desconectar."
    fi
  fi
fi

# --- 3. Secrets de GitHub ------------------------------------------------------
if quiere 3; then
  paso "3. Secrets de GitHub ($REPO)"
  if [ -f .vercel/project.json ] || [ "$SIMULAR" -eq 1 ]; then
    if confirmar "cargar VERCEL_PROJECT_ID, VERCEL_ORG_ID, API_URL y SITE_URL en $REPO"; then
      PROJECT_ID=$(node -p 'require("./.vercel/project.json").projectId')
      ORG_ID=$(node -p 'require("./.vercel/project.json").orgId')
      printf '%s' "$PROJECT_ID" | gh secret set VERCEL_PROJECT_ID --repo "$REPO"
      printf '%s' "$ORG_ID" | gh secret set VERCEL_ORG_ID --repo "$REPO"
      printf '%s' "https://api-$NOMBRE.$DOMINIO" | gh secret set API_URL --repo "$REPO"
      printf '%s' "https://$NOMBRE.vercel.app" | gh secret set SITE_URL --repo "$REPO"
    fi
    # El token es el mismo para todos: se carga como secret DEL REPO (un secret de organizacion
    # no llega a repos privados en el plan Free, ver la cabecera).
    if [ -n "${VERCEL_TOKEN:-}" ]; then
      if confirmar "cargar VERCEL_TOKEN en $REPO (desde tu variable de entorno)"; then
        printf '%s' "$VERCEL_TOKEN" | gh secret set VERCEL_TOKEN --repo "$REPO"
      fi
    elif gh secret list --repo "$REPO" 2>/dev/null | grep -q '^VERCEL_TOKEN'; then
      echo "   ✅ VERCEL_TOKEN ya esta cargado en $REPO."
    else
      echo "   ⚠️  Falta VERCEL_TOKEN: ni en tu entorno ni cargado en el repo. Definirlo (ver la cabecera) o:"
      echo "      gh secret set VERCEL_TOKEN --repo $REPO     # pide el valor oculto"
    fi
    [ "$SIMULAR" -eq 1 ] || gh secret list --repo "$REPO"
  else
    echo "   (omitido: falta .vercel/project.json; correr el paso 2)"
  fi
fi

# --- 4. Lo que sigue en la Pi (no se automatiza desde aca) ---------------------
paso "Siguientes pasos"
cat <<EOF
   a. Primer push (falla A PROPOSITO en el paso del .env, pero deja el repo en el runner):
        git push origin HEAD
   b. En la Pi, elegir puertos y horario libres (puertos.md §2):
        sudo bash /home/github-runner/actions-runner/_work/$NOMBRE/$NOMBRE/scripts/chequear-host.sh alta
   c. En la Pi, crear el .env (genera los secretos) y poner esos puertos:
        sudo bash /home/github-runner/actions-runner/_work/$NOMBRE/$NOMBRE/scripts/crear-env.sh
   d. Ruta en Cloudflare Tunnel: api-$NOMBRE.$DOMINIO -> http://localhost:<BACKEND_HOST_PORT>
        (ci-cd §3.1 Fase B paso 4; guion, nunca punto). Para que el deploy la registre solo,
        agregar al .env del servidor:  TUNEL_HOST=api-$NOMBRE.$DOMINIO  (sin esa variable el paso no corre)
   e. Volver a correr el deploy:
        gh workflow run deploy.yml --repo $REPO --ref <rama>  &&  gh run watch --repo $REPO
EOF
