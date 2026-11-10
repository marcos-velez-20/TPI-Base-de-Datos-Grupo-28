import { useState } from "react";
import { Link, useNavigate, useParams, useSearchParams } from "react-router-dom";
import { listarBodegas, listarSalas } from "../api/catalogos";
import {
  agregarRenglonTransferencia,
  crearTransferencia,
  listarTransferencias,
  obtenerTransferencia,
  procesarTransferencia,
  terminarTransferencia,
} from "../api/transferencias";
import { listarVinos } from "../api/vinos";
import ErrorBanner from "../components/ErrorBanner";
import Loading from "../components/Loading";
import Paginador from "../components/Paginador";
import Tabla from "../components/Tabla";
import { useApi } from "../hooks/useApi";
import "./Transferencias.css";

const ESTADOS = ["en_confeccion", "terminado", "procesado"];
const LIMITE = 10;

const etiquetaSala = (s) => `Sala ${s.id_sala} · ${s.calle} ${s.numero}`;
// Si el campo está vacío se envía tal cual y la API informa el error; no se valida en el cliente.
const numero = (v) => (v === "" ? v : Number(v));

function Estado({ estado }) {
  return <span className={`badge badge-${estado}`}>{String(estado).replace(/_/g, " ")}</span>;
}

/* ------------------------------ Listado ------------------------------ */
function Listado() {
  const navigate = useNavigate();
  const [params, setParams] = useSearchParams();
  const estado = params.get("estado") || "";
  const sala = params.get("id_sala") || "";
  const page = Math.max(1, parseInt(params.get("page"), 10) || 1);

  const salas = useApi(listarSalas, []);
  const lista = useApi(
    () => listarTransferencias({ estado, id_sala: sala, page, limit: LIMITE }),
    [estado, sala, page]
  );

  const [nuevaSala, setNuevaSala] = useState("");
  const [creando, setCreando] = useState(false);
  const [errorCrear, setErrorCrear] = useState(null);

  const cambiar = (clave, valor) => {
    const siguiente = new URLSearchParams(params);
    if (valor) siguiente.set(clave, valor);
    else siguiente.delete(clave);
    if (clave !== "page") siguiente.delete("page");
    setParams(siguiente);
  };

  // No se envía fecha: la fuerza la base de datos (RN-11). Se muestra la que devuelve la API.
  const crear = async (e) => {
    e.preventDefault();
    setCreando(true);
    setErrorCrear(null);
    try {
      const nueva = await crearTransferencia(numero(nuevaSala));
      navigate(`/transferencias/${nueva.num_solicitud}`);
    } catch (err) {
      setErrorCrear(err);
      setCreando(false);
    }
  };

  const columnas = [
    { clave: "num_solicitud", titulo: "N°" },
    { clave: "id_sala", titulo: "Sala" },
    { clave: "fecha_confeccion", titulo: "Fecha de confección" },
    { clave: "estado", titulo: "Estado", render: (t) => <Estado estado={t.estado} /> },
    {
      clave: "acciones",
      titulo: "",
      render: (t) => (
        <Link className="tr-boton" to={`/transferencias/${t.num_solicitud}`}>
          Abrir
        </Link>
      ),
    },
  ];

  return (
    <section>
      <h2>Transferencias</h2>

      <form className="tr-caja" onSubmit={crear}>
        <label>
          Nueva transferencia: sala solicitante
          <select value={nuevaSala} onChange={(e) => setNuevaSala(e.target.value)}>
            <option value="">Elegir sala…</option>
            {(salas.data || []).map((s) => (
              <option key={s.id_sala} value={s.id_sala}>
                {etiquetaSala(s)}
              </option>
            ))}
          </select>
        </label>
        <button type="submit" disabled={creando || nuevaSala === ""}>
          Crear
        </button>
      </form>
      <ErrorBanner error={errorCrear} onCerrar={() => setErrorCrear(null)} />
      <ErrorBanner error={salas.error} />

      <div className="tr-caja">
        <label>
          Estado
          <select value={estado} onChange={(e) => cambiar("estado", e.target.value)}>
            <option value="">Todos</option>
            {ESTADOS.map((e) => (
              <option key={e} value={e}>
                {e.replace(/_/g, " ")}
              </option>
            ))}
          </select>
        </label>
        <label>
          Sala
          <select value={sala} onChange={(e) => cambiar("id_sala", e.target.value)}>
            <option value="">Todas</option>
            {(salas.data || []).map((s) => (
              <option key={s.id_sala} value={s.id_sala}>
                {etiquetaSala(s)}
              </option>
            ))}
          </select>
        </label>
        <button type="button" className="secundario" disabled={!estado && !sala} onClick={() => setParams({})}>
          Limpiar filtros
        </button>
      </div>

      <ErrorBanner error={lista.error} />
      {lista.loading && !lista.data && <Loading />}
      {lista.data && (
        <>
          <Tabla columnas={columnas} filas={lista.data.items} clave="num_solicitud" vacio="No hay transferencias." />
          <Paginador
            page={lista.data.page}
            limit={lista.data.limit}
            total={lista.data.total}
            onChange={(p) => cambiar("page", String(p))}
          />
        </>
      )}
    </section>
  );
}

