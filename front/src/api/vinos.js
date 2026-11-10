import { request } from "./client";

// GET /vinos?tipo=&cepa=&bodega=&anada=&page=&limit=
// -> { page, limit, total, items: [{ id, nombre, tipo, anada, volumen, precio, graduacion, cuit_bodega, bodega }] }
export const listarVinos = (params) => request("/vinos", { params });

// GET /vinos/{cod} -> vino + cepas [{ id_cepa, cepa, tipo, porcentaje }] + maridajes [{ id, maridaje, temperatura }]
export const obtenerVino = (cod) => request(`/vinos/${cod}`);

// POST /vinos
// body: { nombre, volumen, precio, graduacion, tipo, anada, cuit_bodega,
//         composicion: [{ id_cepa, porcentaje }], maridajes: [id_maridaje] }
export const crearVino = (body) => request("/vinos", { method: "POST", body });

// PUT /vinos/{cod} (mismo body; composicion y maridajes opcionales: si no se envían, no se tocan)
export const modificarVino = (cod, body) => request(`/vinos/${cod}`, { method: "PUT", body });

// DELETE /vinos/{cod} -> 204
export const eliminarVino = (cod) => request(`/vinos/${cod}`, { method: "DELETE" });

// GET /vinos/{cod}/auditoria-precio -> [{ id, precio_anterior, precio_nuevo, fecha, hora, usuario }]
export const auditoriaPrecio = (cod) => request(`/vinos/${cod}/auditoria-precio`);
