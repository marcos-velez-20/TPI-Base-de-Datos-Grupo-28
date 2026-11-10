import { request } from "./client";

// Los reportes devuelven una lista simple (no paginada).

// GET /reportes/top-vinos?limit=10 -> [{ id, nombre, anada, volumen, botellas }]
export const topVinos = (limit = 10) => request("/reportes/top-vinos", { params: { limit } });

// GET /reportes/ventas-por-sala -> [{ id_sala, localidad, monto }]  (último trimestre, calculado en SQL)
export const ventasPorSala = () => request("/reportes/ventas-por-sala");

// GET /reportes/vinos-sin-stock?sala=<id> -> [{ id, nombre, stock_deposito }]
export const vinosSinStock = (sala) => request("/reportes/vinos-sin-stock", { params: { sala } });

// GET /reportes/transportista-mayor-actividad -> [{ cod_transporte, razon_social, ingresos }]
export const transportistaMayorActividad = () => request("/reportes/transportista-mayor-actividad");

// GET /reportes/ficha-vino/{cod}
export const fichaVino = (cod) => request(`/reportes/ficha-vino/${cod}`);
