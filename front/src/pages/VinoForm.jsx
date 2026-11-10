import { useEffect, useRef, useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { listarBodegas, listarCepas, listarMaridajes } from "../api/catalogos";
import { crearVino, eliminarVino, modificarVino, obtenerVino } from "../api/vinos";
import ErrorBanner from "../components/ErrorBanner";
import Loading from "../components/Loading";
import { useApi } from "../hooks/useApi";
import "./VinoForm.css";

const TIPOS = ["tinto", "blanco", "rosado", "espumante"];
const VOLUMENES = [187, 375, 750, 1500, 3000]; // sugerencias (datalist); la base solo exige > 0

const FORM_VACIO = {
  nombre: "",
  tipo: "",
  anada: "",
  volumen: "",
  graduacion: "",
  precio: "",
  cuit_bodega: "",
};

/* Qué campo del formulario "nombra" cada mensaje de error. Solo sirve para RESALTAR el campo:
   el mensaje que se muestra es siempre el que devolvió la API, sin tocar. Un mismo mensaje puede
   resaltar varios campos (p. ej. el UNIQUE nombre + añada + volumen). */
const PISTAS_CAMPO = [
  ["nombre", /nombre/i],
  ["tipo", /\btipo\b|chk_vino_tipo/i],
  ["anada", /anada|añada/i],
  ["volumen", /volumen/i],
  ["graduacion", /graduacion|graduación/i],
  ["precio", /precio/i],
  ["cuit_bodega", /cuit_bodega|bodega/i],
  ["composicion", /RN-05|porcentaje|composicion|composición|cepa/i],
  ["maridajes", /maridaje/i],
];

function camposConError(error) {
  const texto = error ? `${error.mensaje || error.message || error}` : "";
  return new Set(PISTAS_CAMPO.filter(([, re]) => re.test(texto)).map(([campo]) => campo));
}

// Texto vacío -> null (la API responde con su propio mensaje de validación); si no, número.
const aEntero = (v) => (String(v).trim() === "" ? null : Number(v));
const aTexto = (v) => (String(v).trim() === "" ? null : String(v).trim());

/* ------------------------------ Formulario ------------------------------ */
function Formulario({ cod, inicial }) {
  const navigate = useNavigate();
  const esEdicion = Boolean(cod);

  const cepas = useApi(listarCepas, []);
  const bodegas = useApi(listarBodegas, []);
  const maridajes = useApi(listarMaridajes, []);

  const [form, setForm] = useState(inicial.form);
  const siguienteId = useRef(inicial.filas.length);
  const [filas, setFilas] = useState(inicial.filas); // [{ key, id_cepa, porcentaje }]
  const [maridajesSel, setMaridajesSel] = useState(inicial.maridajes); // [id_maridaje]
  const [error, setError] = useState(null);
  const [resaltados, setResaltados] = useState(new Set());
  const [enviando, setEnviando] = useState(false);
  const bannerRef = useRef(null);

  // Cada vez que aparece un error se lleva la vista al banner (queda arriba del formulario).
  useEffect(() => {
    if (error && bannerRef.current) bannerRef.current.scrollIntoView({ behavior: "smooth", block: "start" });
  }, [error]);

  const cambiar = (campo, valor) => setForm((f) => ({ ...f, [campo]: valor }));

  const agregarFila = () => {
    siguienteId.current += 1;
    setFilas((fs) => [...fs, { key: siguienteId.current, id_cepa: "", porcentaje: "" }]);
  };
  const quitarFila = (key) => setFilas((fs) => fs.filter((f) => f.key !== key));
  const cambiarFila = (key, campo, valor) =>
    setFilas((fs) => fs.map((f) => (f.key === key ? { ...f, [campo]: valor } : f)));

  const alternarMaridaje = (id) =>
    setMaridajesSel((sel) => (sel.includes(id) ? sel.filter((m) => m !== id) : [...sel, id]));

  // Dato INFORMATIVO. No bloquea el envío: la regla RN-05 la valida la base al COMMIT.
  const sumaActual = Math.round(filas.reduce((acc, f) => acc + (Number(f.porcentaje) || 0), 0) * 100) / 100;

  const guardar = async (e) => {
    e.preventDefault();
    setEnviando(true);
    setError(null);
    setResaltados(new Set());

    const body = {
      nombre: aTexto(form.nombre),
      tipo: aTexto(form.tipo),
      anada: aEntero(form.anada),
      volumen: aEntero(form.volumen),
      graduacion: aTexto(form.graduacion),
      precio: aTexto(form.precio),
      cuit_bodega: aTexto(form.cuit_bodega),
      composicion: filas.map((f) => ({
        id_cepa: aEntero(f.id_cepa),
        porcentaje: aTexto(f.porcentaje),
      })),
      maridajes: maridajesSel,
    };

    try {
      const guardado = esEdicion ? await modificarVino(cod, body) : await crearVino(body);
      navigate(`/vinos/${esEdicion ? cod : guardado.id}`);
    } catch (err) {
      setError(err);
      setResaltados(camposConError(err));
      setEnviando(false);
    }
  };

  const eliminar = async () => {
    if (!window.confirm(`¿Eliminar el vino "${form.nombre}"? Esta acción no se puede deshacer.`)) return;
    setEnviando(true);
    setError(null);
    setResaltados(new Set());
    try {
      await eliminarVino(cod);
      navigate("/vinos");
    } catch (err) {
      setError(err); // p. ej. RESTRICT por movimientos asociados: mensaje de la API tal cual
      setEnviando(false);
    }
  };

  const claseCampo = (campo) => (resaltados.has(campo) ? "campo-error" : "");

  return (
    <section>
      <h2>{esEdicion ? `Editar vino #${cod}` : "Nuevo vino"}</h2>

      {/* Error de guardado/borrado: siempre arriba del formulario */}
      <div ref={bannerRef}>
        <ErrorBanner error={error} onCerrar={() => { setError(null); setResaltados(new Set()); }} />
      </div>
      <ErrorBanner error={cepas.error || bodegas.error || maridajes.error} />

      <form className="vino-form" onSubmit={guardar} noValidate>
        <div className="vino-form-grilla">
          <label className={claseCampo("nombre")}>
            Nombre
            <input type="text" value={form.nombre} onChange={(e) => cambiar("nombre", e.target.value)} />
          </label>

          <label className={claseCampo("tipo")}>
            Tipo
            <select value={form.tipo} onChange={(e) => cambiar("tipo", e.target.value)}>
              <option value="">Elegir…</option>
              {TIPOS.map((t) => (
                <option key={t} value={t}>
                  {t}
                </option>
              ))}
            </select>
          </label>

          <label className={claseCampo("anada")}>
            Añada
            <input type="number" step="1" value={form.anada} onChange={(e) => cambiar("anada", e.target.value)} />
          </label>

          <label className={claseCampo("volumen")}>
            Volumen (ml)
            <input
              type="number"
              step="1"
              list="volumenes-habituales"
              value={form.volumen}
              onChange={(e) => cambiar("volumen", e.target.value)}
            />
            <datalist id="volumenes-habituales">
              {VOLUMENES.map((v) => (
                <option key={v} value={v} />
              ))}
            </datalist>
          </label>

          <label className={claseCampo("graduacion")}>
            Graduación (°)
            <input
              type="number"
              step="any"
              value={form.graduacion}
              onChange={(e) => cambiar("graduacion", e.target.value)}
            />
          </label>

          <label className={claseCampo("precio")}>
            Precio ($)
            <input type="number" step="any" value={form.precio} onChange={(e) => cambiar("precio", e.target.value)} />
          </label>

          <label className={`vino-form-ancho ${claseCampo("cuit_bodega")}`}>
            Bodega
            <select value={form.cuit_bodega} onChange={(e) => cambiar("cuit_bodega", e.target.value)}>
              <option value="">Elegir…</option>
              {(bodegas.data || []).map((b) => (
                <option key={b.cuit} value={b.cuit}>
                  {b.razon_social} (CUIT {b.cuit})
                </option>
              ))}
            </select>
          </label>
        </div>

        {/* Composición: filas dinámicas cepa + porcentaje */}
        <fieldset className={`vino-bloque ${claseCampo("composicion")}`}>
          <legend>Composición (corte)</legend>
          {filas.length === 0 && <p className="vacio">Sin cepas cargadas.</p>}
          {filas.map((f) => (
            <div className="vino-fila" key={f.key}>
              <label>
                Cepa
                <select value={f.id_cepa} onChange={(e) => cambiarFila(f.key, "id_cepa", e.target.value)}>
                  <option value="">Elegir…</option>
                  {(cepas.data || []).map((c) => (
                    <option key={c.id_cepa} value={c.id_cepa}>
                      {c.nombre} ({c.tipo})
                    </option>
                  ))}
                </select>
              </label>
              <label>
                Porcentaje (%)
                <input
                  type="number"
                  step="any"
                  value={f.porcentaje}
                  onChange={(e) => cambiarFila(f.key, "porcentaje", e.target.value)}
                />
              </label>
              <button type="button" className="secundario" onClick={() => quitarFila(f.key)}>
                Quitar
              </button>
            </div>
          ))}
          <div className="vino-fila-pie">
            <button type="button" className="secundario" onClick={agregarFila}>
              + Agregar cepa
            </button>
            <small className="vino-suma">Suma actual: {sumaActual} % (informativa; la regla la valida la base)</small>
          </div>
        </fieldset>

        {/* Maridajes: selección múltiple */}
        <fieldset className={`vino-bloque ${claseCampo("maridajes")}`}>
          <legend>Maridajes recomendados</legend>
          {maridajes.loading && <Loading />}
          <div className="vino-maridajes">
            {(maridajes.data || []).map((m) => (
              <label key={m.id} className="vino-check">
                <input
                  type="checkbox"
                  checked={maridajesSel.includes(m.id)}
                  onChange={() => alternarMaridaje(m.id)}
                />
                {m.nombre} <small>({Number(m.temperatura)} °C)</small>
              </label>
            ))}
          </div>
        </fieldset>

        <div className="vino-acciones">
          <button type="submit" disabled={enviando}>
            {enviando ? "Guardando…" : "Guardar"}
          </button>
          <Link className="boton-enlace secundario" to={esEdicion ? `/vinos/${cod}` : "/vinos"}>
            Cancelar
          </Link>
          {esEdicion && (
            <button type="button" className="peligro" disabled={enviando} onClick={eliminar}>
              Eliminar
            </button>
          )}
        </div>
      </form>
    </section>
  );
}

/* ------------------------------ Página ------------------------------ */
// /vinos/nuevo (alta) y /vinos/:cod/editar (edición, precargada con GET /vinos/{cod}).
export default function VinoForm() {
  const { cod } = useParams();
  const vino = useApi(() => (cod ? obtenerVino(cod) : Promise.resolve(null)), [cod]);

  if (cod) {
    if (vino.loading) return <Loading />;
    if (vino.error) {
      return (
        <section>
          <h2>Editar vino #{cod}</h2>
          <ErrorBanner error={vino.error} />
          <Link className="boton-enlace secundario" to="/vinos">
            ← Volver al catálogo
          </Link>
        </section>
      );
    }
  }

  const v = vino.data;
  const inicial = v
    ? {
        form: {
          nombre: v.nombre ?? "",
          tipo: v.tipo ?? "",
          anada: String(v.anada ?? ""),
          volumen: String(v.volumen ?? ""),
          graduacion: String(v.graduacion ?? ""),
          precio: String(v.precio ?? ""),
          cuit_bodega: v.cuit_bodega ?? "",
        },
        filas: (v.cepas || []).map((c, i) => ({ key: i, id_cepa: String(c.id_cepa), porcentaje: String(c.porcentaje) })),
        maridajes: (v.maridajes || []).map((m) => m.id),
      }
    : { form: FORM_VACIO, filas: [], maridajes: [] };

  return <Formulario key={cod || "nuevo"} cod={cod} inicial={inicial} />;
}
