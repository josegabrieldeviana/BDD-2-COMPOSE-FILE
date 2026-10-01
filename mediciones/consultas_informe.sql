-- Mediciones del informe G8 sobre la base con los volúmenes del informe.
-- Correr con: mysql -uroot -t G8 < mediciones/consultas_informe.sql
-- Repetir los EXPLAIN ANALYZE 3 veces y reportar la mediana: aquí se muestra una corrida en caliente.

SET SESSION information_schema_stats_expiry = 0;

-- =====================================================================
-- 0. Volumen de cada tabla
-- =====================================================================
SELECT 'region' AS tabla, COUNT(*) AS filas FROM region
UNION ALL SELECT 'aeropuerto', COUNT(*) FROM aeropuerto
UNION ALL SELECT 'hub', COUNT(*) FROM hub
UNION ALL SELECT 'pasajero', COUNT(*) FROM pasajero
UNION ALL SELECT 'tarifa', COUNT(*) FROM tarifa
UNION ALL SELECT 'boleto', COUNT(*) FROM boleto
UNION ALL SELECT 'vuelo_programado', COUNT(*) FROM vuelo_programado
UNION ALL SELECT 'vuelo_operado', COUNT(*) FROM vuelo_operado
UNION ALL SELECT 'reserva_pnr', COUNT(*) FROM reserva_pnr
UNION ALL SELECT 'equipaje', COUNT(*) FROM equipaje
UNION ALL SELECT 'movimiento_equipaje', COUNT(*) FROM movimiento_equipaje
UNION ALL SELECT 'check_in', COUNT(*) FROM check_in
UNION ALL SELECT 'pase_abordaje', COUNT(*) FROM pase_abordaje
UNION ALL SELECT 'asignacion_puerta', COUNT(*) FROM asignacion_puerta
UNION ALL SELECT 'segmento_boleto', COUNT(*) FROM segmento_boleto;

-- =====================================================================
-- 1. Coherencia de los datos (todo debe dar 0)
-- =====================================================================
SELECT 'boletos con evento anterior a la emision' AS chequeo, COUNT(*) AS casos
FROM boleto WHERE DATE(timestamp_evento_boleto) < fecha_emision
UNION ALL
SELECT 'boletos con tarifa_base distinta al precio de su tarifa', COUNT(*)
FROM boleto b JOIN tarifa t ON t.id = b.id_tarifa WHERE b.tarifa_base <> t.precio
UNION ALL
SELECT 'vuelos que llegan antes de salir', COUNT(*)
FROM vuelo_operado WHERE fecha_llegada_real <= fecha_salida_real
UNION ALL
SELECT 'vuelos operados en el futuro', COUNT(*)
FROM vuelo_operado WHERE fecha_salida_real >= '2026-09-30'
UNION ALL
SELECT 'movimientos de boletos no usados', COUNT(*)
FROM movimiento_equipaje m JOIN boleto b ON b.id_boleto = m.id_boleto WHERE b.estado <> 'USADO'
UNION ALL
SELECT 'maletas de un pasajero distinto al del boleto', COUNT(*)
FROM movimiento_equipaje m
JOIN equipaje e ON e.id = m.codigo_etiqueta
JOIN boleto b ON b.id_boleto = m.id_boleto
WHERE e.id_pasajero <> b.id_pasajero
UNION ALL
SELECT 'movimientos anteriores al REGISTRADO de su maleta', COUNT(*)
FROM movimiento_equipaje m
JOIN (SELECT codigo_etiqueta, MIN(timestamp_evento) AS t_reg
      FROM movimiento_equipaje WHERE tipo_evento = 'REGISTRADO' GROUP BY codigo_etiqueta) r
  ON r.codigo_etiqueta = m.codigo_etiqueta
