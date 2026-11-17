// =====================================================================
// G8 · Avance 4 · Estado de la fuente NoSQL (solo lectura)
// Base: aeropuerto_nosql (MongoDB Atlas). No modifica nada.
// =====================================================================
print("== bases y colecciones ==");
db.adminCommand({ listDatabases: 1, nameOnly: true }).databases
  .map(d => d.name).filter(n => !["admin", "local", "config"].includes(n))
  .forEach(n => {
    const d = db.getSiblingDB(n);
    d.getCollectionInfos().forEach(c => {
      const v = c.options && c.options.validator ? "con validador" : "sin validador";
      print(`${n}.${c.name}\t${d.getCollection(c.name).estimatedDocumentCount()} docs\t${v}`);
    });
  });

const a = db.getSiblingDB("aeropuerto_nosql");
const cuenta = (col, filtro) => a.getCollection(col).countDocuments(filtro);

print("\n== formatos de las claves que cruzan con SQL ==");
[["telemetria_escanner_equipaje", "codigo_etiqueta", /^TAG[0-9]{7}$/],
 ["inspecciones_seguridad_tsa", "codigo_etiqueta", /^TAG[0-9]{7}$/],
 ["notificaciones_pasajero", "codigo_etiqueta", /^TAG[0-9]{7}$/],
 ["telemetria_escanner_equipaje", "codigo_aeropuerto", /^[A-Z]{3}$/],
 ["inspecciones_seguridad_tsa", "codigo_aeropuerto", /^[A-Z]{3}$/],
 ["mantenimiento_infraestructura", "codigo_aeropuerto", /^[A-Z]{3}$/],
 ["resenas_servicio_pasajero", "numero_vuelo", /^(AA|DL|UA|WN)[0-9]{4}$/]
].forEach(([col, campo, re]) => {
  const total = cuenta(col, {});
  const ok = cuenta(col, { [campo]: re });
  const distintos = a.getCollection(col).distinct(campo).length;
  const muestra = (a.getCollection(col).findOne({}, { [campo]: 1 }) || {})[campo];
  print(`${col}.${campo}\tformato ok ${ok}/${total}\tdistintos ${distintos}\tejemplo ${muestra}`);
});

print("\n== tipos de dato de fechas e identificadores ==");
[["telemetria_escanner_equipaje", "timestamp"], ["inspecciones_seguridad_tsa", "timestamp"],
 ["mantenimiento_infraestructura", "fecha_mantenimiento"], ["resenas_servicio_pasajero", "fecha_registro"],
 ["notificaciones_pasajero", "estado_envio.timestamp_lectura"], ["notificaciones_pasajero", "id_pasajero"],
 ["resenas_servicio_pasajero", "id_pasajero"], ["mantenimiento_infraestructura", "costo_total_usd"]
].forEach(([col, campo]) => {
  const r = a.getCollection(col).aggregate([
    { $group: { _id: { $type: "$" + campo }, n: { $sum: 1 }, min: { $min: "$" + campo }, max: { $max: "$" + campo } } },
    { $sort: { n: -1 } }]).toArray();
  print(`${col}.${campo}\t` + r.map(x => `${x._id}: ${x.n} [${EJSON.stringify(x.min)} .. ${EJSON.stringify(x.max)}]`).join(" | "));
});

print("\n== campos presentes por coleccion (diversidad estructural) ==");
a.getCollectionNames().sort().forEach(col => {
  const r = a.getCollection(col).aggregate([
    { $project: { kv: { $objectToArray: "$$ROOT" } } }, { $unwind: "$kv" },
    { $group: { _id: "$kv.k", n: { $sum: 1 }, tipos: { $addToSet: { $type: "$kv.v" } } } }, { $sort: { _id: 1 } }]).toArray();
  print(col + "\t" + r.map(x => `${x._id}(${x.n},${x.tipos.join("/")})`).join(" "));
});

print("\n== dominios que alimentan dimensiones y banderas ==");
const dominio = (col, campo, unwind) => {
  const p = unwind ? [{ $unwind: { path: "$" + campo, preserveNullAndEmptyArrays: true } }] : [];
  const r = a.getCollection(col).aggregate(p.concat([{ $group: { _id: "$" + campo, n: { $sum: 1 } } }, { $sort: { n: -1 } }])).toArray();
  print(`${col}.${campo}\t` + r.map(x => `${x._id}=${x.n}`).join(", "));
};
dominio("inspecciones_seguridad_tsa", "resultado_inspeccion");
dominio("inspecciones_seguridad_tsa", "requiere_apertura_manual");
dominio("inspecciones_seguridad_tsa", "agente_responsable.departamento");
dominio("telemetria_escanner_equipaje", "alertas_detectadas", true);
dominio("notificaciones_pasajero", "tipo_evento");
dominio("notificaciones_pasajero", "canal");
dominio("mantenimiento_infraestructura", "tipo_intervencion");
dominio("mantenimiento_infraestructura", "equipo.tipo");
dominio("resenas_servicio_pasajero", "calificacion_general");
dominio("resenas_servicio_pasajero", "evaluacion_equipaje.estado_maleta");

print("\n== cruces entre inspeccion y resultado ==");
a.inspecciones_seguridad_tsa.aggregate([
  { $group: { _id: { r: "$resultado_inspeccion", m: "$requiere_apertura_manual" }, n: { $sum: 1 },
              articulos: { $avg: { $size: { $ifNull: ["$articulos_inspeccionados", []] } } } } },
  { $sort: { "_id.r": 1, "_id.m": 1 } }]).forEach(x => print(`${x._id.r}\tapertura_manual=${x._id.m}\t${x.n}\tarticulos_prom=${x.articulos.toFixed(2)}`));

print("\n== maletas con mas de un documento por coleccion ==");
["telemetria_escanner_equipaje", "inspecciones_seguridad_tsa", "notificaciones_pasajero"].forEach(col => {
  const r = a.getCollection(col).aggregate([{ $group: { _id: "$codigo_etiqueta", n: { $sum: 1 } } },
    { $group: { _id: "$n", maletas: { $sum: 1 } } }, { $sort: { _id: 1 } }]).toArray();
  print(col + "\t" + r.map(x => `${x.maletas} maletas con ${x._id} doc`).join(", "));
});
const tel = a.telemetria_escanner_equipaje.distinct("codigo_etiqueta");
const ins = a.inspecciones_seguridad_tsa.distinct("codigo_etiqueta");
const noti = a.notificaciones_pasajero.distinct("codigo_etiqueta");
print(`etiquetas en comun\ttelemetria∩inspeccion ${tel.filter(x => ins.includes(x)).length}\ttelemetria∩notificacion ${tel.filter(x => noti.includes(x)).length}\tinspeccion∩notificacion ${ins.filter(x => noti.includes(x)).length}`);

print("\n== un documento de ejemplo por coleccion ==");
a.getCollectionNames().sort().forEach(col => { print(col); print(EJSON.stringify(a.getCollection(col).findOne(), null, 1)); });
