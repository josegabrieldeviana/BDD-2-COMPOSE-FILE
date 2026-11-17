// =====================================================================
// G8 · Avance 4 · Carga de los documentos v2 en aeropuerto_nosql
//
// Lee los EJSON de la carpeta montada en /datos/salida y reemplaza el
// contenido de las 5 colecciones. No borra las colecciones (deleteMany, no
// drop), así que los validadores y los índices se conservan.
//
// Variables de entorno:
//   APLICAR=si        -> escribe. Sin eso solo informa qué haría.
//   CREAR_VALIDADORES=si -> (solo ensayo local) crea las colecciones con los
//                        validadores de /a3/validadores.js antes de cargar.
// =====================================================================
const fs = require("fs");
const DIR = process.env.DIR_DATOS || "/datos/salida";
const APLICAR = process.env.APLICAR === "si";
const d = db.getSiblingDB("aeropuerto_nosql");
const COLECCIONES = ["telemetria_escanner_equipaje", "inspecciones_seguridad_tsa", "notificaciones_pasajero",
                     "resenas_servicio_pasajero", "mantenimiento_infraestructura"];

if (process.env.CREAR_VALIDADORES === "si") {
  load("/a3/validadores.js");
  for (const c of COLECCIONES) {
    if (!d.getCollectionNames().includes(c))
      d.createCollection(c, { validator: validadores[c], validationLevel: "strict", validationAction: "error" });
  }
}

print(APLICAR ? "MODO: APLICAR (se reemplazan los documentos)" : "MODO: SIMULACRO (no se escribe nada)");
for (const c of COLECCIONES) {
  const docs = EJSON.parse(fs.readFileSync(`${DIR}/${c}.json`, "utf8"));
  const col = d.getCollection(c);
  const antes = col.countDocuments({});
  const info = (d.getCollectionInfos({ name: c })[0] || { options: {} }).options;
  let insertados = 0;
  if (APLICAR) {
    col.deleteMany({});
    for (let i = 0; i < docs.length; i += 1000)
      insertados += Object.keys(col.insertMany(docs.slice(i, i + 1000), { ordered: true }).insertedIds).length;
  }
  const despues = col.countDocuments({});
  const incumplen = info.validator ? col.countDocuments({ $nor: [info.validator] }) : "sin validador";
  print(`${c}: en archivo ${docs.length} · antes ${antes} · insertados ${insertados} · después ${despues} · ` +
        `validador ${info.validator ? info.validationLevel + "/" + info.validationAction : "NO"} · no cumplen ${incumplen}`);
}
