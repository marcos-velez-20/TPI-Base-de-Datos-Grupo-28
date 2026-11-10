import { request } from "./client";

// GET /salud -> { estado: "ok", base_de_datos: "conectada" }
export const salud = () => request("/salud");
