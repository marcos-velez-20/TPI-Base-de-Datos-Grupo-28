import { Link, useLocation, useParams, useSearchParams } from "react-router-dom";
import { listarAnadas, listarBodegas, listarCepas } from "../api/catalogos";
import { listarVinos, obtenerVino } from "../api/vinos";
import ErrorBanner from "../components/ErrorBanner";
import Loading from "../components/Loading";
import Paginador from "../components/Paginador";
import Tabla from "../components/Tabla";
import { useApi } from "../hooks/useApi";
import "./Catalogo.css";

const TIPOS = ["tinto", "blanco", "rosado", "espumante"];
const LIMITE = 10;

// Solo formateo para mostrar: los valores vienen tal cual de la API.
const fmtPrecio = (v) =>
  `$ ${Number(v).toLocaleString("es-AR", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

/* ------------------------------ Listado ------------------------------ */
function Listado() {
  const location = useLocation();
  const [params, setParams] = useSearchParams();

  // Filtros y página viven en la URL, así el enlace se puede compartir.
  const tipo = params.get("tipo") || "";
  const cepa = params.get("cepa") || "";
  const bodega = params.get("bodega") || "";
  const anada = params.get("anada") || "";
  const page = Math.max(1, parseInt(params.get("page"), 10) || 1);

  const cepas = useApi(listarCepas, []);
  const bodegas = useApi(listarBodegas, []);
  const anadas = useApi(listarAnadas, []);
  const vinos = useApi(
    () => listarVinos({ tipo, cepa, bodega, anada, page, limit: LIMITE }),
    [tipo, cepa, bodega, anada, page]
  );

  const cambiar = (clave, valor) => {
    const siguiente = new URLSearchParams(params);
    if (valor) siguiente.set(clave, valor);
    else siguiente.delete(clave);
    if (clave !== "page") siguiente.delete("page"); // al cambiar un filtro se vuelve a la página 1
    setParams(siguiente);
  };

  const hayFiltros = tipo || cepa || bodega || anada;

  const columnas = [
    { clave: "nombre", titulo: "Nombre" },
    { clave: "tipo", titulo: "Tipo" },
    { clave: "anada", titulo: "Añada" },
    { clave: "volumen", titulo: "Presentación", render: (v) => `${v.volumen} ml` },
    { clave: "graduacion", titulo: "Graduación", render: (v) => `${Number(v.graduacion)} °` },
    { clave: "precio", titulo: "Precio", render: (v) => fmtPrecio(v.precio) },
    { clave: "bodega", titulo: "Bodega" },
    {
      clave: "acciones",
      titulo: "",
      render: (v) => (
        <span className="acciones">
          <Link className="boton-enlace" to={`/vinos/${v.id}`} state={{ volver: location.search }}>
            Ver detalle
          </Link>
          <Link className="boton-enlace secundario" to={`/vinos/${v.id}/editar`}>
            Editar
          </Link>
        </span>
      ),
    },
  ];

  return (
    <section>
      <div className="catalogo-cabecera">
        <h2>Catálogo de vinos</h2>
        <Link className="boton-enlace" to="/vinos/nuevo">
          + Nuevo vino
        </Link>
      </div>

      <ErrorBanner error={cepas.error || bodegas.error || anadas.error} />

      <div className="filtros">
        <label>
          Tipo
          <select value={tipo} onChange={(e) => cambiar("tipo", e.target.value)}>
            <option value="">Todos</option>
            {TIPOS.map((t) => (
              <option key={t} value={t}>
                {t}
              </option>
            ))}
          </select>
        </label>
        <label>
          Cepa
          <select value={cepa} onChange={(e) => cambiar("cepa", e.target.value)}>
            <option value="">Todas</option>
            {(cepas.data || []).map((c) => (
              <option key={c.id_cepa} value={c.nombre}>
                {c.nombre}
              </option>
            ))}
          </select>
        </label>
        <label>
          Bodega
          <select value={bodega} onChange={(e) => cambiar("bodega", e.target.value)}>
            <option value="">Todas</option>
            {(bodegas.data || []).map((b) => (
              <option key={b.cuit} value={b.cuit}>
                {b.razon_social}
              </option>
            ))}
          </select>
        </label>
        <label>
          Añada
          <select value={anada} onChange={(e) => cambiar("anada", e.target.value)}>
            <option value="">Todas</option>
            {(anadas.data || []).map((a) => (
              <option key={a} value={a}>
                {a}
              </option>
            ))}
          </select>
        </label>
        <button type="button" className="secundario" disabled={!hayFiltros} onClick={() => setParams({})}>
          Limpiar filtros
        </button>
      </div>

      <ErrorBanner error={vinos.error} />
      {vinos.loading && <Loading />}
      {!vinos.loading && vinos.data && (
        <>
          <Tabla
            columnas={columnas}
            filas={vinos.data.items}
            vacio="No hay vinos que coincidan con los filtros."
          />
          <Paginador
            page={vinos.data.page}
            limit={vinos.data.limit}
            total={vinos.data.total}
            onChange={(p) => cambiar("page", String(p))}
          />
        </>
      )}
    </section>
  );
}

/* ------------------------------ Detalle ------------------------------ */
function Detalle({ cod }) {
  const location = useLocation();
  const { data: vino, error, loading } = useApi(() => obtenerVino(cod), [cod]);
  const volver = "/vinos" + ((location.state && location.state.volver) || "");

  return (
    <section>
      <div className="catalogo-cabecera">
        <h2>Detalle del vino</h2>
        <span className="acciones">
          <Link className="boton-enlace secundario" to={volver}>
            ← Volver al listado
          </Link>
          <Link className="boton-enlace" to={`/vinos/${cod}/editar`}>
            Editar
          </Link>
        </span>
      </div>

      <ErrorBanner error={error} />
      {loading && <Loading />}

      {vino && (
        <>
          <div className="ficha">
            <h3>{vino.nombre}</h3>
            <dl>
              <dt>Tipo</dt>
              <dd>{vino.tipo}</dd>
              <dt>Añada</dt>
              <dd>{vino.anada}</dd>
              <dt>Presentación</dt>
              <dd>{vino.volumen} ml</dd>
              <dt>Graduación</dt>
              <dd>{Number(vino.graduacion)} °</dd>
              <dt>Precio</dt>
              <dd>{fmtPrecio(vino.precio)}</dd>
              <dt>Bodega</dt>
              <dd>
                {vino.bodega} <small>(CUIT {vino.cuit_bodega})</small>
              </dd>
            </dl>
          </div>

          <h3>Composición</h3>
          <Tabla
            clave="id_cepa"
            vacio="Este vino no tiene composición cargada."
            columnas={[
              { clave: "cepa", titulo: "Cepa" },
              { clave: "tipo", titulo: "Tipo de cepa" },
              { clave: "porcentaje", titulo: "Porcentaje", render: (c) => `${Number(c.porcentaje)} %` },
            ]}
            filas={vino.cepas}
          />

          <h3>Maridajes</h3>
          <Tabla
            clave="id"
            vacio="Este vino no tiene maridajes cargados."
            columnas={[
              { clave: "maridaje", titulo: "Maridaje" },
              { clave: "temperatura", titulo: "Temperatura de servicio", render: (m) => `${Number(m.temperatura)} °C` },
            ]}
            filas={vino.maridajes}
          />
        </>
      )}
    </section>
  );
}

/* La misma página resuelve /vinos (listado) y /vinos/:cod (detalle). */
export default function Catalogo() {
  const { cod } = useParams();
  return cod ? <Detalle key={cod} cod={cod} /> : <Listado />;
}
