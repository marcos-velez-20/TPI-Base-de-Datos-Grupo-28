/**
 * Tabla simple.
 *   columnas: [{ clave: "nombre", titulo: "Nombre", render: (fila) => ... }]  (render es opcional)
 *   filas:    array de objetos tal cual los devuelve la API
 *   clave:    campo (o función) que identifica cada fila, por defecto "id"
 */
export default function Tabla({ columnas, filas, vacio = "Sin resultados", clave = "id" }) {
  if (!filas || filas.length === 0) return <p className="vacio">{vacio}</p>;
  return (
    <table className="tabla">
      <thead>
        <tr>
          {columnas.map((c) => (
            <th key={c.clave}>{c.titulo}</th>
          ))}
        </tr>
      </thead>
      <tbody>
        {filas.map((fila, i) => (
          <tr key={typeof clave === "function" ? clave(fila) : fila[clave] ?? i}>
            {columnas.map((c) => (
              <td key={c.clave}>{c.render ? c.render(fila) : fila[c.clave]}</td>
            ))}
          </tr>
        ))}
      </tbody>
    </table>
  );
}
