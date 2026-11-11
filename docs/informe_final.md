# Informe final — Bodegas del Atuel

TPI Bases de Datos · Grupo 28 · UTN Facultad Regional San Rafael · Ciclo 2026
Integrantes: Matias Gonzalez, Dalma Monardi, Marcos Velez, Facundo Zinik

## 1. Introducción y alcance

Se desarrolló el sistema de gestión y distribución de la empresa vitivinícola ficticia «Bodegas del Atuel»: producción de uva (fincas, parcelas, lotes y análisis), bodegas y vinos (composición de cepas y maridajes), clientes de tres tipos, ventas con comprobantes, y circuito de stock (depósito central, ingresos y transferencias a las salas).

El peso del trabajo está en la capa de datos: el modelo, las reglas de integridad (RN-01 a RN-15), los índices y las consultas se resuelven en PostgreSQL 16. La API REST (FastAPI + `psycopg`, SQL escrito a mano, sin ORM) expone la base sin recalcular totales, descuentos ni stock.

El sistema completo (base, API y front) se levanta con `docker compose up -d --build`. Las instrucciones de instalación, carga y pruebas están en el `README.md` de la raíz del repositorio.

## 2. Modelo de datos

El detalle completo está en [`diccionario_datos.md`](diccionario_datos.md):

- **Diccionario de datos:** 30 tablas con tipo, nulabilidad, restricciones y descripción.
- **Normalización hasta 3FN:** dependencias funcionales por tabla (por ejemplo, `localidad → encargado regional`), sin dependencias parciales ni transitivas, y las excepciones de desnormalización controlada documentadas.
- **Decisiones de diseño:** jerarquía de clientes (supertipo `clientes` con subtipos `socio_club`, `distribuidores`, `exportadores`), entidades débiles (parcela), claves naturales y sustitutas, tipos de datos (`NUMERIC` para dinero, ENUM para estados), atributos derivados y acciones referenciales (`RESTRICT` en movimientos, `CASCADE` solo en renglones).
- **Esquema relacional y DDL:** el apéndice A del diccionario muestra la equivalencia entre el DER, el esquema relacional y `001_esquema.sql`.

## 3. Integridad y lógica en la base

Detalle en [`informe_tecnico_etapa2.md`](informe_tecnico_etapa2.md). Las reglas se protegen en tres capas:

1. **Declarativa:** dominios (`cuit_dom`), ENUM de estados, CHECK, UNIQUE, FK.
2. **Procedural:** funciones, triggers BEFORE/AFTER y un constraint trigger diferido para el corte = 100 % (RN-05).
3. **Transaccional:** procedimientos `sp_procesar_ingreso` y `sp_procesar_transferencia` con bloqueo `SELECT … FOR UPDATE`.

### 3.1 Trazabilidad regla → mecanismo → prueba

Las pruebas están en `db/tests/db_tests.sql` (casos que deben funcionar y casos que deben fallar, con el error esperado).

| Regla | Mecanismo | Prueba en `db_tests.sql` |
| --- | --- | --- |
| RN-01 Precio único y > 0 | Atributo `vino.precio` + CHECK | Precio negativo rechazado (`chk_vino_precio_positivo`) |
| RN-02 Sala en una localidad; un encargado por localidad | FK + PK de `encargado_regional` | Sala con código postal inexistente y segundo encargado rechazados |
| RN-03 Empleado en una sola sala | FK NOT NULL | Empleado con `id_sala = NULL` rechazado |
| RN-04 Una cepa por parcela; una cosecha por campaña | UNIQUE (finca, parcela, campaña) + FK | Segunda cosecha de la misma parcela y campaña rechazada |
| RN-05 Corte suma 100 | Constraint trigger diferido | Corte 70 + 30 confirmado; 80 % y vino sin cepas rechazados al confirmar |
| RN-06 Descuento por tipo de cliente | `fn_descuento_cliente` + CHECK + triggers de subtipo | Socio con 30 % rechazado; cliente en dos subtipos rechazado |
| RN-07 Permisos: vencimiento > emisión | CHECK entre columnas | Permiso con vencimiento anterior rechazado |
| RN-08 Total calculado, no manual | Triggers en `detalle_comprobante` + protección de la cabecera | `UPDATE comprobante SET total = …` rechazado |
| RN-09 Sin stock no hay venta | Trigger BEFORE (con `FOR UPDATE`) + CHECK (cantidad >= 0) | Venta por encima del stock rechazada |
| RN-10 Estados de ingreso | ENUM + trigger de estados + SP | Saltos y retrocesos rechazados; procesamiento suma al depósito |
| RN-11 Estados y fecha de transferencia | Triggers de estados y de fecha + SP | Fecha reemplazada por la actual; sin stock se revierte todo |
| RN-12 Renglones bloqueados fuera de confección | Trigger BEFORE en renglones | Modificar renglones de documentos procesados rechazado |
| RN-13 Auditoría de precio | Trigger AFTER UPDATE OF precio | Cambio 8500 → 9500 registrado en `auditoria_precio` |
| RN-14 No borrar con movimientos | FK `ON DELETE RESTRICT` | Borrado de un vino con ventas rechazado |
| RN-15 Positivos; graduación 5–20 | CHECK | Finca con superficie negativa rechazada |

