import { Navigate, Route, Routes } from "react-router-dom";
import Layout from "./components/Layout";
import Catalogo from "./pages/Catalogo";
import VinoForm from "./pages/VinoForm";
import NuevaVenta from "./pages/NuevaVenta";
import Transferencias from "./pages/Transferencias";
import Tablero from "./pages/Tablero";

// Todas las rutas quedan definidas acá desde el principio: cada pantalla se implementa
// editando solo su propio archivo en src/pages/, sin tocar este router ni el Layout.
export default function App() {
  return (
    <Routes>
      <Route element={<Layout />}>
        <Route index element={<Navigate to="/vinos" replace />} />

        {/* Pantalla 1: Catálogo (el detalle de un vino se resuelve dentro de la misma página) */}
        <Route path="/vinos" element={<Catalogo />} />
        <Route path="/vinos/:cod" element={<Catalogo />} />

        {/* Pantalla 2: Alta y edición de vino */}
        <Route path="/vinos/nuevo" element={<VinoForm />} />
        <Route path="/vinos/:cod/editar" element={<VinoForm />} />

        {/* Pantalla 3: Nueva venta */}
        <Route path="/ventas/nueva" element={<NuevaVenta />} />

        {/* Pantalla 4: Transferencias (listado y detalle en la misma página) */}
        <Route path="/transferencias" element={<Transferencias />} />
        <Route path="/transferencias/:nro" element={<Transferencias />} />

        {/* Pantalla 5: Tablero */}
        <Route path="/tablero" element={<Tablero />} />

        <Route path="*" element={<p className="vacio">Página no encontrada.</p>} />
      </Route>
    </Routes>
  );
}
