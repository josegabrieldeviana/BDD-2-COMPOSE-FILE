-- G8 · Avance 4 · Primer paso del job: deja el datamart vacío y listo para recargar.
-- El Table output no puede usar "truncate" porque las dimensiones tienen FK desde los
-- hechos (lo advierte la prepa); por eso se vacía aquí, hechos primero y con CASCADE.
TRUNCATE fact_incidencias_equipaje, fact_equipaje_procesado, dim_tiempo, dim_region,
         dim_aeropuerto, dim_vuelo, dim_estado_inspeccion, dim_tipo_equipaje CASCADE;
-- Miembros "desconocido" (SK 0): maletas sin vuelo en el staging y sin inspección en MongoDB
INSERT INTO dim_vuelo VALUES (0, '------', '--', 'Sin vuelo asignado');
INSERT INTO dim_estado_inspeccion VALUES (0, 'SIN_INSPECCION', 'Sin inspección registrada en MongoDB', TRUE, FALSE);
