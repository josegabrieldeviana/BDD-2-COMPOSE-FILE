-- =====================================================================
-- Plan 4 - Clúster Citus del G8 (Citus 12.1 / PostgreSQL 16)
-- Se pega bloque por bloque dentro del coordinador:
--   docker exec -it citus_coordinator psql -U postgres -d coorddb
-- Requiere: docker-compose up -d ya ejecutado.
-- =====================================================================

-- ---------------------------------------------------------------------
-- PASO 1. Confirmar que la extensión Citus quedó habilitada
-- ---------------------------------------------------------------------
\dx

-- ---------------------------------------------------------------------
-- PASO 2. Registrar los 3 nodos worker en el coordinador
-- ---------------------------------------------------------------------
-- Worker 1
SELECT master_add_node('citus_worker_1', 5432);
-- Worker 2
SELECT master_add_node('citus_worker_2', 5432);
-- Worker 3
SELECT master_add_node('citus_worker_3', 5432);

-- ---------------------------------------------------------------------
-- PASO 3. Verificar el registro de los workers
-- ---------------------------------------------------------------------
SELECT * FROM master_get_active_worker_nodes();

SELECT nodeid, groupid, nodename, nodeport, noderole, isactive
FROM pg_dist_node
ORDER BY nodeid;

-- ---------------------------------------------------------------------
-- PASO 4. Tabla fragmentadora: region
-- ---------------------------------------------------------------------
-- Los ids no van en orden alfabético a propósito: con 3 shards, Citus
-- manda el id 1 al worker 1, el 3 al worker 2 y el 2 al worker 3.
CREATE TABLE region (
    id INT PRIMARY KEY,
    nombre_region VARCHAR(10) NOT NULL,
    CONSTRAINT chk_region_valida CHECK (nombre_region IN ('ESTE', 'CENTRAL', 'OESTE'))
);

INSERT INTO region (id, nombre_region)
VALUES
    (1, 'ESTE'),
    (2, 'OESTE'),
    (3, 'CENTRAL');

-- Todavía no está distribuida: no aparece en pg_dist_partition
SELECT logicalrelid::regclass, partmethod
FROM pg_dist_partition
WHERE logicalrelid = 'region'::regclass;

-- ---------------------------------------------------------------------
-- PASO 5. Estrategia de partición: hash por id, 3 shards (uno por worker)
-- ---------------------------------------------------------------------
SET citus.shard_count = 3;

SELECT create_distributed_table('region', 'id');

-- ---------------------------------------------------------------------
-- PASO 6. Verificar que la tabla esté distribuida y dónde están los shards
-- ---------------------------------------------------------------------
SELECT logicalrelid::regclass, partmethod, colocationid
FROM pg_dist_partition
WHERE logicalrelid = 'region'::regclass;

SELECT
    s.shardid,
    n.nodename,
    n.nodeport,
    n.noderole
FROM pg_dist_placement p
JOIN pg_dist_shard s ON p.shardid = s.shardid
JOIN pg_dist_node n ON p.groupid = n.groupid
WHERE s.logicalrelid = 'region'::regclass
ORDER BY s.shardid;

SELECT colocationid, shardcount, replicationfactor, distributioncolumntype::regtype
FROM pg_dist_colocation;

-- ---------------------------------------------------------------------
-- PASO 7. Datos distribuidos: desde el coordinador se ven las 3 regiones
-- ---------------------------------------------------------------------
SELECT * FROM region;

-- ---------------------------------------------------------------------
-- PASO 8. Datos físicos de cada shard (fuera de psql, en la carpeta
--         del proyecto; usar los shardid que dio el PASO 6)
-- ---------------------------------------------------------------------
-- docker exec -it citus_worker_1 psql -U postgres -d coorddb -c "SELECT * FROM region_102008;"
-- docker exec -it citus_worker_2 psql -U postgres -d coorddb -c "SELECT * FROM region_102009;"
-- docker exec -it citus_worker_3 psql -U postgres -d coorddb -c "SELECT * FROM region_102010;"
