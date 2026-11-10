import { useEffect, useMemo, useRef, useState } from "react";
import { listarSalas } from "../api/catalogos";
import { listarClientes } from "../api/clientes";
import { crearComprobante } from "../api/comprobantes";
import { listarVinos } from "../api/vinos";
import ErrorBanner from "../components/ErrorBanner";
import Loading from "../components/Loading";
import Tabla from "../components/Tabla";
import { useApi } from "../hooks/useApi";
import "./NuevaVenta.css";

const LIMITE_CLIENTES = 100;
const LIMITE_VINOS = 100;

const fmtImporte = (v) =>
  v === null || v === undefined
    ? "—"
    : `$ ${Number(v).toLocaleString("es-AR", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

const textoSala = (s) => `Sala ${s.id_sala} — ${s.calle} ${s.numero}`;

export default function NuevaVenta() {
  const salas = useApi(listarSalas, []);

  const [busquedaCliente, setBusquedaCliente] = useState("");
  const [filtroCliente, setFiltroCliente] = useState("");
  useEffect(() => {
    const timer = setTimeout(() => setFiltroCliente(busquedaCliente.trim()), 300);
    return () => clearTimeout(timer);
  }, [busquedaCliente]);

  const clientes = useApi(
    () => listarClientes({ nombre: filtroCliente, limit: LIMITE_CLIENTES }),
    [filtroCliente]
  );

  const [vinos, setVinos] = useState([]);
  const [cargandoVinos, setCargandoVinos] = useState(true);
  const [errorVinos, setErrorVinos] = useState(null);
  useEffect(() => {
    let activo = true;
    const cargar = async () => {
      setCargandoVinos(true);
      setErrorVinos(null);
      try {
        const primera = await listarVinos({ page: 1, limit: LIMITE_VINOS });
        const paginas = Math.max(1, Math.ceil(primera.total / primera.limit));
        const restantes = await Promise.all(
          Array.from({ length: paginas - 1 }, (_, i) =>
            listarVinos({ page: i + 2, limit: LIMITE_VINOS })
          )
        );
        if (activo) setVinos([...primera.items, ...restantes.flatMap((r) => r.items)]);
      } catch (err) {
        if (activo) setErrorVinos(err);
      } finally {
        if (activo) setCargandoVinos(false);
      }
    };
    cargar();
    return () => {
      activo = false;
    };
  }, []);

  const [clienteSel, setClienteSel] = useState(null);
  const [salaId, setSalaId] = useState("");
  const [busquedaVino, setBusquedaVino] = useState("");
  const [vinoSel, setVinoSel] = useState("");
  const [cantidad, setCantidad] = useState("1");

  const [carrito, setCarrito] = useState([]);
  const [nombresVino, setNombresVino] = useState({});

  const [comprobante, setComprobante] = useState(null);
  const [contexto, setContexto] = useState(null);
  const [error, setError] = useState(null);
  const [enviando, setEnviando] = useState(false);
  const bannerRef = useRef(null);

  useEffect(() => {
    if (error && bannerRef.current) bannerRef.current.scrollIntoView({ behavior: "smooth", block: "start" });
  }, [error]);

  const itemsClientes = clientes.data?.items || [];
  const opcionesClientes =
    clienteSel && !itemsClientes.some((c) => c.id === clienteSel.id)
      ? [clienteSel, ...itemsClientes]
      : itemsClientes;

  const salaSel = (salas.data || []).find((s) => s.id_sala === Number(salaId)) || null;

  const vinosFiltrados = useMemo(() => {
    const texto = busquedaVino.trim().toLowerCase();
    if (!texto) return vinos;
    return vinos.filter((v) =>
      `${v.nombre} ${v.bodega} ${v.tipo} ${v.anada}`.toLowerCase().includes(texto)
    );
  }, [vinos, busquedaVino]);

  const cantidadNum = Number(cantidad);
  const puedeAgregar = Boolean(vinoSel) && Number.isInteger(cantidadNum) && cantidadNum > 0;
  const puedeConfirmar =
    Boolean(clienteSel) && Boolean(salaId) && carrito.length > 0 && !enviando && !comprobante;

  const elegirCliente = (id) => {
    const cliente = opcionesClientes.find((c) => c.id === Number(id)) || null;
    setClienteSel(cliente);
  };

  const agregarRenglon = () => {
    if (!puedeAgregar) return;
    const cod = Number(vinoSel);
    const vino = vinos.find((v) => v.id === cod);
    setNombresVino((m) => ({ ...m, [cod]: vino?.nombre || `Vino ${cod}` }));
    setCarrito((filas) => {
      const existente = filas.find((f) => f.cod_vino === cod);
      if (existente) {
        return filas.map((f) =>
          f.cod_vino === cod ? { ...f, cantidad: f.cantidad + cantidadNum } : f
        );
      }
      return [...filas, { cod_vino: cod, cantidad: cantidadNum }];
    });
    setVinoSel("");
    setCantidad("1");
  };

  const quitarRenglon = (cod) => setCarrito((filas) => filas.filter((f) => f.cod_vino !== cod));

  const confirmar = async (e) => {
    e.preventDefault();
    if (!puedeConfirmar) return;
    setEnviando(true);
    setError(null);
    try {
      const creado = await crearComprobante({
        id_sala: Number(salaId),
        id_cliente: clienteSel.id,
        renglones: carrito,
      });
      setComprobante(creado);
      setContexto({ cliente: clienteSel, sala: salaSel });
    } catch (err) {
      setError(err);
    } finally {
      setEnviando(false);
    }
  };

  const nuevaVenta = () => {
    setBusquedaCliente("");
    setFiltroCliente("");
    setClienteSel(null);
    setSalaId("");
    setBusquedaVino("");
    setVinoSel("");
    setCantidad("1");
    setCarrito([]);
    setNombresVino({});
    setComprobante(null);
    setContexto(null);
    setError(null);
  };

  const columnasCarrito = [
    { clave: "vino", titulo: "Vino", render: (f) => nombresVino[f.cod_vino] || `Vino ${f.cod_vino}` },
    { clave: "cantidad", titulo: "Cantidad" },
    {
      clave: "acciones",
      titulo: "",
      render: (f) => (
        <button type="button" className="secundario" onClick={() => quitarRenglon(f.cod_vino)}>
          Quitar
        </button>
      ),
    },
  ];

  const columnasComprobante = [
    { clave: "vino", titulo: "Vino" },
    { clave: "cantidad", titulo: "Cantidad" },
    { clave: "precio_unit", titulo: "Precio unitario", render: (r) => fmtImporte(r.precio_unit) },
    { clave: "descuento", titulo: "Descuento", render: (r) => fmtImporte(r.descuento) },
    { clave: "subtotal", titulo: "Subtotal", render: (r) => fmtImporte(r.subtotal) },
  ];

  return (
    <section className="nueva-venta">
      <h2>Nueva venta</h2>

      <div ref={bannerRef}>
        <ErrorBanner
          error={error}
          onCerrar={() => {
            setError(null);
          }}
        />
      </div>
      <ErrorBanner error={clientes.error || salas.error || errorVinos} />

      <form onSubmit={confirmar}>
        <div className="nueva-venta-bloque">
          <h3>Cliente y sala</h3>
          <div className="nueva-venta-selectores">
            <label>
              Buscar cliente
              <input
                type="text"
                value={busquedaCliente}
                onChange={(e) => setBusquedaCliente(e.target.value)}
                placeholder="Nombre, apellido o razón social"
              />
            </label>

            <label>
              Cliente
              <select
                value={clienteSel ? clienteSel.id : ""}
                onChange={(e) => elegirCliente(e.target.value)}
              >
                <option value="">Elegir…</option>
                {opcionesClientes.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.nombre} ({c.tipo_cliente})
                  </option>
                ))}
              </select>
            </label>

            <label>
              Sala
              <select value={salaId} onChange={(e) => setSalaId(e.target.value)}>
                <option value="">Elegir…</option>
                {(salas.data || []).map((s) => (
                  <option key={s.id_sala} value={s.id_sala}>
                    {textoSala(s)}
                  </option>
                ))}
              </select>
            </label>
          </div>
          {clientes.loading && <Loading />}
        </div>

        <div className="nueva-venta-bloque">
          <h3>Renglones</h3>
          <div className="nueva-venta-agregar">
            <label>
              Buscar vino
              <input
                type="text"
                value={busquedaVino}
                onChange={(e) => setBusquedaVino(e.target.value)}
                placeholder="Nombre, bodega, tipo o añada"
              />
            </label>

            <label>
              Vino
              <select value={vinoSel} onChange={(e) => setVinoSel(e.target.value)}>
                <option value="">Elegir…</option>
                {vinosFiltrados.map((v) => (
                  <option key={v.id} value={v.id}>
                    {v.nombre} — {v.tipo} {v.anada} ({v.volumen} ml)
                  </option>
                ))}
              </select>
            </label>

            <label>
              Cantidad
              <input
                type="number"
                min="1"
                step="1"
                value={cantidad}
                onChange={(e) => setCantidad(e.target.value)}
              />
            </label>

            <button type="button" onClick={agregarRenglon} disabled={!puedeAgregar}>
              Agregar
            </button>
          </div>

          {cargandoVinos && <Loading />}
          {!cargandoVinos && busquedaVino.trim() && vinosFiltrados.length === 0 && (
            <p className="vacio">No hay vinos que coincidan con la búsqueda.</p>
          )}

          <h4>Carrito</h4>
          <Tabla
            columnas={columnasCarrito}
            filas={carrito}
            clave="cod_vino"
            vacio="Todavía no agregaste renglones."
          />
        </div>

        <div className="nueva-venta-acciones">
          <button type="submit" disabled={!puedeConfirmar}>
            {enviando ? "Confirmando…" : "Confirmar venta"}
          </button>
        </div>
      </form>

      {comprobante && (
        <div className="nueva-venta-comprobante">
          <h3>Comprobante N° {comprobante.numero}</h3>
          <p>
            <strong>Fecha:</strong> {comprobante.fecha}
          </p>
          <p>
            <strong>Cliente:</strong>{" "}
            {contexto?.cliente ? `${contexto.cliente.nombre} (ID ${comprobante.id_cliente})` : `ID ${comprobante.id_cliente}`}
          </p>
          <p>
            <strong>Sala:</strong>{" "}
            {contexto?.sala
              ? `${textoSala(contexto.sala)} (ID ${comprobante.id_sala})`
              : `ID ${comprobante.id_sala}`}
          </p>

          <Tabla
            columnas={columnasComprobante}
            filas={comprobante.renglones}
            clave="cod_vino"
            vacio="El comprobante no tiene renglones."
          />

          <dl className="nueva-venta-totales">
            <dt>Subtotal</dt>
            <dd>{fmtImporte(comprobante.subtotal)}</dd>
            <dt>Descuento</dt>
            <dd>{fmtImporte(comprobante.descuento)}</dd>
            <dt className="nueva-venta-total">Total</dt>
            <dd className="nueva-venta-total">{fmtImporte(comprobante.total)}</dd>
          </dl>

          <div className="nueva-venta-acciones">
            <button type="button" onClick={nuevaVenta}>
              Nueva venta
            </button>
          </div>
        </div>
      )}
    </section>
  );
}
