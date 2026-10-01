# G8 · Aeropuerto y Equipaje (MySQL 8.0)

Base de datos del Avance 1 de Bases de Datos II, con los volúmenes que usa el informe.

## Cómo levantarla

```bash
docker compose down -v
docker compose up -d --build
```

`down -v` borra el volumen anterior: MySQL solo ejecuta los scripts de `docker-entrypoint-initdb.d` cuando la base se crea desde cero. La primera carga tarda uno o dos minutos.

Conexión: `localhost:3307`, usuario `root`, base `G8`. La contraseña está en `docker-compose.yml`.

## Qué se carga

| Script | Contenido |
|---|---|
| `01_esquema.sql` | Las 15 tablas, con las correcciones de integridad (FK de movimientos a equipaje, precio con céntimos, zonas del pase como regiones, check_in a pasajero, NOT NULL y CHECK). |
| `02_datos.sql` | Datos sintéticos coherentes. Es determinista: siempre genera los mismos datos. |
| `03_indices.sql` | Los 6 índices del informe más `idx_mov_evento_fecha` para la consulta de optimización. |

| Tabla | Filas |
|---|---|
| movimiento_equipaje | 300.000 |
| boleto | 200.000 |
| pasajero, reserva_pnr, equipaje | 100.000 cada una |
| vuelo_programado, vuelo_operado | 50.000 cada una |
| tarifa | 50 |
| aeropuerto / hub / region | 42 / 10 / 3 |

check_in, pase_abordaje, asignacion_puerta y segmento_boleto quedan vacías por ahora.

Reglas de coherencia que respetan los datos:

- Ningún evento de un boleto es anterior a su emisión, y los boletos USADO ya viajaron.
- `tarifa_base` es el precio de la tarifa del boleto, y la tarifa corresponde a su clase (Y, J, F).
- Los vuelos aterrizan después de despegar, y todos los vuelos operados ya ocurrieron.
- Solo los boletos USADO tienen equipaje, y cada maleta es del pasajero del boleto.
- Cada maleta tiene 3 eventos en orden cronológico (registro, carga o incidencia, entrega).
- El PNR de cada movimiento es la reserva del mismo pasajero.

## Mediciones

`mediciones/consultas_informe.sql` corre todas las consultas del informe (volúmenes, `information_schema`, `SHOW INDEX`, EXPLAIN y EXPLAIN ANALYZE con y sin cada índice, `innodb_index_stats` y la consulta de optimización). Los resultados de una corrida están en `mediciones/resultados.txt`.

```bash
docker exec -i mysql-local sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot -t G8' < mediciones/consultas_informe.sql
```

`G8_completo.sql`, en la raíz, es el respaldo anterior (5.000 boletos y sin movimientos). Ya no se carga.
