/**
 * Muestra un error de la API tal cual lo devolvió (sin reemplazarlo por un texto genérico).
 * Uso: <ErrorBanner error={error} />   (error es un ApiError, un Error o un string)
 */
export default function ErrorBanner({ error, onCerrar }) {
  if (!error) return null;
  const mensaje = typeof error === "string" ? error : error.mensaje || error.message || String(error);
  return (
    <div className="error-banner" role="alert">
      <div>
        <strong>{error.status ? `Error ${error.status}` : "Error"}</strong>
        <span className="error-mensaje">{mensaje}</span>
        {error.sqlstate && <small className="error-sqlstate">SQLSTATE {error.sqlstate}</small>}
      </div>
      {onCerrar && (
        <button type="button" className="enlace" onClick={onCerrar}>
          Cerrar
        </button>
      )}
    </div>
  );
}