WHERE m.timestamp_evento < r.t_reg
UNION ALL
SELECT 'PNR del movimiento de otro pasajero', COUNT(*)
FROM movimiento_equipaje m
JOIN equipaje e ON e.id = m.codigo_etiqueta
JOIN reserva_pnr p ON p.id_reserva_pnr = m.id_codigo_pnr
WHERE p.id_pasajero <> e.id_pasajero
UNION ALL
SELECT 'movimientos en el futuro', COUNT(*)
FROM movimiento_equipaje WHERE timestamp_evento >= '2026-09-30 20:00:00';

-- =====================================================================
-- 2. Manejo de memoria (2.2.1): estadísticas de cada tabla
-- =====================================================================
SELECT table_name, table_rows, avg_row_length, data_length, index_length,
       CEIL(data_length / 16384) AS paginas_datos
FROM information_schema.tables
WHERE table_schema = 'G8'
ORDER BY table_name;

-- Promedio real de bytes de las columnas variables (para el cálculo manual)
SELECT 'movimiento_equipaje.tipo_evento' AS columna, ROUND(AVG(LENGTH(tipo_evento)), 2) AS bytes_promedio FROM movimiento_equipaje
UNION ALL SELECT 'boleto.estado', ROUND(AVG(LENGTH(estado)), 2) FROM boleto
UNION ALL SELECT 'vuelo_operado.estado', ROUND(AVG(LENGTH(estado)), 2) FROM vuelo_operado
UNION ALL SELECT 'reserva_pnr.itinerario_vuelos', ROUND(AVG(LENGTH(itinerario_vuelos)), 2) FROM reserva_pnr
UNION ALL SELECT 'reserva_pnr.info_contacto', ROUND(AVG(LENGTH(info_contacto)), 2) FROM reserva_pnr
UNION ALL SELECT 'reserva_pnr.ente_realizador_de_reserva', ROUND(AVG(LENGTH(ente_realizador_de_reserva)), 2) FROM reserva_pnr;

-- =====================================================================
-- 3. Índices (3.2.2)
-- =====================================================================
SHOW INDEX FROM boleto;
SHOW INDEX FROM vuelo_programado;
SHOW INDEX FROM movimiento_equipaje;
SHOW INDEX FROM vuelo_operado;
SHOW INDEX FROM reserva_pnr;

-- =====================================================================
-- 4. EXPLAIN y EXPLAIN ANALYZE con y sin cada índice (3.2.3)
-- =====================================================================

-- 4.1 idx_boleto_numero: búsqueda de un boleto por su número
EXPLAIN SELECT * FROM boleto WHERE numero_boleto = '0011204567884';
EXPLAIN ANALYZE SELECT * FROM boleto WHERE numero_boleto = '0011204567884'\G
EXPLAIN ANALYZE SELECT * FROM boleto IGNORE INDEX (idx_boleto_numero) WHERE numero_boleto = '0011204567884'\G

-- 4.2 idx_vprog_fecha_salida: vuelos de una semana (covering index) y un rango amplio
EXPLAIN SELECT id_vuelo_programado, fecha_salida FROM vuelo_programado
WHERE fecha_salida BETWEEN '2026-08-01' AND '2026-08-07';
EXPLAIN ANALYZE SELECT id_vuelo_programado, fecha_salida FROM vuelo_programado
WHERE fecha_salida BETWEEN '2026-08-01' AND '2026-08-07'\G
EXPLAIN ANALYZE SELECT id_vuelo_programado, fecha_salida FROM vuelo_programado IGNORE INDEX (idx_vprog_fecha_salida)
WHERE fecha_salida BETWEEN '2026-08-01' AND '2026-08-07'\G
EXPLAIN SELECT * FROM vuelo_programado WHERE fecha_salida BETWEEN '2026-01-01' AND '2026-08-31';

-- 4.3 idx_vop_numero_fecha: salidas de un número de vuelo
EXPLAIN SELECT numero_vuelo, fecha_salida_real FROM vuelo_operado WHERE numero_vuelo = 'AA1234';
EXPLAIN ANALYZE SELECT numero_vuelo, fecha_salida_real FROM vuelo_operado WHERE numero_vuelo = 'AA1234'\G
EXPLAIN ANALYZE SELECT numero_vuelo, fecha_salida_real FROM vuelo_operado IGNORE INDEX (idx_vop_numero_fecha)
WHERE numero_vuelo = 'AA1234'\G

