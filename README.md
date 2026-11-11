# Bodegas del Atuel — TPI Bases de Datos (Grupo 28)

Sistema de gestión y distribución de una empresa vitivinícola (producción de uva, vinos, salas de venta, depósito central, ingresos, transferencias y ventas).
Trabajo Práctico Integrador · Base de Datos · Ingeniería en Sistemas · UTN Facultad Regional San Rafael · Ciclo 2026.

**Integrantes:** Matias Gonzalez, Dalma Monardi, Marcos Velez, Facundo Zinik.

La parte central del trabajo es la **capa de datos**: las reglas de negocio (RN-01 a RN-15) viven dentro de PostgreSQL (constraints, funciones, procedimientos y triggers). La API y el front solo exponen esa base; **no recalculan totales, descuentos ni stock**.

## Tecnologías

| Componente | Elección |
| --- | --- |
| Base de datos | PostgreSQL 16 (imagen `postgres:16-alpine`) |
| API REST | Python + FastAPI, driver nativo `psycopg` 3, SQL escrito a mano (sin ORM) |
| Carga de datos | Python + `psycopg` + Faker (`es_AR`), semilla fija |
| Contenedores | Docker y Docker Compose |
| Front | React 18 + Vite, React Router y Chart.js, servido con nginx |

## Estructura del repositorio

```text
.
├── README.md
├── docker-compose.yml          # base + API + front
├── api/                        # API REST (routers, repositories, errors, tests)
├── front/                      # front web (React + Vite)
├── consultas/                  # insert.sql, update.sql, delete.sql, select.sql (sección 8)
├── db/
│   ├── migrations/             # 001_esquema.sql … 008_indices.sql
│   ├── seed/                   # catálogos CSV, generador de datos, consultas de control
│   └── tests/db_tests.sql      # pruebas de las reglas RN-01 a RN-15
└── docs/                       # diccionario, informes, evidencias
```

## Requisitos

- Docker y Docker Compose.
- Python 3.11 o superior (solo para la carga de datos y las pruebas de la API).
- `psql` es opcional: se puede usar `docker exec` contra el contenedor.

## Levantar todo en local

```bash
# 1) Base (migraciones 001-008 automáticas) + API en :8000 + front en :8080
docker compose up -d --build

# 2) Primera vez: cargar los datos (como postgres, puerto 5433)
python -m venv .venv && source .venv/bin/activate
pip install -r db/seed/requirements.txt
python db/seed/cargar_catalogos.py
python db/seed/generar_datos.py --seed 42 --fecha-ref 2026-11-08
```

- Front: <http://localhost:8080>
- Swagger / OpenAPI: <http://localhost:8000/docs>
- Salud de la API: <http://localhost:8000/salud>
- Base desde el host: `localhost:5433`, base `bodegas_del_atuel`.

> Las migraciones solo se ejecutan cuando el volumen de la base está vacío. Para reaplicarlas desde cero:
> `docker compose down -v && docker compose up -d --build` (**borra los datos locales**).

> La contraseña de `app_rw` está fijada en `db/migrations/007_roles.sql` (`cambiar_por_un_secreto`). Si definís otra en `APP_RW_PASSWORD`, aplicala también en la base:
> `docker exec postgres-bodega psql -U postgres -d bodegas_del_atuel -c "ALTER ROLE app_rw PASSWORD '<nueva>'"`.
> Las contraseñas reales no se suben al repositorio.

## Migraciones

Se aplican en orden alfabético sobre una base vacía (`db/migrations/`):

| Archivo | Contenido |
| --- | --- |
| `001_esquema.sql` | Tipos ENUM y dominios, tablas, claves primarias y foráneas |
| `002_constraints.sql` | UNIQUE, CHECK, DEFAULT y acciones referenciales |
| `003_funciones.sql` | Funciones de cálculo (descuento, total, stock, antigüedad) |
| `004_procedimientos.sql` | `sp_procesar_ingreso`, `sp_procesar_transferencia` |
| `005_triggers.sql` | Validación de stock, totales, estados, bloqueo de renglones, auditoría de precio, corte = 100 % |
| `006_vistas.sql` | Vistas de stock, ventas y documentos pendientes |
| `007_roles.sql` | Roles y privilegios mínimos |
| `008_indices.sql` | Índices de la Etapa 4 |

