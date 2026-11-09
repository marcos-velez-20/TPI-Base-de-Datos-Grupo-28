# Carga de datos de Bodegas del Atuel

Esta carpeta contiene la carga de catálogos y el generador de datos masivos
reproducibles para el esquema de `db/migrations`.

## Requisitos

- PostgreSQL 16 disponible en `localhost:5433` (ver `docker-compose.yml`).
- Python 3.11 o superior.
- Dependencias de `db/seed/requirements.txt`:
  - `psycopg[binary]>=3.1,<4`
  - `Faker>=30,<40`

Con `uv` (recomendado):

```bash
uv venv .venv
uv pip install --python .venv/bin/python -r db/seed/requirements.txt
source .venv/bin/activate
```

Con `venv`/`pip`:

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r db/seed/requirements.txt
```

## Orden de ejecución

1. Crear la base y aplicar las migraciones (`001_esquema.sql` a
   `007_roles.sql`, en orden).
2. Cargar los catálogos obligatorios.
3. Ejecutar el generador.

```bash
docker compose up -d postgres

for archivo in db/migrations/*.sql; do
  docker exec -i postgres-bodega psql -U postgres -d bodegas_del_atuel \
    < "$archivo"
done

python db/seed/cargar_catalogos.py
python db/seed/generar_datos.py --seed 42 --fecha-ref 2026-11-08
```

La base de ejemplo se llama `bodegas_del_atuel`, usa el usuario `postgres` y
escucha en el puerto `5433`.

## Variables de entorno

| Variable | Alternativa | Default |
| --- | --- | --- |
| `DB_HOST` | `PGHOST` | `localhost` |
| `DB_PORT` | `PGPORT` | `5433` |
| `DB_USER` | `PGUSER` | `postgres` |
| `DB_PASSWORD` | `PGPASSWORD` | `postgres` |
| `DB_NAME` | `PGDATABASE` | `bodegas_del_atuel` |
| `SEED_LOCK_TIMEOUT` | — | `30` (segundos) |

`SEED_LOCK_TIMEOUT` define cuánto espera el `TRUNCATE` de `--reset` para tomar
sus locks. Si otra corrida o una sesión con transacción abierta bloquea las
tablas, el script falla con un error claro en lugar de quedar colgado.

## Opciones del generador

```text
--seed SEED           semilla aleatoria (default: 42)
--fecha-ref FECHA     fecha de referencia ISO, por ejemplo 2026-11-08
                      (default: hoy)
--reset               vacía las tablas generadas antes de insertar
--modo-insercion MÉTODO
                      copy, lotes o fila (default: copy)
--benchmark           mide fila por fila, por lotes y COPY con 20.000
                      renglones y ROLLBACK, sin dejar cambios
```

Ejemplos:

```bash
# Carga desde cero con una fecha de referencia fija
python db/seed/generar_datos.py --reset --seed 42 --fecha-ref 2026-11-08

# Regenerar usando la fecha actual como referencia
python db/seed/generar_datos.py --reset --seed 7

# Aborta si ya hay datos, sin borrar nada
python db/seed/generar_datos.py --seed 42 --fecha-ref 2026-11-08

# Carga por lotes en lugar de COPY
python db/seed/generar_datos.py --reset --modo-insercion lotes

# Medir los tres métodos de inserción sin dejar cambios
python db/seed/generar_datos.py --benchmark
```

Sin `--reset`, el script aborta si alguna tabla generada ya tiene filas. Con
`--reset` se ejecuta `TRUNCATE ... RESTART IDENTITY CASCADE` únicamente sobre
las tablas generadas. Los catálogos `cepa` y `maridaje` se conservan.

Si los catálogos están vacíos, el generador los carga automáticamente desde
`cepas.csv` y `maridajes.csv`.

## Métodos de inserción

`--modo-insercion` controla cómo se insertan las tablas grandes (10.000 filas o
más):

- `copy` (default): usa `COPY ... FROM STDIN`. Para tablas con una columna
  `GENERATED ALWAYS AS IDENTITY` (por ejemplo `comprobante` y `clientes`) copia
  primero a una tabla temporal sin identity y luego ejecuta
  `INSERT ... OVERRIDING SYSTEM VALUE SELECT ...`; así se conservan los IDs
  explícitos y la reproducibilidad.
- `lotes`: `INSERT` multi-fila por lotes (comportamiento histórico).
- `fila`: un `INSERT` por fila; útil solo para mediciones.

Las tablas con menos de 10.000 filas usan lotes aunque el modo sea `copy`.

## Benchmark

`--benchmark` mide los tres métodos con 20.000 renglones de
`detalle_comprobante` y **no deja cambios**: cada método corre dentro de una
transacción con `force_rollback=True`.

- Requiere que la base ya tenga comprobantes y vinos (ejecutar antes el
  generador).
- Deshabilita los triggers de usuario dentro de la misma transacción, para
  medir solo la inserción.
- Al hacer ROLLBACK, PostgreSQL restaura los triggers; el script verifica que
  los 8 queden en `'O'` y aborta si alguno quedó deshabilitado.
- Cada método usa los mismos pares `(cod_comprobante, cod_vino)` y se revierte
  antes del siguiente, así no hay choques de PK y la comparación es justa.

Salida típica:

```text
=== Benchmark de inserción (20.000 renglones, ROLLBACK) ===
  fila por fila      X.XX s  ... filas/s   1.00x
  por lotes          Y.YY s  ... filas/s   A.AAx
  COPY               Z.ZZ s  ... filas/s   B.BBx
```

## Progreso y locks

La generación corre dentro de una única transacción y deshabilita los triggers
de usuario mientras inserta. Por eso no conviene lanzar dos corridas al mismo
tiempo: la segunda quedaría esperando los locks de la primera.

El script registra:

- inicio y fin de cada etapa, con su duración;
- avance de comprobantes cada 25.000 registros;
- avance de las inserciones masivas (por ejemplo `detalle_comprobante`);
- un diagnóstico de `pg_stat_activity` antes del `TRUNCATE`;
- el tiempo que tardó el `TRUNCATE` y un error explícito si vence
  `SEED_LOCK_TIMEOUT`.

## Reproducibilidad

La generación usa `random.Random(seed)` y `Faker("es_AR").seed_instance(seed)`.
Los identificadores se insertan explícitamente y las secuencias se ajustan al
final. Con la misma semilla, la misma fecha de referencia y una base inicial
equivalente, dos corridas producen los mismos datos.

Para verificar la reproducibilidad, ejecutar dos veces de forma secuencial:

```bash
python db/seed/generar_datos.py --reset --seed 42 --fecha-ref 2026-11-08
python db/seed/generar_datos.py --reset --seed 42 --fecha-ref 2026-11-08
```

El reporte final muestra filas por tabla, tiempos por etapa, la cantidad de
tablas con más de 10.000 y 100.000 filas, y un SHA-256 por tabla más un hash
global. Comparar los hashes por tabla y el hash global de ambas corridas: deben
ser idénticos.

## Triggers

Durante la carga se deshabilitan los triggers de usuario de las tablas
`composicion`, `detalle_comprobante`, `ingresos`, `transferencias`,
`detalle_ingreso`, `detalle_transferencia` y `vino` con
`ALTER TABLE ... DISABLE TRIGGER USER`, y se vuelven a habilitar en un
`finally` antes del commit.

**Por qué:** el histórico incluye documentos ya `procesado`/`terminado` con sus
renglones; los triggers `trg_bloqueo_renglon_ingreso` y
`trg_bloqueo_renglon_transferencia` (RN-12) rechazarían esas filas. Además, los
triggers de totales, stock y auditoría modificarían la generación determinista.

**Validaciones equivalentes en Python:**

- composición al 100 % por construcción (cortes de 1, 2 y 3 cepas);
- subtotal, descuento y total de comprobantes calculados en
  `agregar_comprobante`;
- stock de sala/central derivado de transferencias, ingresos y ventas, con
  control explícito de stock central no negativo;
- fechas coherentes (cosecha → ingreso/transferencia → venta) y primera venta
  posterior al suministro;
- filas de `auditoria_precio` generadas explícitamente.

**Riesgos:**

- si la lógica Python tuviera un error, los triggers deshabilitados no lo
  detectarían;
- `ENABLE TRIGGER` no revalida retroactivamente los datos ya insertados;
- toda la carga es una única transacción: si el script falla o se corta,
  PostgreSQL hace ROLLBACK completo (incluidos `TRUNCATE` y
  `DISABLE TRIGGER`), por lo que no quedan datos parciales y los triggers
  vuelven a estar habilitados;
- no ejecutar dos cargas en paralelo: la segunda espera locks de la primera.

Al finalizar, verificar que todos queden en `'O'`:

```sql
SELECT tgname, tgenabled
FROM pg_trigger
WHERE NOT tgisinternal;
```

## Volumen aproximado

| Grupo | Filas aproximadas |
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

## Dump comprimido

Para crear una copia de seguridad comprimida de la base de datos:

```bash
docker exec postgres-bodega pg_dump -U postgres -d bodegas_del_atuel --no-owner --no-acl | gzip > dump_completo.sql.gz
```

Para restaurar la base en un nuevo contenedor o instancia:

```bash
gunzip -c dump_completo.sql.gz | docker exec -i postgres-bodega psql -U postgres -c "CREATE DATABASE bodegas_nueva"
# o contra una base ya creada:
# gunzip -c dump_completo.sql.gz | psql -U postgres -d bodegas_nueva
```

Para verificar los conteos después de la restauración:

```bash
gunzip -c dump_completo.sql.gz | docker exec -i postgres-bodega psql -U postgres -d bodegas_nueva -f db/migrations/001_esquema.sql

# Luego dentro de psql:
SELECT COUNT(*) FROM comprobante;
SELECT COUNT(*) FROM vino;
-- ... verificar todas las tablas esperadas
```

Si el dump comprimido supera los 100 MB, no lo suba al repositorio y agréguelo a `.gitignore`. El tamaño actual es de **9.8 MB** (puede variar según la configuración de la base), por lo que se conserva el archivo generado.

## Reporte de la Etapa 3

A continuación se detallan los resultados de la Etapa 3 de generación:

- **Conteos principales:**
  - Comprobantes: 150.000
  - Vinos: 500
  - Permisos: 3.000
  - Stock central: 500
  - Stock sala: 4.500
  - Ingresos: 1.700
  - Transferencias: 1.995

- **Benchmark de inserción (20.000 renglones, ROLLBACK):**
  - Fila por fila: **31.82 s**
  - Por lotes: **11.93 s**
  - COPY: **5.02 s**

- **Estrategia de triggers:**
  - Durante la carga masiva se deshabilitan los triggers de usuario de las tablas `composicion`, `detalle_comprobante`, `ingresos`, `transferencias`, `detalle_ingreso`, `detalle_transferencia` y `vino` con `ALTER TABLE ... DISABLE TRIGGER USER`, y se vuelven a habilitar en un `finally` antes del commit.
  - Esto permite insertar documentos históricos ya `procesado`/`terminado` sin que los triggers de bloqueo (RN-12) rechacen filas válidas, y evita que los triggers de totales, stock y auditoríaalteren la generación determinista.
  - Las validaciones equivalentes se realizan en Python antes de la inserción: composición al 100% por construcción, subtotal/descuento/total de comprobantes calculados explícitamente, stock de sala/central no negativo, fechas coherentes y auditoría de precio.

- **Hash global:** `47a387a0eb2a4db3b4b0930f16273cba8523e00d8c97212a9c27cc5d605fdf18`
