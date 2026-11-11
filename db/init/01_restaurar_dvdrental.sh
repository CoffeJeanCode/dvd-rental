#!/bin/bash
# Crea la base dvdrental y restaura el respaldo original (solo en el primer arranque).
set -e
echo ">> Restaurando dvdrental desde /seed/dvdrental.tar"
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -c "CREATE DATABASE dvdrental"
pg_restore --username "$POSTGRES_USER" --dbname dvdrental --no-owner /seed/dvdrental.tar
echo ">> dvdrental restaurada"
