// =====================================================================
// G8 · Avance 4 · Las 10 consultas del Avance 3 (láminas 6 y 7), contadas.
// Sirve para comparar cuántos documentos devuelve cada una con los datos
// actuales de Atlas y con la versión nueva. Solo lectura.
// =====================================================================
const d = db.getSiblingDB("aeropuerto_nosql");
const fila = (nombre, n, ejemplo) => print(`${nombre}\t${n}\t${ejemplo === undefined ? "" : EJSON.stringify(ejemplo)}`);

fila("find 1 ($eq) telemetría en LAX", d.telemetria_escanner_equipaje.countDocuments({ codigo_aeropuerto: { $eq: "LAX" } }));
fila("find 2 ($in) alerta de peso o desviación", d.telemetria_escanner_equipaje.countDocuments({ alertas_detectadas: { $in: ["ALERTA_PESO", "DESVIACION_LIGERA"] } }));
fila("find 3 ($gte/$lte) mantenimientos de 500 a 2.000 USD", d.mantenimiento_infraestructura.countDocuments({ costo_total_usd: { $gte: 500, $lte: 2000 } }));
fila("find 4 ($and+$or) retenidas o abiertas en MIA", d.inspecciones_seguridad_tsa.countDocuments({ $and: [
  { codigo_aeropuerto: "MIA" }, { $or: [{ resultado_inspeccion: "RETENIDO" }, { requiere_apertura_manual: true }] }] }));
fila("find 5 (proyección) reseñas", d.resenas_servicio_pasajero.countDocuments({}),
  d.resenas_servicio_pasajero.findOne({}, { _id: 0, id_pasajero: 1, numero_vuelo: 1, calificacion_general: 1, comentario: 1 }));

let r = d.mantenimiento_infraestructura.aggregate([
  { $match: { tipo_intervencion: "CORRECTIVO" } },
  { $group: { _id: "$codigo_aeropuerto", costo_total_usd: { $sum: "$costo_total_usd" }, intervenciones: { $sum: 1 } } },
  { $sort: { costo_total_usd: -1 } }]).toArray();
fila("pipeline 1 ($match+$group) correctivos por aeropuerto", r.length, r[0]);

r = d.inspecciones_seguridad_tsa.aggregate([
  { $unwind: "$articulos_inspeccionados" },
  { $group: { _id: { aeropuerto: "$codigo_aeropuerto", categoria: "$articulos_inspeccionados.categoria" },
      hallazgos: { $sum: 1 }, retenidos: { $sum: { $cond: [{ $eq: ["$resultado_inspeccion", "RETENIDO"] }, 1, 0] } } } },
  { $sort: { hallazgos: -1 } }]).toArray();
fila("pipeline 2 ($unwind+$group) hallazgos TSA por aeropuerto y categoría", r.length, r[0]);

r = d.inspecciones_seguridad_tsa.aggregate([
  { $match: { resultado_inspeccion: "RETENIDO" } },
  { $lookup: { from: "mantenimiento_infraestructura", localField: "codigo_aeropuerto", foreignField: "codigo_aeropuerto", as: "mantenimientos" } },
  { $project: { _id: 0, inspeccion: "$_id", codigo_etiqueta: 1, codigo_aeropuerto: 1,
      mantenimientos_en_aeropuerto: { $size: "$mantenimientos" },
      correctivos: { $size: { $filter: { input: "$mantenimientos", cond: { $eq: ["$$this.tipo_intervencion", "CORRECTIVO"] } } } } } }]).toArray();
fila("pipeline 3 ($lookup) retenidas y mantenimientos de su aeropuerto", r.length, r[0]);

r = d.mantenimiento_infraestructura.aggregate([
  { $unwind: "$repuestos_utilizados" },
  { $replaceRoot: { newRoot: { $mergeObjects: ["$repuestos_utilizados", { id_mantenimiento: "$_id", codigo_aeropuerto: "$codigo_aeropuerto" }] } } }]).toArray();
fila("pipeline 4 ($unwind+$replaceRoot) repuestos como raíz", r.length, r[0]);

r = d.resenas_servicio_pasajero.aggregate([
  { $match: { calificacion_general: { $lte: 2 } } }, { $sort: { calificacion_general: 1, fecha_registro: -1 } },
  { $skip: 0 }, { $limit: 5 }, { $project: { id_pasajero: 1, numero_vuelo: 1, calificacion_general: 1, comentario: 1 } }]).toArray();
fila("pipeline 5 ($sort+$skip+$limit) reseñas críticas, página 1", r.length, r[0]);