## Roles de base de datos

| Rol | Uso | Permisos |
| --- | --- | --- |
| `postgres` (propietario) | Migraciones y carga masiva | Todos |
| `app_rw` | **La API** (nunca el propietario) | SELECT/INSERT/UPDATE/DELETE y EXECUTE; sin DDL |
| `reportes_ro` | Reportes | Solo SELECT y EXECUTE |

`PUBLIC` no tiene privilegios sobre el esquema `public`.

## Carga masiva de datos

Detalle completo en [`db/seed/README.md`](db/seed/README.md). Resumen:

- Catálogos reales desde CSV (cepas, maridajes, departamentos, tipos de vino).
- Generador reproducible: mismas semilla y `--fecha-ref` producen los mismos datos (hash SHA-256 por tabla y global).
- Modos de inserción: `copy` (por defecto), `lotes` y `fila`; `--benchmark` compara los tres sin dejar cambios.
- Durante la carga se deshabilitan los triggers de usuario de las tablas históricas y se rehabilitan al final; las validaciones equivalentes se hacen en Python y se verifican con `db/seed/consultas_control.sql`.
- Volumen: 150.000 comprobantes y ~525.400 renglones de comprobante.

Consultas de control:

```bash
docker exec -i postgres-bodega psql -U postgres -d bodegas_del_atuel < db/seed/consultas_control.sql
```

## Pruebas

**Reglas de negocio en la base (RN-01 a RN-15)**, sobre una base vacía recién migrada:

```bash
docker exec postgres-bodega createdb -U postgres bodegas_test
for f in db/migrations/*.sql; do
  docker exec -i postgres-bodega psql -U postgres -d bodegas_test -v ON_ERROR_STOP=1 < "$f"
done
docker exec -i postgres-bodega psql -U postgres -d bodegas_test -v ON_ERROR_STOP=1 < db/tests/db_tests.sql
```

Cada rechazo esperado se informa como `OK`; si una operación prohibida fuera aceptada, el script se detiene con `FALLO`.

**API** (con la base levantada y cargada):

```bash
cd api
python -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
cp .env.example .env        # DB_HOST=localhost, DB_PORT=5433
pytest -v
```

## API REST

Documentación interactiva en `/docs`. Endpoints principales:

| Recurso | Rutas |
| --- | --- |
| Vinos | `GET /vinos` (filtros `tipo`, `cepa`, `bodega`, `anada`; paginación `page`/`limit`), `GET /vinos/{cod}`, `GET /vinos/anadas`, `GET /vinos/{cod}/auditoria-precio`, `POST /vinos`, `PUT /vinos/{cod}`, `DELETE /vinos/{cod}` |
| Clientes | `GET /clientes`, `GET /clientes/{id}`, `POST`, `PUT`, `DELETE` (socio, distribuidor y exportador) |
| Comprobantes | `POST /comprobantes` (cabecera + renglones en una transacción), `GET /comprobantes/{nro}` |
| Transferencias | `GET/POST /transferencias`, `GET /transferencias/{nro}`, `POST …/{nro}/renglones`, `POST …/{nro}/terminar`, `POST …/{nro}/procesar` |
| Ingresos | `GET/POST /ingresos`, `GET /ingresos/{cod}`, `POST …/{cod}/renglones`, `POST …/{cod}/terminar`, `POST …/{cod}/procesar` |
| Reportes | `GET /reportes/top-vinos`, `/ventas-por-sala`, `/vinos-sin-stock?sala=`, `/transportista-mayor-actividad`, `/ficha-vino/{cod}`, `/trazabilidad/{cod}` (ingresos, transferencias y ventas de un vino) |
| Catálogos | `GET /cepas`, `/bodegas`, `/salas`, `/maridajes` |
| Salud | `GET /salud` |

### Traducción de errores (SQLSTATE → HTTP)

