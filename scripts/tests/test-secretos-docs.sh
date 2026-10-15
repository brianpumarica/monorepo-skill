#!/usr/bin/env bash
# Pruebas de los fragmentos de shell que viven en ci-cd-deployment-pipeline.md. Se EXTRAEN del
# markdown (no se copian aca): si alguien rompe el texto de la doc, este test falla.
#   1. el paso del deploy que exige secretos reales (REQUIRED_SECRETS + los derivados de .env.example)
#   2. el bucle de inspecciona §6.5 que compara el .env de cada repo contra su plantilla (con las
#      rutas que define el principio del catalogo, §6)
. "$(dirname "$0")/lib.sh"

# ---- 1. paso del deploy -------------------------------------------------------
extraer_md '# Vacio, "admin" o igual al valor de' '^          done$' 10 > "$T/paso.sh" || { fail "no pude extraer el paso del deploy"; terminar; exit 1; }
{ echo 'ENV_STORE=/almacen/.env; REQUIRED_SECRETS="ADMIN_PASSWORD JWT_SECRET POSTGRES_PASSWORD"'; cat "$T/paso.sh"; echo 'echo PASA'; } > "$T/chequeo.sh"

# paso <contenido del .env.example> <contenido del .env>  ->  OUT, ST
paso() {
  mkdir -p "$T/w"; printf '%b' "$1" > "$T/w/.env.example"; printf '%b' "$2" > "$T/w/.env"
  OUT=$(cd "$T/w" && bash "$T/chequeo.sh" 2>&1); ST=$?
}
EJ='ADMIN_PASSWORD=admin\nJWT_SECRET=cambiame\nPOSTGRES_PASSWORD=postgres\nSERVICE_API_KEY=ejemplo-key\nOPTIONAL_API_KEY=\nNEXT_PUBLIC_MAPS_KEY=pub\n'
REAL='ADMIN_PASSWORD=r1\nJWT_SECRET=r2\nPOSTGRES_PASSWORD=r3\nSERVICE_API_KEY=r4\nOPTIONAL_API_KEY=\nNEXT_PUBLIC_MAPS_KEY=pub\n'

titulo "paso del deploy: REQUIRED_SECRETS + derivados de .env.example"
paso "$EJ" "$REAL"
igual "todo real (clave opcional vacia, NEXT_PUBLIC_* igual al ejemplo): pasa" "0 PASA" "$ST ${OUT##*$'\n'}"
paso "$EJ" 'ADMIN_PASSWORD=r1\nJWT_SECRET=r2\nPOSTGRES_PASSWORD=r3\nSERVICE_API_KEY=ejemplo-key\n'
igual "una *_KEY igual al ejemplo: falla" 1 "$ST"
contiene "nombra la variable" "$OUT" 'SERVICE_API_KEY is empty or has an example value'
paso "$EJ" 'ADMIN_PASSWORD=r1\nJWT_SECRET=r2\nPOSTGRES_PASSWORD=r3\nSERVICE_API_KEY=\n'
igual "una *_KEY con valor de ejemplo y vacia en produccion: falla" 1 "$ST"
paso "$EJ" 'ADMIN_PASSWORD=admin\nJWT_SECRET=r2\nPOSTGRES_PASSWORD=r3\nSERVICE_API_KEY=r4\n'
igual "ADMIN_PASSWORD=admin (lista manual): falla" 1 "$ST"
paso "$EJ" 'ADMIN_PASSWORD=r1\nJWT_SECRET=r2\nPOSTGRES_PASSWORD=postgres\nSERVICE_API_KEY=r4\n'
igual "POSTGRES_PASSWORD igual al ejemplo (lista manual): falla" 1 "$ST"
paso "$EJ" 'ADMIN_PASSWORD=r1\nJWT_SECRET=\nPOSTGRES_PASSWORD=r3\nSERVICE_API_KEY=r4\n'
igual "JWT_SECRET vacio: falla" 1 "$ST"
paso 'ADMIN_PASSWORD=admin\r\nJWT_SECRET=cambiame\r\nPOSTGRES_PASSWORD=postgres\r\nSERVICE_API_KEY=ejemplo-key\r\n' 'ADMIN_PASSWORD=r1\nJWT_SECRET=r2\nPOSTGRES_PASSWORD=r3\nSERVICE_API_KEY=ejemplo-key\n'
igual ".env.example con CRLF y .env igual al ejemplo: falla (no se escapa por el CR)" 1 "$ST"
paso 'ADMIN_PASSWORD=admin\r\nJWT_SECRET=cambiame\r\nPOSTGRES_PASSWORD=postgres\r\nSERVICE_API_KEY=ejemplo-key\r\n' 'ADMIN_PASSWORD=r1\nJWT_SECRET=r2\nPOSTGRES_PASSWORD=r3\nSERVICE_API_KEY=r4\n'
igual ".env.example con CRLF y todo real: pasa" 0 "$ST"
paso 'ADMIN_PASSWORD=admin\nJWT_SECRET=cambiame\nPOSTGRES_PASSWORD=postgres\n' 'ADMIN_PASSWORD=r1\nJWT_SECRET=r2\nPOSTGRES_PASSWORD=r3\n'
igual ".env.example sin ninguna *_KEY (el grep sin resultado no mata el paso): pasa" 0 "$ST"

