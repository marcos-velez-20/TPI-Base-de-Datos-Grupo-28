// Única puerta de salida HTTP del front. Los componentes NUNCA llaman a fetch directamente.

const API_URL_POR_DEFECTO = "http://localhost:8000";

/** URL base de la API: config.js (runtime) > VITE_API_URL (build) > valor por defecto. */
export function getApiUrl() {
  const runtime = typeof window !== "undefined" && window.__CONFIG__ && window.__CONFIG__.API_URL;
  const url = runtime || import.meta.env.VITE_API_URL || API_URL_POR_DEFECTO;
  return String(url).replace(/\/+$/, "");
}

/** Error de la API. Conserva el mensaje EXACTO que devolvió la base/API. */
export class ApiError extends Error {
  constructor(status, mensaje, sqlstate = null) {
    super(mensaje);
    this.name = "ApiError";
    this.status = status;
    this.mensaje = mensaje;
    this.sqlstate = sqlstate;
  }
}

// El campo "detail" es un string en los errores de la base, pero FastAPI devuelve una
// lista de objetos en los errores de validación (422). Se convierte a texto sin perder datos.
function detalleATexto(detail) {
  if (typeof detail === "string") return detail;
  if (Array.isArray(detail)) {
    return detail
      .map((d) => {
        const campo = Array.isArray(d.loc) ? d.loc.filter((x) => x !== "body" && x !== "query").join(".") : "";
        return campo ? `${campo}: ${d.msg}` : d.msg || JSON.stringify(d);
      })
      .join(" | ");
  }
  if (detail && typeof detail === "object") return JSON.stringify(detail);
  return "";
}

function armarQuery(params) {
  const qs = new URLSearchParams();
  Object.entries(params || {}).forEach(([clave, valor]) => {
    if (valor !== undefined && valor !== null && valor !== "") qs.append(clave, valor);
  });
  const texto = qs.toString();
  return texto ? `?${texto}` : "";
}

/**
 * request("/vinos", { method, params, body })
 * Devuelve el JSON de la respuesta (o null si es 204). Si la respuesta no es 2xx lanza ApiError.
 */
export async function request(path, { method = "GET", params, body } = {}) {
  const opciones = { method, headers: { Accept: "application/json" } };
  if (body !== undefined) {
    opciones.headers["Content-Type"] = "application/json";
    opciones.body = JSON.stringify(body);
  }

  let respuesta;
  try {
    respuesta = await fetch(getApiUrl() + path + armarQuery(params), opciones);
  } catch (e) {
    throw new ApiError(0, `No se pudo conectar con la API (${getApiUrl()})`);
  }

  if (respuesta.status === 204) return null;

  let datos = null;
  try {
    datos = await respuesta.json();
  } catch (e) {
    datos = null;
  }

  if (!respuesta.ok) {
    const mensaje = detalleATexto(datos && datos.detail) || respuesta.statusText || "Error desconocido";
    throw new ApiError(respuesta.status, mensaje, datos ? datos.sqlstate ?? null : null);
  }
  return datos;
}
