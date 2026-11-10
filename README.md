# TPI-Base-de-Datos-Grupo-28
## Front

Aplicación React (Vite + React Router) en `front/`. Consume únicamente la API REST de `api/`: no calcula importes, descuentos ni stock, y muestra tal cual los mensajes de error de las reglas de negocio que devuelve la base.

### Cómo levantarlo

Todo junto (base + API + front):

```bash
docker compose up --build
```

El front queda en <http://localhost:8080> y la API en <http://localhost:8000>.

Solo el front, en modo desarrollo (con la API ya levantada):

```bash
cd front
npm install
npm run dev      # http://localhost:5173
```

### Variables

| Variable | Dónde | Descripción |
|---|---|---|
| `API_URL` | servicio `front` de `docker-compose.yml` | URL de la API **vista desde el navegador**. Se aplica al arrancar el contenedor (genera `config.js`), sin recompilar. Por defecto `http://localhost:8000`. |
| `VITE_API_URL` | build/desarrollo | Alternativa para `npm run dev`. |
| `CORS_ORIGINS` | API | Orígenes permitidos para el front (por defecto `http://localhost:5173,http://localhost:8080`). |

### Pantallas

| Ruta | Pantalla |
|---|---|
| `/vinos` y `/vinos/:cod` | Catálogo: listado con filtros por tipo, cepa, bodega y añada, y detalle con composición y maridajes. |
| `/vinos/nuevo` y `/vinos/:cod/editar` | Alta y edición de vino con composición de cepas dinámica. |
| `/ventas/nueva` | Nueva venta: cliente, sala y renglones; muestra el comprobante que calcula la base. |
| `/transferencias` y `/transferencias/:nro` | Transferencias: listado, alta, renglones y cambio de estado. |
| `/tablero` | Top 10 de vinos, ventas por sala del último trimestre y vinos sin stock por sala. |

Los bocetos están en `docs/bocetos/pantallas.md`.

### Capturas sugeridas para el informe

1. Venta exitosa con el comprobante devuelto por la API.
2. Venta sin stock, con el mensaje de la regla RN-09.
3. Alta de vino con porcentajes que no suman 100 (RN-05).
4. Ciclo de una transferencia, con los botones habilitados según el estado.
5. Tablero con los tres bloques.
