// G8 · Avance 4 · Exporta las claves de MongoDB como tablas TEMPORALES de MySQL
// (solo lectura en Atlas; en MySQL las tablas viven solo durante la sesión).
const a = db.getSiblingDB("aeropuerto_nosql");
const q = v => v === null || v === undefined ? "NULL" : "'" + String(v).replace(/'/g, "''") + "'";
const f = d => d ? "'" + d.toISOString().slice(0, 19).replace("T", " ") + "'" : "NULL";
const volcar = (tabla, ddl, filas) => {
  print(`CREATE TEMPORARY TABLE ${tabla} (${ddl});`);
  print(`INSERT INTO ${tabla} VALUES\n` + filas.join(",\n") + ";");
};
volcar("tmp_insp", "id VARCHAR(12), etiqueta CHAR(10), aeropuerto CHAR(3), resultado VARCHAR(30), apertura INT, ts DATETIME",
  a.inspecciones_seguridad_tsa.find().toArray().map(d => `(${q(d._id)},${q(d.codigo_etiqueta)},${q(d.codigo_aeropuerto)},${q(d.resultado_inspeccion)},${d.requiere_apertura_manual ? 1 : 0},${f(d.timestamp)})`));
volcar("tmp_tel", "id VARCHAR(12), etiqueta CHAR(10), aeropuerto CHAR(3), ts DATETIME, alertas INT",
  a.telemetria_escanner_equipaje.find().toArray().map(d => `(${q(d._id)},${q(d.codigo_etiqueta)},${q(d.codigo_aeropuerto)},${f(d.timestamp)},${(d.alertas_detectadas || []).length})`));
volcar("tmp_not", "id VARCHAR(12), id_pasajero BIGINT, etiqueta CHAR(10), ts_lectura DATETIME",
  a.notificaciones_pasajero.find().toArray().map(d => `(${q(d._id)},${d.id_pasajero},${q(d.codigo_etiqueta)},${f(d.estado_envio && d.estado_envio.timestamp_lectura)})`));
volcar("tmp_res", "id VARCHAR(12), id_pasajero BIGINT, numero_vuelo CHAR(6), espera INT, ts DATETIME",
  a.resenas_servicio_pasajero.find().toArray().map(d => `(${q(d._id)},${d.id_pasajero},${q(d.numero_vuelo)},${d.evaluacion_equipaje && d.evaluacion_equipaje.tiempo_espera_minutos != null ? d.evaluacion_equipaje.tiempo_espera_minutos : "NULL"},${f(d.fecha_registro)})`));
volcar("tmp_mnt", "id VARCHAR(12), aeropuerto CHAR(3), tipo VARCHAR(20), costo DECIMAL(10,2), ts DATETIME",
  a.mantenimiento_infraestructura.find().toArray().map(d => `(${q(d._id)},${q(d.codigo_aeropuerto)},${q(d.tipo_intervencion)},${d.costo_total_usd},${f(d.fecha_mantenimiento)})`));
