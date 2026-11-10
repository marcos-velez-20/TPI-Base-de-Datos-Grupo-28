import { request } from "./client";

// GET /transferencias?estado=&id_sala=&page=&limit=
// estado: en_confeccion | terminado | procesado
// -> { page, limit, total, items: [{ num_solicitud, fecha_confeccion, estado, id_sala }] }
export const listarTransferencias = (params) => request("/transferencias", { params });

// GET /transferencias/{nro} -> cabecera + renglones: [{ cod_vino, vino, cantidad }]
export const obtenerTransferencia = (nro) => request(`/transferencias/${nro}`);

// POST /transferencias { id_sala }  (la fecha la fuerza la base, RN-11)
export const crearTransferencia = (id_sala) => request("/transferencias", { method: "POST", body: { id_sala } });

// POST /transferencias/{nro}/renglones { cod_vino, cantidad }  (solo en_confeccion, RN-12)
export const agregarRenglonTransferencia = (nro, body) =>
  request(`/transferencias/${nro}/renglones`, { method: "POST", body });

// POST /transferencias/{nro}/terminar
export const terminarTransferencia = (nro) => request(`/transferencias/${nro}/terminar`, { method: "POST" });

// POST /transferencias/{nro}/procesar
export const procesarTransferencia = (nro) => request(`/transferencias/${nro}/procesar`, { method: "POST" });
