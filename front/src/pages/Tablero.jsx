import { useState } from "react";
import { Bar } from "react-chartjs-2";
import { BarElement, CategoryScale, Chart as ChartJS, LinearScale, Title, Tooltip } from "chart.js";
import { listarSalas } from "../api/catalogos";
import { topVinos, ventasPorSala, vinosSinStock } from "../api/reportes";
import ErrorBanner from "../components/ErrorBanner";
import Loading from "../components/Loading";
import Tabla from "../components/Tabla";
import { useApi } from "../hooks/useApi";
import "./Tablero.css";

ChartJS.register(CategoryScale, LinearScale, BarElement, Title, Tooltip);

// Solo formateo para mostrar. Los valores (y el "último trimestre") los calcula la base de datos.
const formatoNumero = (v) => Number(v).toLocaleString("es-AR");
const formatoMonto = (v) =>
  `$ ${Number(v).toLocaleString("es-AR", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

/* 1) Top 10 de vinos más vendidos: GET /reportes/top-vinos */
function TopVinos() {
  const { data, error, loading } = useApi(() => topVinos(10), []);
  // La posición es solo el número de orden en que la API devolvió las filas (ya vienen ordenadas).
  const filas = (data || []).map((v, i) => ({ ...v, posicion: i + 1 }));
  return (
    <section className="tb-bloque">
      <h3>Top 10 vinos más vendidos</h3>
      <ErrorBanner error={error} />
      {loading && <Loading />}
      {data && (
        <Tabla
          vacio="Todavía no hay ventas registradas."
          columnas={[
            { clave: "posicion", titulo: "#" },
            { clave: "nombre", titulo: "Vino", render: (v) => `${v.nombre} ${v.anada} · ${v.volumen} ml` },
            { clave: "botellas", titulo: "Botellas vendidas", render: (v) => formatoNumero(v.botellas) },
          ]}
          filas={filas}
        />
      )}
    </section>
  );
}

/* 2) Ventas por sala en el último trimestre: GET /reportes/ventas-por-sala */
function VentasPorSala() {
  const { data, error, loading } = useApi(ventasPorSala, []);
  const grafico = data && {
    labels: data.map((f) => `Sala ${f.id_sala} · ${f.localidad}`),
    datasets: [{ label: "Monto vendido", data: data.map((f) => Number(f.monto)), backgroundColor: "#7b1e3a" }],
  };
  const opciones = {
    responsive: true,
    plugins: {
      legend: { display: false },
      tooltip: { callbacks: { label: (ctx) => formatoMonto(ctx.parsed.y) } },
    },
    scales: { y: { beginAtZero: true } },
  };
  return (
    <section className="tb-bloque">
      <h3>Ventas por sala (último trimestre)</h3>
      <ErrorBanner error={error} />
      {loading && <Loading />}
      {data && data.length === 0 && <p className="vacio">No hay ventas en el último trimestre.</p>}
      {data && data.length > 0 && <Bar data={grafico} options={opciones} />}
    </section>
  );
}

/* 3) Vinos sin stock en una sala: GET /reportes/vinos-sin-stock?sala=<id> */
function VinosSinStock() {
  const [sala, setSala] = useState("");
  const salas = useApi(listarSalas, []);
  const sinStock = useApi(() => (sala ? vinosSinStock(sala) : Promise.resolve(null)), [sala]);
  return (
    <section className="tb-bloque tb-ancho">
      <h3>Vinos sin stock en la sala (con stock en el depósito central)</h3>
      <ErrorBanner error={salas.error} />
      <label className="tb-selector">
        Sala
        <select value={sala} onChange={(e) => setSala(e.target.value)}>
          <option value="">Elegir sala…</option>
          {(salas.data || []).map((s) => (
            <option key={s.id_sala} value={s.id_sala}>
              Sala {s.id_sala} · {s.calle} {s.numero}
            </option>
          ))}
        </select>
      </label>
      <ErrorBanner error={sinStock.error} />
      {sala && sinStock.loading && <Loading />}
      {sala && sinStock.data && (
        <Tabla
          vacio="Todos los vinos con stock en el depósito tienen stock en esta sala."
          columnas={[
            { clave: "id", titulo: "Cód. vino" },
            { clave: "nombre", titulo: "Vino" },
            { clave: "stock_deposito", titulo: "Stock en depósito", render: (v) => formatoNumero(v.stock_deposito) },
          ]}
          filas={sinStock.data}
        />
      )}
      {!sala && <p className="vacio">Elegí una sala para ver el listado.</p>}
    </section>
  );
}

export default function Tablero() {
  // Cada bloque tiene su propio estado de carga y de error: si uno falla, los otros siguen funcionando.
  return (
    <section>
      <h2>Tablero</h2>
      <div className="tb-grid">
        <TopVinos />
        <VentasPorSala />
        <VinosSinStock />
      </div>
    </section>
  );
}
