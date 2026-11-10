import { request } from "./client";

// GET /clientes?tipo=&nombre=&page=&limit= -> { page, limit, total, items: [...] }
export const listarClientes = (params) => request("/clientes", { params });

// GET /clientes/{id}
export const obtenerCliente = (id) => request(`/clientes/${id}`);

// POST /clientes (body: ver schemas.ClienteIn en la API)
export const crearCliente = (body) => request("/clientes", { method: "POST", body });

// PUT /clientes/{id}
export const modificarCliente = (id, body) => request(`/clientes/${id}`, { method: "PUT", body });

// DELETE /clientes/{id} -> 204
export const eliminarCliente = (id) => request(`/clientes/${id}`, { method: "DELETE" });
