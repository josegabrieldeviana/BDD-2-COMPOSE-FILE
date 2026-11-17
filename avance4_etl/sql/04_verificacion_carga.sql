-- =====================================================================
-- G8 · Avance 4 · Verificación de la carga del Data Mart (base g8_datamart)
-- Solo lectura. Compara lo cargado con las reglas del ETL y con los números
-- esperados del staging y de MongoDB.
-- =====================================================================
\echo '== 1. Filas por tabla'
SELECT 'dim_tiempo' tabla, COUNT(*) filas FROM dim_tiempo UNION ALL
SELECT 'dim_region', COUNT(*) FROM dim_region UNION ALL
SELECT 'dim_aeropuerto', COUNT(*) FROM dim_aeropuerto UNION ALL
SELECT 'dim_vuelo', COUNT(*) FROM dim_vuelo UNION ALL
SELECT 'dim_estado_inspeccion', COUNT(*) FROM dim_estado_inspeccion UNION ALL
SELECT 'dim_tipo_equipaje', COUNT(*) FROM dim_tipo_equipaje UNION ALL
SELECT 'fact_equipaje_procesado', COUNT(*) FROM fact_equipaje_procesado UNION ALL
SELECT 'fact_incidencias_equipaje', COUNT(*) FROM fact_incidencias_equipaje;

\echo '== 2. Dimensiones pequeñas completas'
SELECT * FROM dim_region ORDER BY sk_region;
SELECT * FROM dim_estado_inspeccion ORDER BY sk_estado_inspeccion;
SELECT * FROM dim_tipo_equipaje ORDER BY sk_tipo_equipaje;
SELECT * FROM dim_aeropuerto WHERE codigo_iata IN ('CLT','DFW','LAX','SAT','ORD') ORDER BY sk_aeropuerto;
SELECT * FROM dim_vuelo WHERE sk_vuelo IN (0, 1, 2, 800) ORDER BY sk_vuelo;

\echo '== 3. dim_tiempo: rango, SK en orden de fecha y atributos calculados contra PostgreSQL'
SELECT MIN(fecha_completa) desde, MAX(fecha_completa) hasta, COUNT(*) dias,
       BOOL_AND(sk_tiempo = (fecha_completa - DATE '2026-01-01') + 1) sk_igual_al_orden_de_fecha,
       SUM((anio <> EXTRACT(YEAR FROM fecha_completa))::int + (trimestre <> EXTRACT(QUARTER FROM fecha_completa))::int
         + (mes <> EXTRACT(MONTH FROM fecha_completa))::int + (dia_mes <> EXTRACT(DAY FROM fecha_completa))::int
         + (es_fin_de_semana <> (EXTRACT(ISODOW FROM fecha_completa) IN (6, 7)))::int) atributos_mal_calculados
FROM dim_tiempo;
SELECT fecha_completa, nombre_mes, dia_semana, es_fin_de_semana FROM dim_tiempo
WHERE fecha_completa BETWEEN DATE '2026-11-13' AND DATE '2026-11-16' ORDER BY 1;

\echo '== 4. fact_equipaje_procesado: claves desconocidas y nulos'
SELECT COUNT(*) filas,
       SUM((sk_vuelo = 0)::int) sin_vuelo,
       SUM((sk_estado_inspeccion = 0)::int) sin_inspeccion,
       COUNT(tiempo_entrega_min) con_telemetria,
       SUM(es_conexion) con_conexion, SUM(1 - es_conexion) ruta_directa,
       COUNT(DISTINCT tag_rfid_bag) maletas_distintas
FROM fact_equipaje_procesado;

\echo '== 5. Medidas (solo maletas con telemetría): deben coincidir con el ensayo de MongoDB'
SELECT ROUND(AVG(tiempo_transito_bhs_min), 1) transito_prom_min,
       ROUND(AVG(tiempo_entrega_min), 1) entrega_prom_min,
       MIN(tiempo_entrega_min) entrega_min, MAX(tiempo_entrega_min) entrega_max,
       ROUND(100.0 * AVG(fue_entregado_a_tiempo), 1) pct_a_tiempo,
       ROUND(100.0 * AVG(transferencia_exitosa), 1) pct_transferencia_exitosa,
       ROUND(AVG(peso_kg), 2) peso_prom
FROM fact_equipaje_procesado WHERE tiempo_entrega_min IS NOT NULL;
SELECT SUM(((fue_entregado_a_tiempo = 1) <> (tiempo_entrega_min <= 20))::int) reglas_a_tiempo_inconsistentes,
       SUM((tiempo_entrega_min <> ROUND(tiempo_entrega_min))::int) tiempos_con_fraccion
FROM fact_equipaje_procesado WHERE tiempo_entrega_min IS NOT NULL;

\echo '== 6. Distribución por estado de inspección y por tipo de equipaje'
SELECT e.codigo_estado, COUNT(*) maletas FROM fact_equipaje_procesado f
JOIN dim_estado_inspeccion e USING (sk_estado_inspeccion) GROUP BY 1 ORDER BY 2 DESC;
SELECT t.categoria, t.prioridad_entrega, COUNT(*) maletas, MIN(f.peso_kg) peso_min, MAX(f.peso_kg) peso_max
FROM fact_equipaje_procesado f JOIN dim_tipo_equipaje t USING (sk_tipo_equipaje) GROUP BY 1, 2 ORDER BY 1, 2;

\echo '== 7. fact_incidencias_equipaje'
SELECT COUNT(*) filas, SUM(fue_retenido) retenidas, SUM(requiere_apertura_manual) con_apertura,
       SUM(ocurrio_en_conexion) en_conexion, COUNT(tiempo_resolucion_min) con_tiempo_resolucion,
       COUNT(monto_compensacion_usd) con_compensacion, SUM(monto_compensacion_usd) total_compensado,
       SUM((sk_vuelo = 0)::int) sin_vuelo
FROM fact_incidencias_equipaje;
SELECT tipo_incidencia, COUNT(*) FROM fact_incidencias_equipaje GROUP BY 1 ORDER BY 2 DESC;
SELECT COUNT(*) inspecciones_con_su_maleta,
       SUM(((ocurrio_en_conexion = 1) <> (sk_aeropuerto_incidencia = sk_aeropuerto_conexion_maleta))::int)
       conexion_inconsistente
FROM (SELECT i.ocurrio_en_conexion, i.sk_aeropuerto_incidencia, f.sk_aeropuerto_conexion sk_aeropuerto_conexion_maleta
      FROM fact_incidencias_equipaje i JOIN fact_equipaje_procesado f USING (tag_rfid_bag)) x;
