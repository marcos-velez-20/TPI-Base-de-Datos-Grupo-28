import { request } from "./client";

// Listados chicos para filtros y selectores. Cada función devuelve directamente el array de items.
// Los listados paginados de la API tienen la forma { page, limit, total, items }.

// [{ id_cepa, nombre, tipo }]
export const listarCepas = () => request("/cepas", { params: { limit: 500 } }).then((r) => r.items);

// [{ cuit, razon_social, calle, num_calle }]
export const listarBodegas = () => request("/bodegas", { params: { limit: 500 } }).then((r) => r.items);

// [{ id_sala, calle, numero, dia_cierre, codigo_postal }]
export const listarSalas = () => request("/salas", { params: { limit: 500 } }).then((r) => r.items);

// [{ id, nombre, temperatura }]
export const listarMaridajes = () => request("/maridajes", { params: { limit: 500 } }).then((r) => r.items);

// GET /vinos/anadas devuelve items [{ anada: 2022 }, ...]; acá se devuelve [2022, ...]
export const listarAnadas = () =>
  request("/vinos/anadas", { params: { limit: 500 } }).then((r) => r.items.map((i) => i.anada));
