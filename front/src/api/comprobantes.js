import { request } from "./client";

// POST /comprobantes
// body: { id_sala, id_cliente, renglones: [{ cod_vino, cantidad }] }
// -> { numero, fecha, subtotal, descuento, total, id_sala, id_cliente,
//      renglones: [{ cod_vino, vino, cantidad, precio_unit, descuento, subtotal }] }
// Todos los importes los calcula la base de datos; el front solo los muestra.
export const crearComprobante = (body) => request("/comprobantes", { method: "POST", body });

// GET /comprobantes/{nro}
export const obtenerComprobante = (nro) => request(`/comprobantes/${nro}`);
