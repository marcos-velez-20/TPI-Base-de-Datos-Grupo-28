/** Usa los campos { page, limit, total } que devuelve la API en los listados paginados. */
export default function Paginador({ page, limit, total, onChange }) {
  const paginas = Math.max(1, Math.ceil(total / limit));
  return (
    <div className="paginador">
      <button type="button" disabled={page <= 1} onClick={() => onChange(page - 1)}>
        ← Anterior
      </button>
      <span>
        Página {page} de {paginas} · {total} resultados
      </span>
      <button type="button" disabled={page >= paginas} onClick={() => onChange(page + 1)}>
        Siguiente →
      </button>
    </div>
  );
}
