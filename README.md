# Campaña de Halloween en DVD Rental — PL/pgSQL

Solución de la actividad evaluativa: PostgreSQL prepara destinatarios y mensajes personalizados por correo y WhatsApp para promocionar «Colony: Zona Cero» y «The Others». Cumple las 12 reglas y demuestra los 9 escenarios mínimos, sin alterar el modelo original de DVD Rental.

La explicación completa (diseño, criterios, resultados y límites) está en **[docs/DOCUMENTO.md](docs/DOCUMENTO.md)**.

## Ejecutar en GitHub Codespaces

1. En GitHub: **Code → Codespaces → Create codespace on main**.
2. Espera a que termine la construcción. El contenedor `db` se construye con el [`Dockerfile`](Dockerfile) (PostgreSQL 16) y restaura `dvdrental` automáticamente en el primer arranque.
3. En la terminal del Codespace:

```bash
bash ejecutar_todo.sh
```

El script instala el esquema `campana`, corre todos los escenarios, lanza dos sesiones simultáneas, genera los reportes y cierra la campaña. Las evidencias quedan en `resultados/`. Se puede repetir las veces que haga falta: solo reinicia el esquema `campana`.

Para trabajar a mano, `psql` ya está conectado a `dvdrental` (variables `PG*` del contenedor). También está la extensión SQLTools con la conexión `dvdrental`.

```bash
psql -c "SELECT * FROM campana.v_resumen_lote"
```

### Demostración de concurrencia en clase (dos terminales)

| Terminal 1 | Terminal 2 (dentro de los 6 s siguientes) |
| --- | --- |
| `psql -f sql/09a_concurrencia_sesion_A.sql` | `psql -f sql/09b_concurrencia_sesion_B.sql` |

Después ejecuta `psql -f sql/09d_concurrencia_verificacion.sql`. Para repetir la demostración desde cero, ejecuta antes los scripts `00` a `07` (o `bash ejecutar_todo.sh`).

## Ejecutar en un equipo local con Docker

```bash
docker build -t dvdrental-db .
docker run -d --name pg_dvdrental -e POSTGRES_PASSWORD=postgres -p 5432:5432 dvdrental-db
bash ejecutar_todo.sh
```

Sin `PGHOST` definido y con Docker disponible, el script ejecuta `psql` dentro del contenedor `pg_dvdrental`.

## Estructura

| Ruta | Contenido |
| --- | --- |
| `Dockerfile`, `db/` | Imagen PostgreSQL 16 con el respaldo `dvdrental.tar` y el script de restauración |
| `.devcontainer/` | Configuración de Codespaces (servicio `app` con psql y servicio `db`) |
| `sql/00`–`07` | Instalación: esquema, funciones, triggers, procedimientos, vistas, configuración y datos ficticios |
| `sql/08`–`11` | Escenarios, concurrencia, reportes y cierre |
| `resultados/` | Salidas de la última ejecución completa (evidencias) |
| `docs/DOCUMENTO.md` | Documento explicativo |

Los datos de contacto son ficticios (`es_prueba = true`, dominios `.example`). Ningún mensaje preparado debe enviarse.
