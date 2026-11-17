# G8 · Avance 4 · Data Mart y ETL (Pentaho + PostgreSQL 16)

ETL del subsistema Aeropuerto y Equipaje: el staging relacional (Unidades 1 y 2) y MongoDB (Unidad 3) se cargan en un Data Mart en PostgreSQL 16 con Pentaho Data Integration 10.2 (el zip de la preparadora).

## Contenido

| Carpeta / archivo | Qué es |
|---|---|
| `docker-compose.yml` | PostgreSQL 16.6 en `localhost:5438` (usuario `postgres`, contraseña `0000`), con las bases `g8_staging` y `g8_datamart` |
| `migrar_staging.sh` + `sql/01_staging_esquema.sql` | Copia las 15 tablas de MySQL (`G8_main`, contenedor `mysql-g8-informe`) a `g8_staging` |
| `sql/02_datamart_ddl.sql` | Tablas vacías del datamart: 6 dimensiones sin FK y 2 hechos con todas las FK |
| `sql/03_preparar_carga.sql` | Lo que ejecuta el primer paso del job: vacía el datamart e inserta los miembros desconocidos (SK 0) |
| `sql/04_verificacion_carga.sql` | Consultas de verificación de la carga |
| `pentaho/t01..t08_*.ktr`, `pentaho/j00_cargar_datamart.kjb` | Transformaciones (una por tabla) y el job que las ejecuta en orden |
| `pentaho/catalogo_aeropuertos.csv` | Nombre, ciudad y estado de los 42 aeropuertos (tercera fuente) |
| `pentaho/generar_etl.py` | Script que genera los `.ktr` y el `.kjb` |
| `pentaho/correr_job.ps1` | Ejecuta el job sin abrir Spoon (Kitchen); rutas de la PC de Luis, ajustarlas |
| `respaldos/g8_datamart.sql` | Respaldo del datamart cargado (`pg_dump`) |
| `punto3_informe.md` | Borrador de la sección 7 del informe (entorno, extracción, transformación, carga) |
| `mediciones_*`, `cruce_*`, `resultados_*.txt` | Auditoría de las fuentes y resultados de cada verificación |
| `mongo_v2/` | Regeneración de las 5 colecciones de MongoDB a partir de maletas reales del staging (aplicada en Atlas el 16/11/2026) |

## Cómo correrlo

1. `docker compose -p avance4_etl up -d` en esta carpeta y crear las bases:
   `docker exec pg-g8-bi psql -U postgres -c "CREATE DATABASE g8_staging;" -c "CREATE DATABASE g8_datamart;"`
2. `bash migrar_staging.sh` (requiere el contenedor MySQL con la base `G8_main`).
3. `docker exec -i pg-g8-bi psql -U postgres -d g8_datamart < sql/02_datamart_ddl.sql`
4. Agregar la cadena de MongoDB Atlas a `%USERPROFILE%\.kettle\kettle.properties` (no se guarda en los `.ktr`):
   `G8_MONGO_URI=mongodb+srv://<usuario>:<clave>@aeropuerto-maletas.<...>.mongodb.net/`
5. Abrir Spoon (`Spoon.bat`), abrir `pentaho/j00_cargar_datamart.kjb` y ejecutarlo. Tarda unos 20 segundos.
6. Verificar con `sql/04_verificacion_carga.sql`: 320 días, 3 regiones, 42 aeropuertos, 801 vuelos, 4 estados, 6 tipos de equipaje, 90.112 maletas y 3.000 incidencias.

Si Spoon muestra el texto en blanco, poner Windows en modo claro.
