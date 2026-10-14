# Clúster Citus del G8

Coordinador + 3 workers en Docker, con la tabla fragmentadora `region` ya distribuida. Hecho con los pasos de la Prepa 4.2 (instalación de Citus).

Cubre esta parte del Avance 2: Docker y workers, scripts de inicialización, levantamiento de los contenedores, registro de los workers en el coordinador, verificación del registro, tabla fragmentadora y estrategia de partición.

**Estado:** levantado y verificado el 2026-10-13. PostgreSQL 16.6 y Citus 12.1.6.

## Resultado

| Región | `id` | Shard | Worker |
|---|---|---|---|
| ESTE | 1 | `region_102008` | `citus_worker_1` |
| CENTRAL | 3 | `region_102009` | `citus_worker_2` |
| OESTE | 2 | `region_102010` | `citus_worker_3` |

Es la correspondencia que pide la tabla de arquitectura del enunciado. Esta tabla es el inicio de la bitácora de shards: cada tabla que se distribuya después agrega sus tres filas.

- **Tabla fragmentadora:** `region(id, nombre_region)`.
- **Estrategia de partición:** hash sobre `id`, 3 shards, uno por worker, factor de replicación 1. Las demás tablas se distribuirán por `id_region` con `colocate_with => 'region'`.

## Archivos

| Archivo | Qué es |
|---|---|
| `docker-compose.yml` | Los 4 servicios, como en la prepa |
| `init/init_citus/coord/00_enable_citus.sql` | Habilita Citus en el coordinador al crear el contenedor |
| `init/init_citus/worker/00_enable_citus.sql` | Lo mismo en cada worker |
| `sql/plan4_coordinador.sql` | Los comandos en orden, para pegar en el coordinador |
| `resultados_plan4.txt` | Salidas reales de una corrida completa desde cero |

## Cómo repetirlo desde cero (para las capturas)

Todo se corre en esta carpeta. El primer comando **borra el clúster y sus datos**; en una PC donde nunca se levantó, se empieza por el segundo.

```bash
docker-compose down -v
```

```bash
docker-compose up -d
```

```bash
docker exec -it citus_coordinator psql -U postgres -d coorddb
```

Ya dentro del coordinador, pegar los bloques de `sql/plan4_coordinador.sql` uno por uno:

| Paso | Qué se captura |
|---|---|
| 1 | `\dx` con la extensión `citus` |
| 2 | Los tres `master_add_node` |
| 3 | `master_get_active_worker_nodes()` y `pg_dist_node` con los 3 workers |
| 4 | Creación y carga de `region`; todavía no aparece en `pg_dist_partition` |
| 5 | `SET citus.shard_count = 3` y `create_distributed_table` |
| 6 | `partmethod = h` y qué shard quedó en qué worker |
| 7 | `SELECT * FROM region` en el coordinador: 3 filas |
| 8 | El shard de cada worker: 1 fila |

El paso 8 se corre fuera de psql (salir con `\q`):

```bash
docker exec -it citus_worker_1 psql -U postgres -d coorddb -c "SELECT * FROM region_102008;"
```

```bash
docker exec -it citus_worker_2 psql -U postgres -d coorddb -c "SELECT * FROM region_102009;"
```

```bash
docker exec -it citus_worker_3 psql -U postgres -d coorddb -c "SELECT * FROM region_102010;"
```

Para la captura del compose y de la estructura de carpetas basta abrir esta carpeta en VS Code.

## Uso diario

```bash
docker-compose stop
```

```bash
docker-compose start
```

`stop` y `start` conservan los datos. `down -v` los borra.

## Lo que no es idéntico a la prepa

| Diferencia | Por qué |
|---|---|
| `PGPASSWORD: "0000"` en cada servicio | Sin esa línea, después de un `stop` / `start` toda consulta distribuida falla con `fe_sendauth: no password supplied`. Probado en las dos formas |
| La columna se llama `nombre_region` y lleva el `CHECK` de la Unidad 1 | Es el nombre y la restricción que exige el enunciado para la tabla común `region`. En la prepa se llama `region` |
| Los ids son ESTE = 1, OESTE = 2, CENTRAL = 3 | Con 3 shards, Citus manda el id 1 al worker 1, el 3 al 2 y el 2 al 3 (igual que en la prepa). Así cada región cae en el worker que pide el enunciado |
| Sin el volumen `pgdata_maxi` | En la prepa era un experimento sin borrar |
| `SELECT * FROM region` desde un worker devuelve las 3 filas | En el video dio error; en la lámina dice que se ven las 3. Aquí funciona |

## Antes de cargar el respaldo de la Unidad 1

El respaldo trae su propia tabla `region`. Como se restaura con `pg_restore --clean`, **borraría la tabla distribuida** de este clúster. El `.dump` debe hacerse sin `region` y sin las FK de `aeropuerto` y `hub` hacia ella.

Después, cada tabla se distribuye por `id_region` (columna que debe formar parte de su clave primaria) con `colocate_with => 'region'`.
