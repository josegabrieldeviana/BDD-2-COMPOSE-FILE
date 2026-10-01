-- =====================================================================
-- Sección 3.2 - Manejo de Índices (MySQL 8.0 / InnoDB) - G8
-- Requiere: 01_tablas.sql y 02_datos.sql ya ejecutados.
-- Ejecutar bloque por bloque y sacar captura de cada resultado.
-- =====================================================================

-- ---------------------------------------------------------------------
-- PASO 1. Línea base: EXPLAIN ANALYZE SIN índices
-- ---------------------------------------------------------------------
-- Q1 (B1): buscar un boleto por su número
EXPLAIN ANALYZE SELECT * FROM boleto WHERE numero_boleto = '0010012306682';

-- Q2 (B2): vuelos programados en una semana
EXPLAIN ANALYZE SELECT id_vuelo_programado, fecha_salida FROM vuelo_programado
WHERE fecha_salida BETWEEN '2026-10-01' AND '2026-10-07';

-- Q3 (B3): historial de una maleta en orden cronológico
EXPLAIN ANALYZE SELECT tipo_evento, timestamp_evento FROM movimiento_equipaje
WHERE codigo_etiqueta = 'TAG0000123' ORDER BY timestamp_evento;

-- Q4 (B4): salidas reales de un número de vuelo
EXPLAIN ANALYZE SELECT numero_vuelo, fecha_salida_real FROM vuelo_operado
WHERE numero_vuelo = 'UA1234';

-- Q5 (F1): reservas cuyo itinerario pasa por MIA (sin FULLTEXT solo se puede con LIKE)
EXPLAIN ANALYZE SELECT id_reserva_pnr FROM reserva_pnr
WHERE itinerario_vuelos LIKE '%MIA%';

-- Q6 (F2): reservas de un contacto por nombre y apellido
EXPLAIN ANALYZE SELECT id_reserva_pnr FROM reserva_pnr
WHERE info_contacto LIKE '%Sofia%' AND info_contacto LIKE '%Diaz%';

-- ---------------------------------------------------------------------
-- PASO 2. Crear los 6 índices (4 B-tree + 2 FULLTEXT)
-- ---------------------------------------------------------------------
CREATE UNIQUE INDEX idx_boleto_numero   ON boleto (numero_boleto);
CREATE INDEX idx_vprog_fecha_salida     ON vuelo_programado (fecha_salida);
CREATE INDEX idx_mov_etiqueta_ts        ON movimiento_equipaje (codigo_etiqueta, timestamp_evento);
CREATE INDEX idx_vop_numero_fecha       ON vuelo_operado (numero_vuelo, fecha_salida_real);
CREATE FULLTEXT INDEX ft_pnr_itinerario ON reserva_pnr (itinerario_vuelos);
CREATE FULLTEXT INDEX ft_pnr_contacto   ON reserva_pnr (info_contacto);

ANALYZE TABLE boleto, vuelo_programado, movimiento_equipaje, vuelo_operado, reserva_pnr;

-- ---------------------------------------------------------------------
-- PASO 3. Mostrar los índices
-- ---------------------------------------------------------------------
SHOW INDEX FROM boleto;
SHOW INDEX FROM vuelo_programado;
SHOW INDEX FROM movimiento_equipaje;
SHOW INDEX FROM vuelo_operado;
SHOW INDEX FROM reserva_pnr;

-- ---------------------------------------------------------------------
-- PASO 4. Misma consulta CON índice y con IGNORE INDEX
-- ---------------------------------------------------------------------
-- B1
EXPLAIN SELECT * FROM boleto WHERE numero_boleto = '0010012306682';
EXPLAIN ANALYZE SELECT * FROM boleto WHERE numero_boleto = '0010012306682';
EXPLAIN ANALYZE SELECT * FROM boleto IGNORE INDEX (idx_boleto_numero)
WHERE numero_boleto = '0010012306682';

