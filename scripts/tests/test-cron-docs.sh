#!/usr/bin/env bash
# shellcheck disable=SC2016  # los fixtures son texto con $ literal, no expansiones
# Prueba del paso "Install project cron" de ci-cd-deployment-pipeline.md §2: se EXTRAE del markdown y
# se corre con un crontab falso. Que el cron de un repo se instale una vez, sin sumar los comentarios
# de la plantilla en cada deploy ni tocar las lineas de otros proyectos.
. "$(dirname "$0")/lib.sh"

extraer_md 'mkdir -p "[$]HOME/backups/[$]REPO_NAME"' '^          crontab -l [|] grep' 10 > "$T/paso.sh" \
  || { fail "no pude extraer el paso del deploy"; terminar; exit 1; }

mkdir -p "$T/bin" "$T/home" "$T/ws/scripts"
cat > "$T/bin/crontab" <<'SH'
#!/usr/bin/env bash
case "$1" in -l) cat "$CRON_STATE" 2>/dev/null ;; -) d=$(cat); printf "%s
" "$d" > "$CRON_STATE" ;; esac
SH
chmod +x "$T/bin/crontab"
printf '# Plantilla de crontab (sin el nombre del repo)\n# otro comentario\n0 3 * * * /bin/bash __DIR__/scripts/backup.sh >> $HOME/backups/mi-repo/backup.log 2>&1\n\n0 9 * * * /bin/bash __DIR__/scripts/verificar-backup.sh mi-repo\n' > "$T/ws/scripts/crontab"

# deploy  ->  corre el paso (CRON_STATE es el crontab "instalado")
deploy() {
  (cd "$T/ws" && env PATH="$T/bin:$PATH" HOME="$T/home" REPO_NAME=mi-repo GITHUB_WORKSPACE=/work/mi-repo CRON_STATE="$T/cron.txt" bash "$T/paso.sh") > "$T/salida.txt" 2>&1; ST=$?
}

titulo "instalar el cron del repo"
printf '# comentario del crontab de otro proyecto\n30 3 * * * /bin/bash /work/otro/scripts/backup.sh\n' > "$T/cron.txt"
deploy
igual "sale con 0" 0 "$ST"
igual "instala las 2 lineas del repo" 2 "$(grep -c 'mi-repo' "$T/cron.txt")"
contiene "cambia __DIR__ por el workspace" "$(cat "$T/cron.txt")" '/work/mi-repo/scripts/backup.sh'
no_contiene "no deja __DIR__ sin reemplazar" "$(cat "$T/cron.txt")" '__DIR__'
contiene "la linea de otro proyecto sigue" "$(cat "$T/cron.txt")" '30 3 .*/work/otro/scripts/backup.sh'
no_contiene "los comentarios de la plantilla NO se instalan" "$(cat "$T/cron.txt")" 'Plantilla de crontab|otro comentario'

titulo "idempotente: el segundo deploy deja el crontab igual"
cp "$T/cron.txt" "$T/antes.txt"; deploy; deploy
igual "sale con 0" 0 "$ST"
igual "mismo contenido tras dos deploys mas" "$(cat "$T/antes.txt")" "$(cat "$T/cron.txt")"

titulo "limpia la pila de comentarios que dejaron los deploys viejos"
printf '# Plantilla de crontab (sin el nombre del repo)\n# Plantilla de crontab (sin el nombre del repo)\n# Plantilla de crontab (sin el nombre del repo)\n30 3 * * * /bin/bash /work/otro/scripts/backup.sh\n0 3 * * * /bin/bash /viejo/mi-repo/scripts/backup.sh\n' > "$T/cron.txt"
deploy
igual "sale con 0" 0 "$ST"
igual "queda un solo comentario repetido (no tres)" 1 "$(grep -c 'Plantilla de crontab' "$T/cron.txt")"
igual "la linea vieja del repo se reemplaza (2, no 3)" 2 "$(grep -c 'mi-repo' "$T/cron.txt")"

terminar
