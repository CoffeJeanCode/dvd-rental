#!/usr/bin/env bash
# =====================================================================
# Ejecuta la solución completa y guarda las evidencias en resultados/.
#
# Modo psql   (GitHub Codespaces / cualquier equipo con psql): se usa cuando
#             PGHOST está definido o no hay docker. Conexión por variables
#             PGHOST, PGPORT, PGUSER, PGPASSWORD, PGDATABASE (dvdrental).
# Modo docker (equipo local): psql dentro del contenedor $CONTENEDOR.
#
# Uso:  bash ejecutar_todo.sh
# =====================================================================
set -u
CONTENEDOR="${CONTENEDOR:-pg_dvdrental}"
export PGDATABASE="${PGDATABASE:-dvdrental}"
export PGUSER="${PGUSER:-postgres}"
DIR="$(cd "$(dirname "$0")" && pwd)"
SQL="$DIR/sql"
OUT="$DIR/resultados"
mkdir -p "$OUT"

if [ -n "${PGHOST:-}" ] || ! command -v docker >/dev/null 2>&1; then
  MODO=psql
else
  MODO=docker
fi
echo "Modo de ejecución: $MODO"

psql_run() {   # $1 = archivo, $2 = ON_ERROR_STOP (1/0), $3 = salida
  if [ "$MODO" = psql ]; then
    psql -X -v ON_ERROR_STOP="$2" -e -f "$SQL/$1" > "$OUT/$3" 2>&1
  else
    docker exec -i "$CONTENEDOR" sh -c "psql -X -U $PGUSER -d $PGDATABASE -v ON_ERROR_STOP=$2 -e 2>&1" < "$SQL/$1" > "$OUT/$3"
  fi
}

echo "0) Esperando a PostgreSQL y a la base $PGDATABASE"
for i in $(seq 1 60); do
  if [ "$MODO" = psql ]; then
    psql -X -tAc "SELECT count(*) FROM public.rental" >/dev/null 2>&1 && break
  else
    docker exec "$CONTENEDOR" psql -X -U "$PGUSER" -d "$PGDATABASE" -tAc "SELECT count(*) FROM public.rental" >/dev/null 2>&1 && break
  fi
  sleep 2
done

echo "1) Instalación (reinicia solo el esquema campana)"
for f in 00_reset 01_esquema 02_funciones 03_triggers 04_procedimientos 05_vistas 06_config_campana 07_datos_prueba; do
  psql_run "$f.sql" 1 "$f.txt" || { echo "   FALLÓ $f (ver resultados/$f.txt)"; exit 1; }
  echo "   ok $f"
done

echo "2) Escenarios"
psql_run 08_escenarios.sql 0 08_escenarios.txt && echo "   ok 08_escenarios"

echo "3) Concurrencia: dos sesiones simultáneas + monitor"
psql_run 09a_concurrencia_sesion_A.sql 0 09a_sesion_A.txt &
PID_A=$!
psql_run 09b_concurrencia_sesion_B.sql 0 09b_sesion_B.txt &
PID_B=$!
psql_run 09c_concurrencia_monitor.sql 0 09c_monitor.txt &
PID_C=$!
wait $PID_A $PID_B $PID_C
psql_run 09d_concurrencia_verificacion.sql 0 09d_verificacion.txt && echo "   ok concurrencia"

echo "4) Reportes"
psql_run 10_reportes.sql 0 10_reportes.txt && echo "   ok 10_reportes"

echo "5) Cierre"
psql_run 11_cierre.sql 0 11_cierre.txt && echo "   ok 11_cierre"
echo "Evidencias en $OUT"
