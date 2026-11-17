// G8 · Avance 4 · Exporta las claves de MongoDB (v2) como tablas TEMPORALES de MySQL.
// Solo lee de MongoDB. Sirve igual contra el ensayo local que contra Atlas.
const a = db.getSiblingDB("aeropuerto_nosql");
const q = v => v === null || v === undefined ? "NULL" : "'" + String(v).replace(/'/g, "''") + "'";
const f = d => d ? "'" + d.toISOString().slice(0, 19).replace("T", " ") + "'" : "NULL";
const volcar = (tabla, ddl, filas) => {
  print(`CREATE TEMPORARY TABLE ${tabla} (${ddl});`);
  for (let i = 0; i < filas.length; i += 2000)
    print(`INSERT INTO ${tabla} VALUES\n` + filas.slice(i, i + 2000).join(",\n") + ";");
};
volcar("tmp_insp", "id VARCHAR(12), etiqueta CHAR(10), aeropuerto CHAR(3), resultado VARCHAR(30), apertura INT, min_retenida INT, ts DATETIME, KEY (etiqueta)",
  a.inspecciones_seguridad_tsa.find().toArray().map(d => `(${q(d._id)},${q(d.codigo_etiqueta)},${q(d.codigo_aeropuerto)},${q(d.resultado_inspeccion)},${d.requiere_apertura_manual ? 1 : 0},${d.retencion ? d.retencion.minutos_retenida : "NULL"},${f(d.timestamp)})`));
volcar("tmp_tel", "id VARCHAR(12), etiqueta CHAR(10), aeropuerto CHAR(3), punto VARCHAR(20), ts DATETIME, desvio INT, alerta_peso INT, KEY (etiqueta)",
  a.telemetria_escanner_equipaje.find().toArray().map(d => `(${q(d._id)},${q(d.codigo_etiqueta)},${q(d.codigo_aeropuerto)},${q(d.punto_control)},${f(d.timestamp)},${(d.alertas_detectadas || []).includes("DESVIACION_LIGERA") ? 1 : 0},${(d.alertas_detectadas || []).includes("ALERTA_PESO") ? 1 : 0})`));
volcar("tmp_not", "id VARCHAR(12), id_pasajero BIGINT, etiqueta CHAR(10), tipo VARCHAR(30), ts_envio DATETIME, compensacion DECIMAL(10,2), KEY (etiqueta)",
  a.notificaciones_pasajero.find().toArray().map(d => `(${q(d._id)},${d.id_pasajero},${q(d.codigo_etiqueta)},${q(d.tipo_evento)},${f(d.timestamp_envio)},${d.compensacion ? d.compensacion.monto_usd : "NULL"})`));
volcar("tmp_res", "id VARCHAR(12), id_pasajero BIGINT, numero_vuelo CHAR(6), espera INT, ts DATETIME",
  a.resenas_servicio_pasajero.find().toArray().map(d => `(${q(d._id)},${d.id_pasajero},${q(d.numero_vuelo)},${d.evaluacion_equipaje && d.evaluacion_equipaje.tiempo_espera_minutos != null ? d.evaluacion_equipaje.tiempo_espera_minutos : "NULL"},${f(d.fecha_registro)})`));
volcar("tmp_mnt", "id VARCHAR(12), aeropuerto CHAR(3), tipo VARCHAR(20), costo DECIMAL(10,2), ts DATETIME",
  a.mantenimiento_infraestructura.find().toArray().map(d => `(${q(d._id)},${q(d.codigo_aeropuerto)},${q(d.tipo_intervencion)},${d.costo_total_usd},${f(d.fecha_mantenimiento)})`));