| Situación en PostgreSQL | SQLSTATE | HTTP |
| --- | --- | --- |
| UNIQUE violado | 23505 | 409 |
| FOREIGN KEY: referencia inexistente / dependientes | 23503 | 422 / 409 |
| CHECK o NOT NULL violado | 23514 / 23502 | 422 |
| Regla rechazada por trigger o procedimiento (`RAISE EXCEPTION`) | P0001 | 409, con el mensaje de la regla |
| Texto con formato inválido | 22P02 | 400 |
| Serialización o deadlock | 40001 / 40P01 | 503 con `Retry-After` |
| Sin conexión a la base | 08xxx | 503 |

Una venta sin stock devuelve **409** con el mensaje de la regla RN-09 y no deja datos a medias (cabecera y renglones van en una sola transacción).

## Front

Aplicación React que consume únicamente la API. La URL de la API se configura con la variable `API_URL` del servicio `front` en `docker-compose.yml` (por defecto `http://localhost:8000`) y se escribe en `config.js` al arrancar el contenedor, sin recompilar.

| Pantalla | Qué permite |
| --- | --- |
| Catálogo de vinos | Listado paginado con filtros por tipo, cepa, bodega y añada; detalle con composición y maridajes |
| Alta y edición de vino | Formulario con composición de cepas; muestra el error de la base si los porcentajes no suman 100 |
| Nueva venta | Elegir cliente y sala, armar el carrito y ver el comprobante con los importes que devuelve la API; muestra el error de stock insuficiente |
| Transferencias | Crear, cargar renglones, terminar y procesar, con botones según el estado |
| Tablero | Top 10 de vinos, ventas por sala del último trimestre (gráfico) y vinos sin stock en una sala |

El front no calcula totales, descuentos ni stock: muestra lo que responde la API, y los mensajes de error de las reglas se muestran tal cual llegan. Los bocetos están en [`docs/bocetos/pantallas.md`](docs/bocetos/pantallas.md).

## Consultas SQL (sección 8)

Resueltas y comentadas en [`consultas/`](consultas/): `insert.sql`, `update.sql`, `delete.sql` y `select.sql`. Las sentencias que modifican datos se prueban dentro de `BEGIN … ROLLBACK`.

## Documentación

| Documento | Contenido |
| --- | --- |
| [`docs/informe_final.md`](docs/informe_final.md) | Informe final (estructura de la sección 10.2) |
| [`docs/diccionario_datos.md`](docs/diccionario_datos.md) | Diccionario de datos, dependencias funcionales, 3FN y decisiones de diseño |
| [`docs/informe_tecnico_etapa2.md`](docs/informe_tecnico_etapa2.md) | Integridad, trazabilidad RN → mecanismo → prueba y demostración de concurrencia |
| [`docs/informe_rendimiento.md`](docs/informe_rendimiento.md) | Índices, planes EXPLAIN antes y después, costo de escritura |
| [`docs/guion_demo.md`](docs/guion_demo.md) | Guion de la demo en vivo |
| [`docs/preguntas_defensa.md`](docs/preguntas_defensa.md) | Preguntas típicas de defensa con sus respuestas |
| [`docs/bocetos/pantallas.md`](docs/bocetos/pantallas.md) | Bocetos de las cinco pantallas del front |
| [`docs/inyeccion-sql/`](docs/inyeccion-sql/) | Evidencia de la prueba de inyección SQL fallida |
| [`db/seed/README.md`](db/seed/README.md) | Carga masiva, reproducibilidad, dump y restauración |

## Backup y restauración

```bash
# Backup
docker exec postgres-bodega pg_dump -U postgres -d bodegas_del_atuel --no-owner --no-acl | gzip > dump_completo.sql.gz

# Restauración en una base nueva (y reaplicar roles)
docker exec postgres-bodega createdb -U postgres bodegas_nueva
gunzip -c dump_completo.sql.gz | docker exec -i postgres-bodega psql -U postgres -d bodegas_nueva -v ON_ERROR_STOP=1
docker exec -i postgres-bodega psql -U postgres -d bodegas_nueva -v ON_ERROR_STOP=1 < db/migrations/007_roles.sql
```
