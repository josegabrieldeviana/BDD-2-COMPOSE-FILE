-- Tablas de la sección 1 del informe G8 (MySQL 8.0), limpias para ejecutar tal cual.

CREATE TABLE region (
    nombre_region VARCHAR(10) PRIMARY KEY,
    CONSTRAINT chk_region_valida CHECK (nombre_region IN ('ESTE', 'CENTRAL', 'OESTE'))
);
CREATE TABLE aeropuerto (
    codigo_aeropuerto CHAR(3) PRIMARY KEY,
    region VARCHAR(10),
    FOREIGN KEY (region) REFERENCES region(nombre_region),
    CONSTRAINT chk_aeropuerto_region CHECK (
        (region = 'ESTE' AND codigo_aeropuerto IN ('CLT','PHL','JFK','LGA','DCA','MIA','BOS','EWR','BWI','IAD','PIT','RDU','ATL','MCO')) OR
        (region = 'CENTRAL' AND codigo_aeropuerto IN ('DFW','ORD','MSP','DTW','CLE','STL','MCI','MSY','IAH','AUS','SAT','MEM','BNA','MDW')) OR
        (region = 'OESTE' AND codigo_aeropuerto IN ('PHX','LAX','SFO','SAN','LAS','SEA','PDX','SLC','DEN','ABQ','TUS','SJC','SNA','OAK'))
    )
);
CREATE TABLE hub (
    codigo_base_operaciones CHAR(3) PRIMARY KEY,
    region VARCHAR(10),
    FOREIGN KEY (region) REFERENCES region(nombre_region),
    FOREIGN KEY (codigo_base_operaciones) REFERENCES aeropuerto(codigo_aeropuerto),
    CONSTRAINT chk_hub_region CHECK (
        (region = 'ESTE' AND codigo_base_operaciones IN ('CLT','PHL','JFK','LGA','DCA','MIA')) OR
        (region = 'CENTRAL' AND codigo_base_operaciones IN ('DFW','ORD')) OR
        (region = 'OESTE' AND codigo_base_operaciones IN ('PHX','LAX'))
    )
);
CREATE TABLE pasajero ( id BIGINT PRIMARY KEY );
CREATE TABLE tarifa ( id BIGINT PRIMARY KEY, precio DECIMAL );
CREATE TABLE check_in ( id_check_in BIGINT PRIMARY KEY, confirmacion_identidad BIGINT );
CREATE TABLE vuelo_programado (
    id_vuelo_programado BIGINT PRIMARY KEY,
    fecha_salida TIMESTAMP,
    fecha_llegada TIMESTAMP,
    retraso_minutos INTEGER,
    estado_de_vigencia ENUM('programado','retrasado','abordado','en_vuelo','aterrizado','cancelado') DEFAULT 'programado'
);
CREATE TABLE vuelo_operado (
    id_vuelo_operado BIGINT PRIMARY KEY,
    numero_vuelo CHAR(6),
    fecha_salida_real TIMESTAMP,
    fecha_llegada_real TIMESTAMP,
    retraso_minutos INTEGER,
    estado VARCHAR(20),
    FOREIGN KEY (id_vuelo_operado) REFERENCES vuelo_programado(id_vuelo_programado)
);
CREATE TABLE asignacion_puerta (
    id_asignacion BIGINT PRIMARY KEY,
    vuelo_asociado BIGINT,
    id_pase_abordaje BIGINT,
    FOREIGN KEY (vuelo_asociado) REFERENCES vuelo_programado(id_vuelo_programado)
);
CREATE TABLE pase_abordaje (
    id_pase_abordaje BIGINT PRIMARY KEY,
    id_asignacion_puerta BIGINT,
    fecha_emision TIMESTAMP,
    numero_asiento VARCHAR(4),
    zona_abordaje CHAR,
    zona_aterrizaje CHAR,
    FOREIGN KEY (id_asignacion_puerta) REFERENCES asignacion_puerta(id_asignacion)
);
CREATE TABLE boleto (
    id_boleto BIGINT PRIMARY KEY,
    id_pasajero BIGINT,
    numero_boleto CHAR(13),
    fecha_emision DATE,
    tarifa_base NUMERIC(10,2),
    clase_servicio CHAR(1),
    estado VARCHAR(20),
    timestamp_evento_boleto TIMESTAMP,
    id_tarifa BIGINT,
    FOREIGN KEY (id_pasajero) REFERENCES pasajero(id),
    FOREIGN KEY (id_tarifa) REFERENCES tarifa(id)
);
CREATE TABLE reserva_pnr (
    id_reserva_pnr BIGINT PRIMARY KEY,
    id_pasajero BIGINT,
    itinerario_vuelos TEXT,
    info_contacto TEXT,
    pnr_fecha_de_emision TIMESTAMP,
    ente_realizador_de_reserva VARCHAR(255),
    FOREIGN KEY (id_pasajero) REFERENCES pasajero(id)
);
CREATE TABLE equipaje (
    id CHAR(10) PRIMARY KEY,
    id_pasajero BIGINT,
    FOREIGN KEY (id_pasajero) REFERENCES pasajero(id)
);
CREATE TABLE movimiento_equipaje (
    id_movimiento BIGINT PRIMARY KEY,
    codigo_etiqueta CHAR(10),
    tipo_evento VARCHAR(20),
    timestamp_evento TIMESTAMP,
    peso_kg NUMERIC(5,2),
    id_boleto BIGINT,
    id_codigo_pnr BIGINT,
    FOREIGN KEY (id_boleto) REFERENCES boleto(id_boleto),
    FOREIGN KEY (id_codigo_pnr) REFERENCES reserva_pnr(id_reserva_pnr)
);
CREATE TABLE segmento_boleto (
    id_segmento_de_boleto INTEGER PRIMARY KEY,
    check_in_id BIGINT,
    boleto_id BIGINT,
    id_pase_abordaje BIGINT,
    FOREIGN KEY (check_in_id) REFERENCES check_in(id_check_in),
    FOREIGN KEY (boleto_id) REFERENCES boleto(id_boleto),
    FOREIGN KEY (id_pase_abordaje) REFERENCES pase_abordaje(id_pase_abordaje)
);