### 3.2 ¿Dónde va cada regla?

| Tipo de regla | Herramienta | Ejemplo en este proyecto |
| --- | --- | --- |
| Valor válido de una sola fila | NOT NULL, CHECK, DOMAIN | `precio > 0`, CUIT de 11 dígitos |
| Existencia de un dato relacionado | FOREIGN KEY | Renglón → vino existente |
| Unicidad | UNIQUE / PRIMARY KEY | Una cosecha por parcela y campaña |
| Depende de otras filas, otras tablas o de la fecha actual | Trigger | Stock suficiente, estados, fecha de confección |
| Cálculo reutilizado | Función | Total con descuento |
| Operación de varios pasos todo o nada | Procedimiento en una transacción | Procesar una transferencia |
| Formato, experiencia de usuario, autorización | API y front | Mensajes claros, permisos |

Las reglas que dependen de la fecha actual van en triggers y no en CHECK, porque un CHECK con `CURRENT_DATE` cambia con el tiempo y se rompe al restaurar un backup.

### 3.3 Demostración de concurrencia

Dos sesiones `psql` intentan vender la última botella (`stock_sala.cantidad = 1`) bajo `READ COMMITTED`:

- **Sin bloqueo:** ambas leen `cantidad = 1`; las dos intentan descontar y el `CHECK (cantidad >= 0)` frena a una con un error no controlado (riesgo de pérdida de actualización).
- **Con `SELECT … FOR UPDATE`:** la segunda sesión espera hasta el `COMMIT` de la primera; al destrabarse ve `cantidad = 0` y la venta se rechaza de forma consistente.

Capturas y detalle en `informe_tecnico_etapa2.md`, sección 4.

## 4. Carga masiva

Detalle en [`../db/seed/README.md`](../db/seed/README.md).

- **Catálogos reales** desde CSV: cepas, maridajes, departamentos y tipos de vino.
- **Orden de carga**, según las dependencias de claves foráneas:
  1. Catálogos y tablas sin dependencias: `localidades`, `cepa`, `maridaje`, `bodega`, `empresa_transporte`.
  2. Tablas que dependen de ellas: `encargado_regional`, `transportista_de_localidad`, `sala_de_ventas`, `empleado`, `finca`.
  3. Producción de uva: `parcelas`, `lote_uva`, `analisis_calidad`.
  4. Vinos: `vino`, `composicion`, `vino_maridaje`, `auditoria_precio`.
  5. Clientes: `clientes`, `socio_club`, `distribuidores`, `exportadores`, `permisos`.
  6. Stock y movimientos: `stock_central`, `ingresos` y `detalle_ingreso`, `transferencias` y `detalle_transferencia`, `stock_sala`.
  7. Ventas: `comprobante` y `detalle_comprobante`, al final porque dependen de clientes, salas y vinos.
- **Reproducibilidad:** `random.Random(seed)` y `Faker("es_AR")` con semilla fija; dos corridas con la misma semilla y `--fecha-ref` dan el mismo hash global (`47a387a0eb2a…`).
- **Triggers durante la carga:** se deshabilitan los de usuario en las tablas históricas (`DISABLE TRIGGER USER`) y se rehabilitan en un `finally`. Motivo: el histórico incluye documentos ya procesados cuyos renglones rechazaría RN-12, y los triggers de totales, stock y auditoría alterarían la generación determinista. Las validaciones equivalentes se hacen en Python y se verifican con consultas de control. **Riesgo:** si la lógica Python tuviera un error, nada lo detectaría en el momento, y `ENABLE TRIGGER` no revalida lo ya insertado.
- **Volumen y filas por tabla** (valores aproximados):

| Grupo de tablas | Filas |
| --- | ---: |
| Localidades, salas, empleados y transporte | 250 |
| Fincas, parcelas y cosechas | 4.200 |
| Análisis de calidad | 7.000 |
| Vinos, composición y maridajes | 2.500 |
| Clientes, subtipos y permisos | 22.500 |
| Comprobantes | 150.000 |
| Renglones de comprobante | 525.400 |
| Ingresos y transferencias | 4.000 |
| Renglones de ingreso y transferencia | 14.500 |
| Stock central y por sala | 5.000 |

  Cumple los mínimos del enunciado: todas las tablas tienen filas, varias superan las 10.000 y dos superan las 100.000. Los conteos principales de la corrida documentada son 150.000 comprobantes, 500 vinos, 3.000 permisos, 1.995 transferencias y 1.700 ingresos.
