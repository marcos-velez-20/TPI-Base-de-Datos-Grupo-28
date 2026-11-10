import { request } from "./client";

// Ingresos al depósito (misma mecánica de estados que las transferencias). Disponible por si se necesita.
export const crearIngreso = (body) => request("/ingresos", { method: "POST", body }); // { cuit_bodega, cod_transporte }
export const obtenerIngreso = (cod) => request(`/ingresos/${cod}`);
export const agregarRenglonIngreso = (cod, body) => request(`/ingresos/${cod}/renglones`, { method: "POST", body });
export const terminarIngreso = (cod) => request(`/ingresos/${cod}/terminar`, { method: "POST" });
export const procesarIngreso = (cod) => request(`/ingresos/${cod}/procesar`, { method: "POST" });
