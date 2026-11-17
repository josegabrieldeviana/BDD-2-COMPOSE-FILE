#!/usr/bin/env bash
# =====================================================================
# G8 · Avance 4 · Migración MySQL 8.0 (G8_main) -> PostgreSQL 16 (g8_staging)
# Copia tabla por tabla en el orden de las FK: SELECT en MySQL -> COPY en PostgreSQL.
# Contenedores: mysql-g8-informe (3308) y pg-g8-bi (5438). Solo lee de MySQL.
# Uso: bash migrar_staging.sh   (desde la carpeta avance4_etl)
# =====================================================================
set -euo pipefail
MY='docker exec mysql-g8-informe sh -c'
PG='docker exec -i pg-g8-bi psql -U postgres -d g8_staging -v ON_ERROR_STOP=1 -q'

$PG < sql/01_staging_esquema.sql

TABLAS="region aeropuerto hub pasajero tarifa check_in vuelo_programado vuelo_operado
        asignacion_puerta pase_abordaje boleto reserva_pnr equipaje movimiento_equipaje segmento_boleto"

for t in $TABLAS; do
  $MY "MYSQL_PWD=\"\$MYSQL_ROOT_PASSWORD\" mysql -uroot -B -N --raw -e 'SELECT * FROM G8_main.$t'" \
    | $PG -c "\\copy $t FROM STDIN WITH (FORMAT text, NULL 'NULL')"
  printf '%-22s mysql=%-8s postgres=%s\n' "$t" \
    "$($MY "MYSQL_PWD=\"\$MYSQL_ROOT_PASSWORD\" mysql -uroot -B -N -e 'SELECT COUNT(*) FROM G8_main.$t'")" \
    "$(docker exec pg-g8-bi psql -U postgres -d g8_staging -tAc "SELECT COUNT(*) FROM $t")"
done
docker exec pg-g8-bi psql -U postgres -d g8_staging -qc "ANALYZE;"
