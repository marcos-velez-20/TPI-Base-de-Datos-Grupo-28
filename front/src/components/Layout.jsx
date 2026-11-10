import { useEffect, useState } from "react";
import { NavLink, Outlet } from "react-router-dom";
import { getApiUrl } from "../api/client";
import { salud } from "../api/salud";

const ENLACES = [
  { to: "/vinos", texto: "Catálogo", end: true },
  { to: "/vinos/nuevo", texto: "Nuevo vino" },
  { to: "/ventas/nueva", texto: "Nueva venta" },
  { to: "/transferencias", texto: "Transferencias" },
  { to: "/tablero", texto: "Tablero" },
];

function EstadoApi() {
  const [estado, setEstado] = useState("verificando");

  useEffect(() => {
    let activo = true;
    const consultar = () =>
      salud()
        .then(() => activo && setEstado("ok"))
        .catch(() => activo && setEstado("error"));
    consultar();
    const timer = setInterval(consultar, 30000);
    return () => {
      activo = false;
      clearInterval(timer);
    };
  }, []);

  const texto = { verificando: "verificando…", ok: "OK", error: "sin conexión" }[estado];
  return (
    <span className={`estado-api estado-${estado}`}>
      API: {texto} <small>({getApiUrl()})</small>
    </span>
  );
}

export default function Layout() {
  return (
    <div className="app">
      <header className="cabecera">
        <h1>🍷 Bodegas del Atuel</h1>
        <nav>
          {ENLACES.map((e) => (
            <NavLink key={e.to} to={e.to} end={e.end}>
              {e.texto}
            </NavLink>
          ))}
        </nav>
      </header>
      <main className="contenido">
        <Outlet />
      </main>
      <footer className="pie">
        <EstadoApi />
      </footer>
    </div>
  );
}