/* --------------------- Formulario de renglón (en_confeccion) --------------------- */
function NuevoRenglon({ nro, ejecutar, ocupado }) {
  const [cuit, setCuit] = useState("");
  const [codVino, setCodVino] = useState("");
  const [cantidad, setCantidad] = useState("");
  const bodegas = useApi(listarBodegas, []);
  // Ayuda para elegir: vinos (hasta 100) de la bodega elegida; el código también se puede escribir.
  const vinos = useApi(() => listarVinos({ bodega: cuit, limit: 100 }), [cuit]);

  const enviar = (e) => {
    e.preventDefault();
    ejecutar(async () => {
      await agregarRenglonTransferencia(nro, { cod_vino: numero(codVino), cantidad: numero(cantidad) });
      setCantidad("");
    });
  };

  return (
    <form className="tr-caja" onSubmit={enviar}>
      <ErrorBanner error={bodegas.error || vinos.error} />
      <label>
        Bodega (para filtrar)
        <select value={cuit} onChange={(e) => setCuit(e.target.value)}>
          <option value="">Todas</option>
          {(bodegas.data || []).map((b) => (
            <option key={b.cuit} value={b.cuit}>
              {b.razon_social}
            </option>
          ))}
        </select>
      </label>
      <label>
        Vino
        <select value={codVino} onChange={(e) => setCodVino(e.target.value)}>
          <option value="">Elegir vino…</option>
          {((vinos.data && vinos.data.items) || []).map((v) => (
            <option key={v.id} value={v.id}>
              {v.nombre} {v.anada} · {v.volumen} ml (cód. {v.id})
            </option>
          ))}
        </select>
      </label>
      <label>
        Código de vino
        <input type="number" value={codVino} onChange={(e) => setCodVino(e.target.value)} />
      </label>
      <label>
        Cantidad
        <input type="number" value={cantidad} onChange={(e) => setCantidad(e.target.value)} />
      </label>
      <button type="submit" disabled={ocupado}>
        Agregar renglón
      </button>
    </form>
  );
}

/* ------------------------------ Detalle ------------------------------ */
function Detalle({ nro }) {
  const { data: t, error, loading, recargar } = useApi(() => obtenerTransferencia(nro), [nro]);
  const [errorAccion, setErrorAccion] = useState(null);
  const [ocupado, setOcupado] = useState(false);

  // Ejecuta una acción contra la API y SIEMPRE recarga desde la API (el estado no se toca a mano).
  const ejecutar = async (accion) => {
    setOcupado(true);
    setErrorAccion(null);
    try {
      await accion();
    } catch (e) {
      setErrorAccion(e);
    } finally {
      setOcupado(false);
      recargar();
    }
  };

  return (
    <section>
      <div className="tr-cabecera">
        <h2>Transferencia N° {nro}</h2>
        <Link className="tr-boton tr-secundario" to="/transferencias">
          ← Volver al listado
        </Link>
      </div>

      <ErrorBanner error={error} />
      <ErrorBanner error={errorAccion} onCerrar={() => setErrorAccion(null)} />
      {loading && !t && <Loading />}

      {t && (
        <>
          <div className="tr-caja tr-ficha">
            <div>
              <small>Sala</small>
              <strong>{t.id_sala}</strong>
            </div>
            <div>
              <small>Fecha de confección</small>
              <strong>{t.fecha_confeccion}</strong>
            </div>
            <div>
              <small>Estado</small>
              <Estado estado={t.estado} />
            </div>
            <div className="tr-botones">
              <button
                type="button"
                disabled={ocupado || t.estado !== "en_confeccion"}
                onClick={() => ejecutar(() => terminarTransferencia(nro))}
              >
                Terminar
              </button>
              <button
                type="button"
                disabled={ocupado || t.estado !== "terminado"}
                onClick={() => ejecutar(() => procesarTransferencia(nro))}
              >
                Procesar
              </button>
            </div>
          </div>

          <h3>Renglones</h3>
          <Tabla
            clave="cod_vino"
            vacio="Todavía no tiene renglones."
            columnas={[
              { clave: "cod_vino", titulo: "Cód. vino" },
              { clave: "vino", titulo: "Vino" },
              { clave: "cantidad", titulo: "Cantidad" },
            ]}
            filas={t.renglones}
          />

          {t.estado === "en_confeccion" ? (
            <>
              <h3>Agregar renglón</h3>
              <NuevoRenglon nro={nro} ejecutar={ejecutar} ocupado={ocupado} />
            </>
          ) : (
            <p className="vacio">La transferencia está {String(t.estado).replace(/_/g, " ")}: ya no admite renglones.</p>
          )}
        </>
      )}
    </section>
  );
}

/* La misma página resuelve /transferencias (listado) y /transferencias/:nro (detalle). */
export default function Transferencias() {
  const { nro } = useParams();
  return nro ? <Detalle key={nro} nro={nro} /> : <Listado />;
}