- **Consultas de control** (`db/seed/consultas_control.sql`): filas huérfanas en las claves foráneas principales, stock negativo en sala y depósito, comprobantes con subtotal, descuento o total inconsistente, vinos cuya composición no suma 100, permisos con vencimiento anterior a la emisión, fechas futuras y estados inválidos. Todas deben devolver 0 filas problemáticas.
- **Fila por fila, por lotes y COPY** (20.000 renglones de `detalle_comprobante`, con ROLLBACK). En la corrida del reporte de la Etapa 3 los tiempos fueron 31,82 s, 11,93 s y 5,02 s. En la Etapa 4 se repitió el benchmark con y sin índices (Tabla 7 del informe de rendimiento) y dio 14,11 s, 2,41 s y 1,92 s sin índices, y 14,27 s, 2,40 s y 1,91 s con índices. Las cifras absolutas cambian entre corridas, pero el orden se mantiene: COPY es entre 7 y 7,4 veces más rápido que insertar fila por fila, y los índices casi no afectan el costo de estos métodos.

## 5. Índices y rendimiento

Detalle completo, con planes `EXPLAIN (ANALYZE, BUFFERS)`, en [`informe_rendimiento.md`](informe_rendimiento.md).

| Consulta | Antes (ms) | Después (ms) | Recorrido | Índice | Mejora |
| --- | --- | --- | --- | --- | --- |
| Q2 (S3) clientes por tipo en una sala, última semana | 25,8 | 1,8 | Parallel Seq Scan → Bitmap Heap Scan | `idx_comprobante_sala_fecha` | 14,3× |
| Q3 (S8) ventas por sala, último trimestre | 25,5 | 4,8 | Parallel Seq Scan → Index Only Scan | `idx_comprobante_fecha_cubriente` | 5,3× |
| Q5 (S12 a) clientes que compraron todos los vinos de una bodega | 170.491,4 | 1.010,7 | Seq Scan por cliente → Bitmap Index Scan | `idx_comprobante_cliente` | 168,7× |
| Q1 (S1) top 10 vinos | 128,7 | 131,3 | Parallel Seq Scan (el planificador ignora el índice) | — | 1,0× |
| Q4 (S12 parte anti-join) | 351,6 | 410,0 | Seq Scan (el planificador ignora el índice) | — | 0,9× |

Puntos a destacar en la defensa:

- Orden de columnas del índice compuesto: igualdad primero (`id_sala`), rango después (`fecha`); invertirlo sube Q2 de 1,8 a ~10,5 ms.
- Índice descartado: BRIN sobre `fecha` (correlación física ≈ 0,003; el planificador prefiere el Seq Scan).
- Costo de escritura: la carga completa pasa de 1 m 24,0 s a 1 m 25,7 s con los índices (+2,05 %).
- Caso en que el planificador no usa el índice: baja selectividad (filtro de ~80 % de la tabla).

## 6. Consultas SQL

Todas las consignas de la sección 8 están en [`../consultas/`](../consultas/) (`insert.sql`, `update.sql`, `delete.sql`, `select.sql`), comentadas y probadas dentro de `BEGIN … ROLLBACK`. Los planes de ejecución (`EXPLAIN (ANALYZE, BUFFERS)`) de las consultas de la Etapa 4 y de S9 a S12 están en [`informe_etapa5.md`](informe_etapa5.md).

Cuatro consultas que muestran las herramientas pedidas:

- **S10 — rendimiento por parcela (CTE y subconsulta correlacionada).** Una CTE calcula los kg por hectárea de cada lote y parcela. Para encontrar las parcelas que rinden menos que el promedio de su finca, la subconsulta correlacionada va contra las tablas base (`lote_uva` y `parcelas`) y no contra la CTE, porque una CTE no tiene índices y habría que recorrerla completa en cada ejecución.
- **S11 — ranking y acumulado (funciones de ventana).** `RANK() OVER (PARTITION BY id_sala ORDER BY SUM(cantidad) DESC)` numera los vinos dentro de cada sala y los empates comparten puesto. Para las ventas mensuales, `SUM(monto) OVER (PARTITION BY id_sala ORDER BY mes)` da el acumulado, que arranca de nuevo en cada sala.
- **S12 — división y anti-join (`NOT EXISTS`).** Un cliente compró todos los vinos de una bodega si no existe ningún vino de esa bodega que no haya comprado (doble `NOT EXISTS`). Los clientes que nunca compraron vino tinto se obtienen con un anti-join, exigiendo antes que tengan al menos una compra para no contar a quienes nunca compraron.
- **I3 — comprobante con tres renglones en una transacción.** La cabecera se inserta con importes en 0 y los renglones se cargan solo con vino y cantidad: los triggers validan el stock (RN-09), toman el precio, calculan el descuento (RN-06), descuentan el stock y recalculan la cabecera con `fn_total_comprobante` (RN-08). La consulta final compara el total guardado con el que devuelve la función, y todo termina en `ROLLBACK`.

