# PostgreSQL 16 con la base DVD Rental ya restaurada al primer arranque.
# Lo usa .devcontainer/docker-compose.yml (servicio "db") en GitHub Codespaces,
# y también se puede usar solo:
#   docker build -t dvdrental-db .
#   docker run -d --name pg_dvdrental -e POSTGRES_PASSWORD=postgres -p 5432:5432 dvdrental-db
FROM postgres:16

ENV POSTGRES_USER=postgres \
    POSTGRES_PASSWORD=postgres \
    POSTGRES_DB=postgres

# Respaldo original entregado con la actividad (dvdrental.zip -> dvdrental.tar)
COPY db/dvdrental.tar /seed/dvdrental.tar
# Los scripts de /docker-entrypoint-initdb.d se ejecutan solo cuando el volumen de datos está vacío
COPY db/init/01_restaurar_dvdrental.sh /docker-entrypoint-initdb.d/01_restaurar_dvdrental.sh
RUN chmod 755 /docker-entrypoint-initdb.d/01_restaurar_dvdrental.sh

EXPOSE 5432
