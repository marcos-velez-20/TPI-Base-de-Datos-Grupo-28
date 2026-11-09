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
```

Ejemplos:

```bash
# Carga desde cero con una fecha de referencia fija
python db/seed/generar_datos.py --reset --seed 42 --fecha-ref 2026-11-08

# Regenerar usando la fecha actual como referencia
python db/seed/generar_datos.py --reset --seed 7

# Aborta si ya hay datos, sin borrar nada
python db/seed/generar_datos.py --seed 42 --fecha-ref 2026-11-08
```

Sin `--reset`, el script aborta si alguna tabla generada ya tiene filas. Con
`--reset` se ejecuta `TRUNCATE ... RESTART IDENTITY CASCADE` únicamente sobre
las tablas generadas. Los catálogos `cepa` y `maridaje` se conservan.

Si los catálogos están vacíos, el generador los carga automáticamente desde
`cepas.csv` y `maridajes.csv`.

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

Durante la carga se deshabilitan los triggers de usuario y se vuelven a
habilitar antes del commit. Al finalizar, verificar que todos queden en `'O'`:

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

## Escenarios incluidos

- Vino `Malbec Reserva` 2021, 750 ml, con corte Malbec 85 / Cabernet 15 y
  maridajes Carnes rojas y Quesos duros.
- Cepa Semillón sin parcelas ni composiciones.
- Ventas de aproximadamente seis años, con actividad en la última semana,
  mes y trimestre.
- Clientes socios sin compras, clientes que nunca compraron tintos y clientes
  forzados a comprar los cinco vinos de la bodega pequeña.
- Vinos estrella vendidos en todas las salas y un vino reservado ausente de la
  sala 15 pero con stock en el depósito central.
- Documentos en distintos estados, con ingresos y transferencias procesados
  antes de las ventas, y sin stock negativo.