-- 4.4 idx_mov_etiqueta_ts: historial de una maleta
EXPLAIN SELECT tipo_evento, timestamp_evento FROM movimiento_equipaje
WHERE codigo_etiqueta = '0001012345' ORDER BY timestamp_evento;
EXPLAIN ANALYZE SELECT tipo_evento, timestamp_evento FROM movimiento_equipaje
WHERE codigo_etiqueta = '0001012345' ORDER BY timestamp_evento\G
EXPLAIN ANALYZE SELECT tipo_evento, timestamp_evento FROM movimiento_equipaje IGNORE INDEX (idx_mov_etiqueta_ts)
WHERE codigo_etiqueta = '0001012345' ORDER BY timestamp_evento\G

-- 4.5 ft_pnr_itinerario: reservas cuyo itinerario pasa por MIA (sin índice: LIKE)
EXPLAIN SELECT id_reserva_pnr FROM reserva_pnr
WHERE MATCH(itinerario_vuelos) AGAINST ('MIA' IN NATURAL LANGUAGE MODE);
EXPLAIN ANALYZE SELECT id_reserva_pnr FROM reserva_pnr
WHERE MATCH(itinerario_vuelos) AGAINST ('MIA' IN NATURAL LANGUAGE MODE)\G
EXPLAIN ANALYZE SELECT id_reserva_pnr FROM reserva_pnr WHERE itinerario_vuelos LIKE '%MIA%'\G

-- 4.6 ft_pnr_contacto: contactos con Sofia y Diaz (sin índice: LIKE)
EXPLAIN SELECT id_reserva_pnr FROM reserva_pnr
WHERE MATCH(info_contacto) AGAINST ('+Sofia +Diaz' IN BOOLEAN MODE);
EXPLAIN ANALYZE SELECT id_reserva_pnr FROM reserva_pnr
WHERE MATCH(info_contacto) AGAINST ('+Sofia +Diaz' IN BOOLEAN MODE)\G
EXPLAIN ANALYZE SELECT id_reserva_pnr FROM reserva_pnr
WHERE info_contacto LIKE '%Sofia%' AND info_contacto LIKE '%Diaz%'\G

-- =====================================================================
-- 5. B-tree: páginas totales y hojas (3.2.4)
-- =====================================================================
SELECT table_name, index_name, stat_name, stat_value
FROM mysql.innodb_index_stats
WHERE database_name = 'G8'
  AND index_name IN ('idx_boleto_numero', 'idx_vprog_fecha_salida', 'idx_mov_etiqueta_ts',
                     'idx_vop_numero_fecha', 'idx_mov_evento_fecha')
  AND stat_name IN ('size', 'n_leaf_pages')
ORDER BY table_name, index_name, stat_name;

-- =====================================================================
-- 6. Consulta de optimización (punto 4)
-- =====================================================================
SELECT b.clase_servicio,
       COUNT(*)                      AS incidencias,
       COUNT(DISTINCT e.id_pasajero) AS pasajeros_afectados,
       ROUND(AVG(m.peso_kg), 2)      AS peso_promedio_kg
FROM movimiento_equipaje m
JOIN equipaje e ON e.id        = m.codigo_etiqueta
JOIN boleto   b ON b.id_boleto = m.id_boleto
JOIN tarifa   t ON t.id        = b.id_tarifa
WHERE m.tipo_evento IN ('EXTRAVIADO', 'DANADO')
  AND m.timestamp_evento >= '2026-07-01'
  AND m.timestamp_evento <  '2026-10-01'
  AND t.precio >= 300
GROUP BY b.clase_servicio
HAVING COUNT(*) >= 200;