## 7. API y front

### 7.1 Arquitectura

- FastAPI con una capa `repositories/` (una función por consulta, todas parametrizadas) y `routers/` por recurso.
- Pool de conexiones y transacciones explícitas en operaciones de varios pasos (por ejemplo, `POST /comprobantes`: cabecera y renglones en una sola transacción).
- Conexión con el rol `app_rw` (sin DDL, nunca el propietario); credenciales por variables de entorno y `.env.example` sin secretos.
- Endpoints: vinos (con filtros y paginación), clientes, comprobantes, transferencias, ingresos, reportes, catálogos y `/salud`. Lista completa en el `README.md` y en `/docs` (Swagger).

### 7.2 Traducción de errores

El manejo central (`api/errors.py`) traduce el SQLSTATE: 23505 → 409; 23503 → 422 o 409; 23514 y 23502 → 422; P0001 → 409 con el mensaje exacto de la regla; 22P02 → 400; 40001 y 40P01 → 503 con `Retry-After`.

### 7.3 Pruebas automáticas

`api/tests/test_api.py` tiene más de 20 pruebas, entre ellas las que provocan violaciones de reglas de la base: precio negativo (422), corte distinto de 100 (409), vino duplicado (409), venta sin stock (409), procesar una transferencia sin terminar (409) y un flujo completo ingreso → transferencia → venta.

### 7.4 Inyección SQL fallida

Contra `GET /vinos?tipo=…` se enviaron `' OR '1'='1` y `'; DROP TABLE vino; --`: ambos devuelven `200` con `items: []`, porque el valor viaja como parámetro y se compara como texto literal. La request de control devuelve `total: 500`, lo que confirma que la tabla sigue intacta. Evidencia en [`inyeccion-sql/`](inyeccion-sql/) y en `api/README.md`.

### 7.5 Front

Aplicación React 18 con Vite, React Router y Chart.js, servida con nginx desde su propio contenedor (puerto 8080). Los bocetos de las pantallas están en [`bocetos/pantallas.md`](bocetos/pantallas.md).

- **Una sola salida HTTP:** todas las llamadas pasan por `src/api/client.js`; los componentes nunca usan `fetch` directamente. La URL de la API sale de `config.js`, que el contenedor genera al arrancar a partir de la variable `API_URL`.
- **Errores de las reglas:** `ApiError` conserva el mensaje exacto que devuelve la API y `ErrorBanner` lo muestra sin reemplazarlo por un texto genérico. Por ejemplo, una venta sin stock muestra el mensaje de RN-09 y el carrito se conserva.
- **Sin lógica de negocio:** el carrito guarda solo `{cod_vino, cantidad}`; precios, descuentos y totales se muestran tal como los devuelve `POST /comprobantes`. En el formulario de vino, la suma de porcentajes es informativa y el envío no se bloquea: la regla la valida la base al confirmar.
- **Pantallas:** catálogo con filtros y paginación, alta y edición de vino con composición, nueva venta, transferencias (botones habilitados según el estado) y tablero con ranking, gráfico de ventas por sala y vinos sin stock.

## 8. Despliegue y operación

Los tres servicios (`db`, `api` y `front`) se definen en `docker-compose.yml`. La base aplica las migraciones 001 a 008 al crearse el volumen y su healthcheck garantiza que la API arranque recién cuando las migraciones terminaron. La API se conecta con `app_rw`, nunca con el propietario, y las credenciales se pasan por variables de entorno.

**Backup y restauración:** el volcado se genera con `pg_dump` sin dueños ni permisos (`dump_completo.sql.gz`; no se sube al repositorio porque supera el tamaño permitido, pero se genera con los comandos del README) y se restaura en una base nueva con `psql`. Como el volcado no incluye roles ni privilegios, después de restaurar se vuelve a aplicar `007_roles.sql`. La restauración se verifica comparando los conteos de `comprobante`, `detalle_comprobante`, `clientes` y `vino` entre la base original y la nueva. Los comandos completos están en `db/seed/README.md` y en el `README.md` principal.

## 9. Conclusiones

- **Dificultades:** cargar el histórico sin chocar con los triggers de bloqueo y de totales (resuelto deshabilitándolos en la carga y validando en Python); que el planificador ignorara índices que parecían evidentes (Q1 y Q4).
- **Aprendizajes:** mantener las reglas dentro de la base garantiza que valgan aunque alguien acceda directamente; los índices se diseñan a partir de los planes medidos y no por intuición; un `FOREIGN KEY` no crea su índice, y esa omisión llevó a Q5 de 170 s a 1 s al agregarlo.