-- B2
EXPLAIN SELECT id_vuelo_programado, fecha_salida FROM vuelo_programado
WHERE fecha_salida BETWEEN '2026-10-01' AND '2026-10-07';
EXPLAIN ANALYZE SELECT id_vuelo_programado, fecha_salida FROM vuelo_programado
WHERE fecha_salida BETWEEN '2026-10-01' AND '2026-10-07';
EXPLAIN ANALYZE SELECT id_vuelo_programado, fecha_salida FROM vuelo_programado IGNORE INDEX (idx_vprog_fecha_salida)
WHERE fecha_salida BETWEEN '2026-10-01' AND '2026-10-07';
-- Selectividad: con un rango de casi todo el año el optimizador vuelve a elegir Table scan
EXPLAIN SELECT * FROM vuelo_programado
WHERE fecha_salida BETWEEN '2026-01-01' AND '2026-11-30';

-- B3
EXPLAIN SELECT tipo_evento, timestamp_evento FROM movimiento_equipaje
WHERE codigo_etiqueta = 'TAG0000123' ORDER BY timestamp_evento;
EXPLAIN ANALYZE SELECT tipo_evento, timestamp_evento FROM movimiento_equipaje
WHERE codigo_etiqueta = 'TAG0000123' ORDER BY timestamp_evento;
EXPLAIN ANALYZE SELECT tipo_evento, timestamp_evento FROM movimiento_equipaje IGNORE INDEX (idx_mov_etiqueta_ts)
WHERE codigo_etiqueta = 'TAG0000123' ORDER BY timestamp_evento;

-- B4 (covering index: Extra = Using index)
EXPLAIN SELECT numero_vuelo, fecha_salida_real FROM vuelo_operado WHERE numero_vuelo = 'UA1234';
EXPLAIN ANALYZE SELECT numero_vuelo, fecha_salida_real FROM vuelo_operado WHERE numero_vuelo = 'UA1234';
EXPLAIN ANALYZE SELECT numero_vuelo, fecha_salida_real FROM vuelo_operado IGNORE INDEX (idx_vop_numero_fecha)
WHERE numero_vuelo = 'UA1234';

-- F1 (NATURAL LANGUAGE, ordenado por relevancia)
EXPLAIN SELECT id_reserva_pnr FROM reserva_pnr
WHERE MATCH(itinerario_vuelos) AGAINST ('MIA' IN NATURAL LANGUAGE MODE);
EXPLAIN ANALYZE SELECT id_reserva_pnr FROM reserva_pnr
WHERE MATCH(itinerario_vuelos) AGAINST ('MIA' IN NATURAL LANGUAGE MODE);

-- F2 (BOOLEAN MODE: ambas palabras obligatorias, sin orden por relevancia)
EXPLAIN SELECT id_reserva_pnr FROM reserva_pnr
WHERE MATCH(info_contacto) AGAINST ('+Sofia +Diaz' IN BOOLEAN MODE);
EXPLAIN ANALYZE SELECT id_reserva_pnr FROM reserva_pnr
WHERE MATCH(info_contacto) AGAINST ('+Sofia +Diaz' IN BOOLEAN MODE);

-- ---------------------------------------------------------------------
-- PASO 5. Estadísticas para orden y altura de los B-tree
-- ---------------------------------------------------------------------
SELECT table_name, index_name, stat_name, stat_value
FROM mysql.innodb_index_stats
WHERE database_name = DATABASE()
  AND index_name IN ('idx_boleto_numero','idx_vprog_fecha_salida','idx_mov_etiqueta_ts','idx_vop_numero_fecha')
  AND stat_name IN ('size','n_leaf_pages')
ORDER BY table_name, index_name, stat_name;

SELECT 'boleto' AS tabla, COUNT(*) AS n FROM boleto
UNION ALL SELECT 'vuelo_programado', COUNT(*) FROM vuelo_programado
UNION ALL SELECT 'movimiento_equipaje', COUNT(*) FROM movimiento_equipaje
UNION ALL SELECT 'vuelo_operado', COUNT(*) FROM vuelo_operado;