-- Grupos antes del HAVING
SELECT b.clase_servicio, COUNT(*) AS incidencias
FROM movimiento_equipaje m
JOIN equipaje e ON e.id        = m.codigo_etiqueta
JOIN boleto   b ON b.id_boleto = m.id_boleto
JOIN tarifa   t ON t.id        = b.id_tarifa
WHERE m.tipo_evento IN ('EXTRAVIADO', 'DANADO')
  AND m.timestamp_evento >= '2026-07-01'
  AND m.timestamp_evento <  '2026-10-01'
  AND t.precio >= 300
GROUP BY b.clase_servicio;

-- Sin el índice del punto 4
EXPLAIN ANALYZE
SELECT b.clase_servicio, COUNT(*) AS incidencias, COUNT(DISTINCT e.id_pasajero) AS pasajeros_afectados,
       ROUND(AVG(m.peso_kg), 2) AS peso_promedio_kg
FROM movimiento_equipaje m IGNORE INDEX (idx_mov_evento_fecha)
JOIN equipaje e ON e.id        = m.codigo_etiqueta
JOIN boleto   b ON b.id_boleto = m.id_boleto
JOIN tarifa   t ON t.id        = b.id_tarifa
WHERE m.tipo_evento IN ('EXTRAVIADO', 'DANADO')
  AND m.timestamp_evento >= '2026-07-01'
  AND m.timestamp_evento <  '2026-10-01'
  AND t.precio >= 300
GROUP BY b.clase_servicio
HAVING COUNT(*) >= 200\G

-- Con el índice
EXPLAIN
SELECT b.clase_servicio, COUNT(*) AS incidencias, COUNT(DISTINCT e.id_pasajero) AS pasajeros_afectados,
       ROUND(AVG(m.peso_kg), 2) AS peso_promedio_kg
FROM movimiento_equipaje m
JOIN equipaje e ON e.id        = m.codigo_etiqueta
JOIN boleto   b ON b.id_boleto = m.id_boleto
JOIN tarifa   t ON t.id        = b.id_tarifa
WHERE m.tipo_evento IN ('EXTRAVIADO', 'DANADO')
  AND m.timestamp_evento >= '2026-07-01'
  AND m.timestamp_evento <  '2026-10-01'
  AND t.precio >= 300
GROUP BY b.clase_servicio
HAVING COUNT(*) >= 200;

EXPLAIN ANALYZE
SELECT b.clase_servicio, COUNT(*) AS incidencias, COUNT(DISTINCT e.id_pasajero) AS pasajeros_afectados,
       ROUND(AVG(m.peso_kg), 2) AS peso_promedio_kg
FROM movimiento_equipaje m
JOIN equipaje e ON e.id        = m.codigo_etiqueta
JOIN boleto   b ON b.id_boleto = m.id_boleto
JOIN tarifa   t ON t.id        = b.id_tarifa
WHERE m.tipo_evento IN ('EXTRAVIADO', 'DANADO')
  AND m.timestamp_evento >= '2026-07-01'
  AND m.timestamp_evento <  '2026-10-01'
  AND t.precio >= 300
GROUP BY b.clase_servicio
HAVING COUNT(*) >= 200\G

-- Con el índice y el orden del árbol optimizado (T, B, M, E)
EXPLAIN ANALYZE
SELECT /*+ JOIN_ORDER(t, b, m, e) */
       b.clase_servicio, COUNT(*) AS incidencias, COUNT(DISTINCT e.id_pasajero) AS pasajeros_afectados,
       ROUND(AVG(m.peso_kg), 2) AS peso_promedio_kg
FROM movimiento_equipaje m
JOIN equipaje e ON e.id        = m.codigo_etiqueta
JOIN boleto   b ON b.id_boleto = m.id_boleto
JOIN tarifa   t ON t.id        = b.id_tarifa
WHERE m.tipo_evento IN ('EXTRAVIADO', 'DANADO')
  AND m.timestamp_evento >= '2026-07-01'
  AND m.timestamp_evento <  '2026-10-01'
  AND t.precio >= 300
GROUP BY b.clase_servicio
HAVING COUNT(*) >= 200\G