# ---- 2. bucle de inspecciona §6.5 ---------------------------------------------
titulo "inspecciona §6.5: bucle sobre env-backups"
B="$T/gr"
linea=$(grep -E '^for r in \$\(sudo ls "\$\{ENV_BASE:\?\}"\)' "$CICD_MD" | head -1)
[ -n "$linea" ] || { fail "no encontre el bucle de §6.5 en la doc"; terminar; exit 1; }
# Las rutas salen de las variables del principio del catalogo (§6), no van fijas en el bucle.
rutas=$(grep -E '^(RUNNER_WORK|ENV_BASE)=' "$CICD_MD")
igual "las rutas del catalogo estan definidas una vez cada una" 2 "$(printf '%s\n' "$rutas" | grep -c .)"
no_contiene "el bucle no repite rutas fijas" "$linea" '/home/github-runner'
# El home del runner no es legible para el usuario comun: TODO acceso a esa ruta va con sudo, tambien
# la comprobacion de existencia (sin ella el bucle marcaba a todos los repos como "SIN .env.example").
contiene "el bucle comprueba el .env.example con sudo (el home del runner no es legible)" "$linea" 'sudo test -f "\$ex"'
printf '%s\n' "$linea" | sed "s#sudo ##g" > "$T/bucle-solo.sh"
{ printf '%s\n' "$rutas" | sed "s#/home/github-runner#$B#g"; cat "$T/bucle-solo.sh"; } > "$T/bucle.sh"
ws() { mkdir -p "$B/actions-runner/_work/$1/$1" "$B/env-backups/$1"; printf '%b' "$2" > "$B/actions-runner/_work/$1/$1/.env.example"; printf '%b' "$3" > "$B/env-backups/$1/.env"; }
ws solo-key 'API_KEY=cambiame\nPORT=3000\n' 'API_KEY=cambiame\nPORT=3000\n'
ws normal 'JWT_SECRET=x\nADMIN_PASSWORD=admin\nOPT_API_KEY=\n' 'JWT_SECRET=real\nADMIN_PASSWORD=admin\nOPT_API_KEY=\n'
ws publico 'NEXT_PUBLIC_MAPS_KEY=pub\nVITE_APP_KEY=v\nJWT_SECRET=x\n' 'JWT_SECRET=real\nNEXT_PUBLIC_MAPS_KEY=pub\nVITE_APP_KEY=v\n'
ws callado 'PORT=1\n' 'PORT=1\n'
mkdir -p "$B/env-backups/sin-ws"; printf 'JWT_SECRET=real\n' > "$B/env-backups/sin-ws/.env"
OUT=$(bash "$T/bucle.sh" 2>&1)
contiene "un proyecto cuyo unico secreto es API_KEY ya NO sale mudo" "$OUT" '^solo-key: API_KEY EJEMPLO$'
contiene "JWT_SECRET real: OK" "$OUT" '^normal: JWT_SECRET OK$'
contiene "ADMIN_PASSWORD=admin: EJEMPLO" "$OUT" '^normal: ADMIN_PASSWORD EJEMPLO$'
contiene "clave opcional vacia: VACIO (no es un hallazgo critico)" "$OUT" '^normal: OPT_API_KEY VACIO$'
no_contiene "NEXT_PUBLIC_* y VITE_* no se comparan" "$OUT" 'NEXT_PUBLIC|VITE_'
contiene "avisa cuando falta el .env.example del workspace" "$OUT" '^sin-ws: SIN \.env\.example'
no_contiene "sin ninguna variable secreta no imprime nada (el aviso de la doc: eso no es 'sano')" "$OUT" '^callado'

titulo "inspecciona §6.5: sin pegar las rutas, el bucle se corta"
OUT=$(env -u RUNNER_WORK -u ENV_BASE bash "$T/bucle-solo.sh" 2>&1)
contiene "dice que falta la variable" "$OUT" 'ENV_BASE: parameter null or not set'
no_contiene "no da un resultado falso" "$OUT" 'SIN \.env\.example|OK$|EJEMPLO$'
OUT=$(env -u RUNNER_WORK ENV_BASE="$B/env-backups" bash "$T/bucle-solo.sh" 2>&1)
contiene "con ENV_BASE pero sin RUNNER_WORK: dice que falta" "$OUT" 'RUNNER_WORK: parameter null or not set'
no_contiene "y no marca a todos como SIN .env.example" "$OUT" 'SIN \.env\.example'

terminar
