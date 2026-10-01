-- Índices propuestos en el informe (punto 3.2.1)
CREATE UNIQUE INDEX idx_boleto_numero ON boleto (numero_boleto);
CREATE INDEX idx_vprog_fecha_salida ON vuelo_programado (fecha_salida);
CREATE INDEX idx_mov_etiqueta_ts ON movimiento_equipaje (codigo_etiqueta, timestamp_evento);
CREATE INDEX idx_vop_numero_fecha ON vuelo_operado (numero_vuelo, fecha_salida_real);
CREATE FULLTEXT INDEX ft_pnr_itinerario ON reserva_pnr (itinerario_vuelos);
CREATE FULLTEXT INDEX ft_pnr_contacto ON reserva_pnr (info_contacto);

-- Índice de la consulta de optimización (punto 4): filtro por tipo de evento y rango de fechas
CREATE INDEX idx_mov_evento_fecha ON movimiento_equipaje (tipo_evento, timestamp_evento);

ANALYZE TABLE region, aeropuerto, hub, pasajero, tarifa, boleto, vuelo_programado, vuelo_operado,
              reserva_pnr, equipaje, movimiento_equipaje;
