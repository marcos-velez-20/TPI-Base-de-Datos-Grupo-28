# Informe de Etapa 5 — Consultas SQL

Bodegas del Atuel · TPI Bases de Datos · Grupo 28 · UTN FRSR · Ciclo 2026

## 1. Qué hicimos

Resolvimos todas las consignas de la sección 8 en cuatro archivos dentro de la carpeta `consultas/`:

- [`update.sql`](../consultas/update.sql): U1 a U6
- [`insert.sql`](../consultas/insert.sql): I1 a I6
- [`delete.sql`](../consultas/delete.sql): D1 a D6
- [`select.sql`](../consultas/select.sql): S1 a S12

En cada consigna dejamos el enunciado, la consulta y una explicación corta de cómo la pensamos. Los valores que se pueden cambiar (una sala, una bodega, una localidad) están al principio de cada archivo como variables de psql con `\set`, así que para probar con otro dato alcanza con cambiarlo ahí. Por eso los archivos se corren desde psql, por ejemplo con `\i consultas/select.sql`.

Todas las sentencias que modifican datos las probamos dentro de una transacción: primero una consulta de control, después la sentencia, otra vez el control para ver la diferencia y al final `ROLLBACK`, para no ensuciar la base. En los comentarios de cada una anotamos cuántas filas se modificaron.

Algunas consignas piden dos cosas en el mismo enunciado, y las resolvimos con una consulta para cada parte: S10 (rendimiento de todas las parcelas y las que rinden menos que el promedio), S11 (ranking por sala y acumulado mensual) y S12 (división y anti-join). S9 la separamos en tres consultas (datos y stock, cepas y maridajes) para que las cepas no se repitan por cada maridaje.

## 2. Cómo medimos

Medimos sobre la base cargada con el script de la Etapa 3:

- Motor: PostgreSQL 18.3 instalado en Windows
- Datos: `generar_datos.py --seed 42`, con la fecha del día como referencia
- Fecha de las mediciones: 2026-11-09
- Índices: los de `008_indices.sql`

Antes de medir corrimos `ANALYZE;` para que el planificador tuviera las estadísticas al día. Cada `EXPLAIN (ANALYZE, BUFFERS)` lo ejecutamos dos o tres veces y nos quedamos con la última corrida, cuando los datos ya estaban en memoria.

Las filas afectadas que figuran en los comentarios de los archivos `.sql` corresponden a esta misma base. Las consultas que dependen de la fecha actual (última semana, último trimestre, más de 5 años) pueden dar números algo distintos si se ejecutan otro día.

## 3. Resumen de los planes

Medimos las consultas que se usaron en la Etapa 4 (S1, S3, S5, S8 y S12) y las avanzadas (S9 a S12). En la tabla anotamos cómo lee el motor la tabla más grande de cada consulta, qué índice usa y cuánto tarda (el `Execution Time` del final de cada salida).

| Consulta | Origen | Cómo lee la tabla principal | Índice | Filas | Tiempo (ms) |
| --- | --- | --- | --- | --- | --- |
| S1 | Q1 de la Etapa 4 | Parallel Seq Scan sobre `detalle_comprobante` | ninguno | 10 | 177,5 |
| S3 | Q2 de la Etapa 4 | Bitmap Heap Scan sobre `comprobante` | `idx_comprobante_sala_fecha` | 3 | 0,8 |
| S5 | Q5 de la Etapa 4 | Bitmap Heap Scan sobre `transferencias` | `idx_transferencias_pendientes` | 2 | 0,6 |
| S8 | Q3 de la Etapa 4 | Index Only Scan sobre `comprobante` | `idx_comprobante_fecha_cubriente` | 15 | 13,8 |
| S9 (a) | Avanzada | Seq Scan sobre `stock_sala` (desde la vista) | ninguno | 1 | 0,8 |
| S9 (b) | Avanzada | Seq Scan sobre `composicion` | ninguno | 2 | 0,2 |
| S9 (c) | Avanzada | Bitmap Heap Scan sobre `vino_maridaje` | `vino_maridaje_pkey` | 2 | 0,1 |
| S10 (a) | Avanzada | Index Scan sobre `lote_uva` | `lote_uva_id_finca_id_parcela_campania_key` | 3500 | 11,9 |
| S10 (b) | Avanzada | Seq Scan sobre `lote_uva` + Bitmap Heap Scan en la subconsulta | `lote_uva_id_finca_id_parcela_campania_key` | 1749 | 617,7 |
| S11 (a) | Avanzada | Parallel Seq Scan sobre `detalle_comprobante` | ninguno | 45 | 211,2 |
| S11 (b) | Avanzada | Seq Scan sobre `comprobante` | ninguno | 1065 | 122,1 |
| S12 (a) | Avanzada | Bitmap Heap Scan sobre `comprobante` (en la subconsulta) | `idx_comprobante_cliente` | 20 | 839,0 |
| S12 (b) | Avanzada (Q4 de la Etapa 4) | Seq Scan sobre `detalle_comprobante` | ninguno (`idx_comprobante_cliente` en el EXISTS) | 402 | 373,0 |

## 4. Lo que nos llamó la atención

### S9: consultas chicas, casi todo con índices

Las tres partes de S9 tardan menos de 1 ms porque filtran por un solo vino. En S9 (c), `vino_maridaje` se busca con su clave primaria, que empieza por `cod_vino`. En cambio, `composicion` (S9 b) y `stock_sala` (S9 a, a través de la vista) se leen enteras con Seq Scan: sus claves primarias empiezan por la otra columna (`id_cepa` y `id_sala`), así que no sirven para buscar por vino. Con 1.000 y 4.500 filas igual es rápido, pero se ve en el plan cuántas filas descarta (`Rows Removed by Filter: 998` y `4485`). Los catálogos chicos, como `maridaje` (8 filas) o `cepa` (12), también se leen con Seq Scan: entran en una sola página y leerlos enteros es más rápido que pasar por un índice.

### S10: la subconsulta correlacionada

La subconsulta calcula el promedio de la finca para cada una de las 3.500 filas (`loops=3500`). La escribimos contra las tablas `lote_uva` y `parcelas` y no contra la CTE, porque una CTE no tiene índices y habría que recorrerla entera en cada ejecución. Así, cada vez busca con el índice único `(id_finca, id_parcela, campania)` de `lote_uva` y con la clave primaria de `parcelas`, y lee unas 39 filas en lugar de 3.500. La consulta completa tarda 617,7 ms.

```text
SubPlan 1
  ->  Aggregate  (actual time=0.172..0.172 rows=1.00 loops=3500)
        ->  Hash Join  (actual time=0.099..0.149 rows=38.89 loops=3500)
              ->  Bitmap Heap Scan on lote_uva lu2  (rows=38.89 loops=3500)
                    ->  Bitmap Index Scan on lote_uva_id_finca_id_parcela_campania_key
                          Index Cond: ((id_finca = lu.id_finca) AND (campania = lu.campania))
              ->  Hash
                    ->  Bitmap Heap Scan on parcelas p2  (rows=38.89 loops=3500)
                          ->  Bitmap Index Scan on parcelas_pkey
                                Index Cond: (id_finca = lu.id_finca)
```

En S10 (a), que no tiene subconsulta, el motor recorre las 700 parcelas y por cada una busca sus 5 cosechas con el mismo índice de `lote_uva` (`loops=700`), y tarda 11,9 ms.

### S12 (a): la división relacional

Es la consulta más lenta (839 ms). El motor recorre los 20.000 clientes y, para cada uno, revisa los 5 vinos de la bodega hasta encontrar uno que el cliente no haya comprado. Por eso la subconsulta de adentro (`SubPlan 1`) se ejecuta 21.984 veces (`loops=21984`). En cada ejecución busca los comprobantes del cliente con `idx_comprobante_cliente` y después revisa si alguno tiene ese vino con la clave primaria de `detalle_comprobante` (`Index Only Scan`, 158.958 veces). Cada búsqueda es rápida (0,037 ms), pero son muchas: en total lee 681.477 páginas desde memoria.

Sin `idx_comprobante_cliente`, cada una de esas 21.984 búsquedas tendría que recorrer los 150.000 comprobantes. Es el índice de clave foránea de la Etapa 4 haciendo su trabajo.

### S11: las funciones de ventana

En S11 (a), el nodo `WindowAgg` calcula el `RANK()` por sala y tiene una `Run Condition: (rank() OVER w1 <= 3)`: el motor deja de numerar dentro de cada sala cuando pasa el puesto 3, en lugar de calcular el ranking completo y filtrar después. Casi todo el tiempo (211 ms) se va en sumar los 525.000 renglones por sala y vino, no en el ranking. En S11 (b), la suma acumulada se hace sobre solo 1.065 filas (una por sala y mes), así que el `WindowAgg` es casi instantáneo; el costo está en agrupar los 150.000 comprobantes.

### Las consultas de la Etapa 4, ahora como consignas

Los planes coinciden con lo que se midió en la Etapa 4. Los tiempos son distintos porque medimos en otra máquina y con PostgreSQL 18.

- **S1 (Q1):** sigue con Parallel Seq Scan y no usa `idx_detalle_comprobante_vino`. Como no hay filtro y hay que sumar todos los renglones, leer la tabla entera sale más barato. El `LIMIT 10` se resuelve con un *top-N heapsort*, que guarda solo los 10 mayores.
- **S3 (Q2):** usa `idx_comprobante_sala_fecha` con las dos columnas (`id_sala = 13` y el rango de fechas) y lee solo 94 comprobantes de 150.000. Los clientes se buscan uno por uno con su clave primaria (`loops=94`).
- **S5 (Q5):** usa el índice parcial `idx_transferencias_pendientes`, que tiene solo las 185 transferencias no procesadas. En la Etapa 4 era un Index Only Scan; acá es un Bitmap Heap Scan, porque la consulta necesita `num_solicitud`, que no está en el índice, y tiene que ir a la tabla.
- **S8 (Q3):** usa `idx_comprobante_fecha_cubriente` con un Index Only Scan y `Heap Fetches: 0`: todo lo que necesita (fecha, sala y total) está en el índice. El `JOIN` que agregamos con `sala_de_ventas` y `localidades` casi no suma tiempo, porque son tablas de 15 y 30 filas.
- **S12 (b) (Q4):** igual que en la Etapa 4, el anti-join recorre `detalle_comprobante` completa (Seq Scan sobre 525.000 renglones). Lo nuevo es la condición "compró algo alguna vez", que se resuelve con `idx_comprobante_cliente` (Index Only Scan, 1.202 veces).

### Triggers y restricciones con los que nos cruzamos

Varias modificaciones chocaron con reglas que pusimos en la Etapa 2. Lo anotamos porque muestra que las reglas se cumplen aunque se escriba SQL a mano:

- **U1:** no se pueden cambiar los totales de un comprobante directamente, porque un trigger lo impide (RN-08). Para recalcularlos actualizamos los renglones, y los triggers rehacen los importes de la cabecera.
- **U3 y U5:** cada cambio de precio quedó registrado solo en `auditoria_precio` (RN-13). En U3, por ejemplo, la tabla pasó de 30 a 75 filas.
- **U6:** el CHECK de clientes deja que un exportador tenga 30 o 35 % de descuento, así que el cambio se aceptó sin problemas.
- **I3:** cargamos los renglones solo con el vino y la cantidad. El precio, el descuento, el subtotal y el stock los calculó la base.
- **D1 y D5:** al borrar comprobantes o ingresos, sus renglones se borraron solos por `ON DELETE CASCADE`. En D5, el trigger de RN-12 lo permite porque se borra el documento completo.
- **D4 y D6:** solo se pueden borrar clientes sin compras, porque `comprobante` tiene `ON DELETE RESTRICT` hacia `clientes`. La fila del socio se borra en cascada.

### Decisiones que tomamos

Algunas consignas se podían leer de más de una forma. Estas son las que elegimos:

- **S4** devuelve una sola fila. No es un error de la consulta: en los datos generados hay muy pocas transferencias en los últimos 15 días y cada vino aparece en una sola sala.
- **S10** compara cada parcela con el promedio de su finca en la misma campaña, porque comparar años distintos mezclaría cosechas buenas y malas.
- **S12 (b)** cuenta solo a los clientes que compraron algo alguna vez.
- **U5** tiene en cuenta los vinos que nunca se vendieron (cuentan como 0 botellas).
- **I1 y U5:** cuando hay empate, elegimos el de menor código para que el resultado sea siempre el mismo.
- **I3 e I6:** para encontrar el comprobante o el ingreso recién creado usamos `MAX(numero)` y `MAX(id)`. Funciona porque estamos dentro de nuestra propia transacción. Con varios usuarios insertando a la vez, `currval` sería más seguro.

## Anexo. Planes de ejecución completos

### S1 — Ranking de los 10 vinos más vendidos

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT v.id, v.nombre, v.anada, v.volumen, SUM(dc.cantidad) AS botellas
FROM detalle_comprobante dc
JOIN vino v ON v.id = dc.cod_vino
GROUP BY v.id, v.nombre, v.anada, v.volumen
ORDER BY botellas DESC
LIMIT 10;
```

```text
 Limit  (cost=9358.43..9358.46 rows=10 width=48) (actual time=167.474..177.412 rows=10.00 loops=1)
   Buffers: shared hit=4323
   ->  Sort  (cost=9358.43..9359.68 rows=500 width=48) (actual time=167.473..177.409 rows=10.00 loops=1)
         Sort Key: (sum(dc.cantidad)) DESC
         Sort Method: top-N heapsort  Memory: 26kB
         Buffers: shared hit=4323
         ->  Finalize GroupAggregate  (cost=9196.87..9347.63 rows=500 width=48) (actual time=166.601..177.274 rows=500.00 loops=1)
               Group Key: v.id
               Buffers: shared hit=4323
               ->  Gather Merge  (cost=9196.87..9336.63 rows=1200 width=48) (actual time=166.592..176.880 rows=1500.00 loops=1)
                     Workers Planned: 2
                     Workers Launched: 2
                     Buffers: shared hit=4323
                     ->  Sort  (cost=8196.84..8198.09 rows=500 width=48) (actual time=121.497..121.534 rows=500.00 loops=3)
                           Sort Key: v.id
                           Sort Method: quicksort  Memory: 58kB
                           Buffers: shared hit=4323
                           Worker 0:  Sort Method: quicksort  Memory: 58kB
                           Worker 1:  Sort Method: quicksort  Memory: 58kB
                           ->  Partial HashAggregate  (cost=8169.43..8174.43 rows=500 width=48) (actual time=121.193..121.312 rows=500.00 loops=3)
                                 Group Key: v.id
                                 Batches: 1  Memory Usage: 105kB
                                 Buffers: shared hit=4309
                                 Worker 0:  Batches: 1  Memory Usage: 105kB
                                 Worker 1:  Batches: 1  Memory Usage: 105kB
                                 ->  Hash Join  (cost=18.25..7074.87 rows=218911 width=44) (actual time=0.402..81.379 rows=175128.67 loops=3)
                                       Hash Cond: (dc.cod_vino = v.id)
                                       Buffers: shared hit=4309
                                       ->  Parallel Seq Scan on detalle_comprobante dc  (cost=0.00..6477.11 rows=218911 width=8) (actual time=0.015..14.702 rows=175128.67 loops=3)
                                             Buffers: shared hit=4288
                                       ->  Hash  (cost=12.00..12.00 rows=500 width=40) (actual time=0.374..0.375 rows=500.00 loops=3)
                                             Buckets: 1024  Batches: 1  Memory Usage: 45kB
                                             Buffers: shared hit=21
                                             ->  Seq Scan on vino v  (cost=0.00..12.00 rows=500 width=40) (actual time=0.134..0.252 rows=500.00 loops=3)
                                                   Buffers: shared hit=21
 Planning:
   Buffers: shared hit=14
 Planning Time: 0.505 ms
 Execution Time: 177.506 ms
(39 filas)
```

### S3 — Clientes de cada tipo que compraron en la sala 13 en la última semana

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT cl.tipoCliente, COUNT(DISTINCT cl.id) AS clientes
FROM comprobante c
JOIN clientes cl ON cl.id = c.id_cliente
WHERE c.id_sala = 13
  AND c.fecha >= CURRENT_DATE - 7
GROUP BY cl.tipoCliente
ORDER BY clientes DESC;
```

```text
 Sort  (cost=960.97..960.98 rows=3 width=15) (actual time=0.711..0.713 rows=3.00 loops=1)
   Sort Key: (count(DISTINCT cl.id)) DESC
   Sort Method: quicksort  Memory: 25kB
   Buffers: shared hit=376
   ->  GroupAggregate  (cost=960.10..960.95 rows=3 width=15) (actual time=0.684..0.705 rows=3.00 loops=1)
         Group Key: cl.tipocliente
         Buffers: shared hit=376
         ->  Sort  (cost=960.10..960.37 rows=110 width=11) (actual time=0.671..0.678 rows=94.00 loops=1)
               Sort Key: cl.tipocliente, cl.id
               Sort Method: quicksort  Memory: 28kB
               Buffers: shared hit=376
               ->  Nested Loop  (cost=5.71..956.37 rows=110 width=11) (actual time=0.085..0.579 rows=94.00 loops=1)
                     Buffers: shared hit=376
                     ->  Bitmap Heap Scan on comprobante c  (cost=5.43..342.82 rows=110 width=4) (actual time=0.074..0.202 rows=94.00 loops=1)
                           Recheck Cond: ((id_sala = 13) AND (fecha >= (CURRENT_DATE - 7)))
                           Heap Blocks: exact=92
                           Buffers: shared hit=94
                           ->  Bitmap Index Scan on idx_comprobante_sala_fecha  (cost=0.00..5.40 rows=110 width=0) (actual time=0.029..0.029 rows=94.00 loops=1)
                                 Index Cond: ((id_sala = 13) AND (fecha >= (CURRENT_DATE - 7)))
                                 Index Searches: 1
                                 Buffers: shared hit=2
                     ->  Index Scan using clientes_pkey on clientes cl  (cost=0.29..5.58 rows=1 width=11) (actual time=0.003..0.003 rows=1.00 loops=94)
                           Index Cond: (id = c.id_cliente)
                           Index Searches: 94
                           Buffers: shared hit=282
 Planning:
   Buffers: shared hit=16
 Planning Time: 0.631 ms
 Execution Time: 0.775 ms
(29 filas)
```

### S5 — Salas con menos transferencias pendientes

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT s.id_sala, l.nombre AS localidad, COUNT(t.num_solicitud) AS pendientes
FROM sala_de_ventas s
JOIN localidades l ON l.codigo_postal = s.codigo_postal
LEFT JOIN transferencias t ON t.id_sala = s.id_sala AND t.estado <> 'procesado'
GROUP BY s.id_sala, l.nombre
HAVING COUNT(t.num_solicitud) = (
  SELECT MIN(cant) FROM (
    SELECT COUNT(t2.num_solicitud) AS cant
    FROM sala_de_ventas s2
    LEFT JOIN transferencias t2 ON t2.id_sala = s2.id_sala AND t2.estado <> 'procesado'
    GROUP BY s2.id_sala
  ) AS conteos
)
ORDER BY s.id_sala;
```

```text
 Sort  (cost=55.98..55.99 rows=1 width=23) (actual time=0.505..0.509 rows=2.00 loops=1)
   Sort Key: s.id_sala
   Sort Method: quicksort  Memory: 25kB
   Buffers: shared hit=9
   InitPlan 1
     ->  Aggregate  (cost=25.65..25.66 rows=1 width=8) (actual time=0.162..0.163 rows=1.00 loops=1)
           Buffers: shared hit=4
           ->  HashAggregate  (cost=25.31..25.46 rows=15 width=12) (actual time=0.156..0.160 rows=15.00 loops=1)
                 Group Key: s2.id_sala
                 Batches: 1  Memory Usage: 32kB
                 Buffers: shared hit=4
                 ->  Hash Right Join  (cost=10.45..24.39 rows=185 width=8) (actual time=0.038..0.113 rows=185.00 loops=1)
                       Hash Cond: (t2.id_sala = s2.id_sala)
                       Buffers: shared hit=4
                       ->  Bitmap Heap Scan on transferencias t2  (cost=9.12..22.43 rows=185 width=8) (actual time=0.020..0.039 rows=185.00 loops=1)
                             Recheck Cond: (estado <> 'procesado'::estado_documento)
                             Heap Blocks: exact=2
                             Buffers: shared hit=3
                             ->  Bitmap Index Scan on idx_transferencias_pendientes  (cost=0.00..9.07 rows=185 width=0) (actual time=0.010..0.010 rows=185.00 loops=1)
                                   Index Searches: 1
                                   Buffers: shared hit=1
                       ->  Hash  (cost=1.15..1.15 rows=15 width=4) (actual time=0.015..0.015 rows=15.00 loops=1)
                             Buckets: 1024  Batches: 1  Memory Usage: 9kB
                             Buffers: shared hit=1
                             ->  Seq Scan on sala_de_ventas s2  (cost=0.00..1.15 rows=15 width=4) (actual time=0.010..0.011 rows=15.00 loops=1)
                                   Buffers: shared hit=1
   ->  HashAggregate  (cost=28.00..30.31 rows=1 width=23) (actual time=0.496..0.500 rows=2.00 loops=1)
         Group Key: s.id_sala, l.nombre
         Filter: (count(t.num_solicitud) = (InitPlan 1).col1)
         Batches: 1  Memory Usage: 40kB
         Rows Removed by Filter: 13
         Buffers: shared hit=9
         ->  Hash Join  (cost=12.13..26.61 rows=185 width=19) (actual time=0.110..0.260 rows=185.00 loops=1)
               Hash Cond: (s.codigo_postal = l.codigo_postal)
               Buffers: shared hit=5
               ->  Hash Right Join  (cost=10.45..24.39 rows=185 width=12) (actual time=0.069..0.157 rows=185.00 loops=1)
                     Hash Cond: (t.id_sala = s.id_sala)
                     Buffers: shared hit=4
                     ->  Bitmap Heap Scan on transferencias t  (cost=9.12..22.43 rows=185 width=8) (actual time=0.043..0.063 rows=185.00 loops=1)
                           Recheck Cond: (estado <> 'procesado'::estado_documento)
                           Heap Blocks: exact=2
                           Buffers: shared hit=3
                           ->  Bitmap Index Scan on idx_transferencias_pendientes  (cost=0.00..9.07 rows=185 width=0) (actual time=0.024..0.024 rows=185.00 loops=1)
                                 Index Searches: 1
                                 Buffers: shared hit=1
                     ->  Hash  (cost=1.15..1.15 rows=15 width=8) (actual time=0.016..0.017 rows=15.00 loops=1)
                           Buckets: 1024  Batches: 1  Memory Usage: 9kB
                           Buffers: shared hit=1
                           ->  Seq Scan on sala_de_ventas s  (cost=0.00..1.15 rows=15 width=8) (actual time=0.010..0.013 rows=15.00 loops=1)
                                 Buffers: shared hit=1
               ->  Hash  (cost=1.30..1.30 rows=30 width=15) (actual time=0.037..0.037 rows=30.00 loops=1)
                     Buckets: 1024  Batches: 1  Memory Usage: 10kB
                     Buffers: shared hit=1
                     ->  Seq Scan on localidades l  (cost=0.00..1.30 rows=30 width=15) (actual time=0.023..0.027 rows=30.00 loops=1)
                           Buffers: shared hit=1
 Planning:
   Buffers: shared hit=12
 Planning Time: 0.813 ms
 Execution Time: 0.606 ms
(59 filas)
```

### S8 — Monto de ventas por sala en el último trimestre

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.id_sala, l.nombre AS localidad, SUM(c.total) AS monto
FROM comprobante c
JOIN sala_de_ventas s ON s.id_sala = c.id_sala
JOIN localidades l ON l.codigo_postal = s.codigo_postal
WHERE c.fecha >= CURRENT_DATE - INTERVAL '3 months'
GROUP BY c.id_sala, l.nombre
ORDER BY monto DESC;
```

```text
 Sort  (cost=735.22..736.34 rows=450 width=47) (actual time=13.693..13.697 rows=15.00 loops=1)
   Sort Key: (sum(c.total)) DESC
   Sort Method: quicksort  Memory: 25kB
   Buffers: shared hit=84
   ->  HashAggregate  (cost=709.76..715.39 rows=450 width=47) (actual time=13.662..13.676 rows=15.00 loops=1)
         Group Key: c.id_sala, l.nombre
         Batches: 1  Memory Usage: 48kB
         Buffers: shared hit=84
         ->  Hash Join  (cost=3.44..617.38 rows=12318 width=23) (actual time=0.095..8.648 rows=12010.00 loops=1)
               Hash Cond: (s.codigo_postal = l.codigo_postal)
               Buffers: shared hit=84
               ->  Hash Join  (cost=1.76..578.80 rows=12318 width=16) (actual time=0.052..5.368 rows=12010.00 loops=1)
                     Hash Cond: (c.id_sala = s.id_sala)
                     Buffers: shared hit=83
                     ->  Index Only Scan using idx_comprobante_fecha_cubriente on comprobante c  (cost=0.42..535.99 rows=12318 width=12) (actual time=0.030..1.923 rows=12010.00 loops=1)
                           Index Cond: (fecha >= (CURRENT_DATE - '3 mons'::interval))
                           Heap Fetches: 0
                           Index Searches: 1
                           Buffers: shared hit=82
                     ->  Hash  (cost=1.15..1.15 rows=15 width=8) (actual time=0.017..0.018 rows=15.00 loops=1)
                           Buckets: 1024  Batches: 1  Memory Usage: 9kB
                           Buffers: shared hit=1
                           ->  Seq Scan on sala_de_ventas s  (cost=0.00..1.15 rows=15 width=8) (actual time=0.011..0.013 rows=15.00 loops=1)
                                 Buffers: shared hit=1
               ->  Hash  (cost=1.30..1.30 rows=30 width=15) (actual time=0.039..0.039 rows=30.00 loops=1)
                     Buckets: 1024  Batches: 1  Memory Usage: 10kB
                     Buffers: shared hit=1
                     ->  Seq Scan on localidades l  (cost=0.00..1.30 rows=30 width=15) (actual time=0.025..0.030 rows=30.00 loops=1)
                           Buffers: shared hit=1
 Planning:
   Buffers: shared hit=8
 Planning Time: 0.528 ms
 Execution Time: 13.821 ms
(33 filas)
```

### S9 (a) — Ficha de un vino: datos, bodega, cantidades y stock (vino 1)

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT v.id, v.nombre, v.tipo, v.anada, v.volumen, v.graduacion, v.precio,
  b.razon_social AS bodega,
  (SELECT COUNT(*) FROM composicion co WHERE co.id_vino = v.id) AS cantidad_cepas,
  (SELECT COUNT(*) FROM vino_maridaje vm WHERE vm.cod_vino = v.id) AS cantidad_maridajes,
  st.stock_deposito, st.stock_salas, st.stock_total
FROM vino v
JOIN bodega b ON b.cuit = v.cuit_bodega
JOIN vista_stock_total_vino st ON st.cod_vino = v.id
WHERE v.id = 1;
```

```text
 Nested Loop  (cost=98.56..135.04 rows=1 width=106) (actual time=0.765..0.770 rows=1.00 loops=1)
   Join Filter: ((b.cuit)::text = (v.cuit_bodega)::text)
   Buffers: shared hit=44
   ->  Nested Loop  (cost=98.56..106.72 rows=1 width=82) (actual time=0.488..0.492 rows=1.00 loops=1)
         Buffers: shared hit=34
         ->  Index Scan using vino_pkey on vino v  (cost=0.27..8.29 rows=1 width=70) (actual time=0.016..0.018 rows=1.00 loops=1)
               Index Cond: (id = 1)
               Index Searches: 1
               Buffers: shared hit=3
         ->  GroupAggregate  (cost=98.28..98.41 rows=1 width=56) (actual time=0.469..0.470 rows=1.00 loops=1)
               Group Key: dc.cantidad
               Buffers: shared hit=31
               ->  Sort  (cost=98.28..98.32 rows=15 width=48) (actual time=0.452..0.455 rows=15.00 loops=1)
                     Sort Key: dc.cantidad
                     Sort Method: quicksort  Memory: 25kB
                     Buffers: shared hit=31
                     ->  Nested Loop Left Join  (cost=0.55..97.99 rows=15 width=48) (actual time=0.049..0.433 rows=15.00 loops=1)
                           Buffers: shared hit=31
                           ->  Nested Loop Left Join  (cost=0.55..16.59 rows=1 width=44) (actual time=0.017..0.022 rows=1.00 loops=1)
                                 Buffers: shared hit=6
                                 ->  Index Scan using vino_pkey on vino v_1  (cost=0.27..8.29 rows=1 width=40) (actual time=0.004..0.009 rows=1.00 loops=1)
                                       Index Cond: (id = 1)
                                       Index Searches: 1
                                       Buffers: shared hit=3
                                 ->  Index Scan using stock_central_pkey on stock_central dc  (cost=0.27..8.29 rows=1 width=8) (actual time=0.010..0.010 rows=1.00 loops=1)
                                       Index Cond: (codigo_vino = 1)
                                       Index Searches: 1
                                       Buffers: shared hit=3
                           ->  Seq Scan on stock_sala ds  (cost=0.00..81.25 rows=15 width=8) (actual time=0.031..0.407 rows=15.00 loops=1)
                                 Filter: (cod_vino = 1)
                                 Rows Removed by Filter: 4485
                                 Buffers: shared hit=25
   ->  Seq Scan on bodega b  (cost=0.00..1.12 rows=12 width=32) (actual time=0.029..0.029 rows=1.00 loops=1)
         Buffers: shared hit=1
   SubPlan 1
     ->  Aggregate  (cost=18.50..18.52 rows=1 width=8) (actual time=0.195..0.196 rows=1.00 loops=1)
           Buffers: shared hit=6
           ->  Seq Scan on composicion co  (cost=0.00..18.50 rows=2 width=0) (actual time=0.012..0.193 rows=2.00 loops=1)
                 Filter: (id_vino = v.id)
                 Rows Removed by Filter: 998
                 Buffers: shared hit=6
   SubPlan 2
     ->  Aggregate  (cost=8.53..8.54 rows=1 width=8) (actual time=0.042..0.042 rows=1.00 loops=1)
           Buffers: shared hit=3
           ->  Bitmap Heap Scan on vino_maridaje vm  (cost=4.29..8.52 rows=2 width=0) (actual time=0.038..0.039 rows=2.00 loops=1)
                 Recheck Cond: (cod_vino = v.id)
                 Heap Blocks: exact=1
                 Buffers: shared hit=3
                 ->  Bitmap Index Scan on vino_maridaje_pkey  (cost=0.00..4.29 rows=2 width=0) (actual time=0.010..0.010 rows=2.00 loops=1)
                       Index Cond: (cod_vino = v.id)
                       Index Searches: 1
                       Buffers: shared hit=2
 Planning:
   Buffers: shared hit=4
 Planning Time: 0.745 ms
 Execution Time: 0.847 ms
(56 filas)
```

### S9 (b) — Ficha de un vino: cepas y porcentajes

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT ce.nombre AS cepa, co.porcentaje
FROM composicion co
JOIN cepa ce ON ce.identificador = co.id_cepa
WHERE co.id_vino = 1
ORDER BY co.porcentaje DESC;
```

```text
 Sort  (cost=19.79..19.79 rows=2 width=15) (actual time=0.207..0.209 rows=2.00 loops=1)
   Sort Key: co.porcentaje DESC
   Sort Method: quicksort  Memory: 25kB
   Buffers: shared hit=7
   ->  Hash Join  (cost=1.27..19.78 rows=2 width=15) (actual time=0.055..0.148 rows=2.00 loops=1)
         Hash Cond: (co.id_cepa = ce.identificador)
         Buffers: shared hit=7
         ->  Seq Scan on composicion co  (cost=0.00..18.50 rows=2 width=9) (actual time=0.030..0.121 rows=2.00 loops=1)
               Filter: (id_vino = 1)
               Rows Removed by Filter: 998
               Buffers: shared hit=6
         ->  Hash  (cost=1.12..1.12 rows=12 width=14) (actual time=0.018..0.019 rows=12.00 loops=1)
               Buckets: 1024  Batches: 1  Memory Usage: 9kB
               Buffers: shared hit=1
               ->  Seq Scan on cepa ce  (cost=0.00..1.12 rows=12 width=14) (actual time=0.010..0.013 rows=12.00 loops=1)
                     Buffers: shared hit=1
 Planning:
   Buffers: shared hit=4
 Planning Time: 0.434 ms
 Execution Time: 0.241 ms
(20 filas)
```

### S9 (c) — Ficha de un vino: maridajes

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT m.nombre AS maridaje, m.temperatura
FROM vino_maridaje vm
JOIN maridaje m ON m.id = vm.cod_maridaje
WHERE vm.cod_vino = 1
ORDER BY m.nombre;
```

```text
 Sort  (cost=9.72..9.72 rows=2 width=20) (actual time=0.081..0.083 rows=2.00 loops=1)
   Sort Key: m.nombre
   Sort Method: quicksort  Memory: 25kB
   Buffers: shared hit=4
   ->  Hash Join  (cost=5.47..9.71 rows=2 width=20) (actual time=0.060..0.063 rows=2.00 loops=1)
         Hash Cond: (vm.cod_maridaje = m.id)
         Buffers: shared hit=4
         ->  Bitmap Heap Scan on vino_maridaje vm  (cost=4.29..8.52 rows=2 width=4) (actual time=0.022..0.022 rows=2.00 loops=1)
               Recheck Cond: (cod_vino = 1)
               Heap Blocks: exact=1
               Buffers: shared hit=3
               ->  Bitmap Index Scan on vino_maridaje_pkey  (cost=0.00..4.29 rows=2 width=0) (actual time=0.009..0.010 rows=2.00 loops=1)
                     Index Cond: (cod_vino = 1)
                     Index Searches: 1
                     Buffers: shared hit=2
         ->  Hash  (cost=1.08..1.08 rows=8 width=24) (actual time=0.029..0.030 rows=8.00 loops=1)
               Buckets: 1024  Batches: 1  Memory Usage: 9kB
               Buffers: shared hit=1
               ->  Seq Scan on maridaje m  (cost=0.00..1.08 rows=8 width=24) (actual time=0.022..0.024 rows=8.00 loops=1)
                     Buffers: shared hit=1
 Planning:
   Buffers: shared hit=4
 Planning Time: 0.405 ms
 Execution Time: 0.138 ms
(24 filas)
```

### S10 (a) — Rendimiento kg/ha por parcela y campaña

```sql
EXPLAIN (ANALYZE, BUFFERS)
WITH rendimiento AS (
  SELECT lu.id_finca, lu.id_parcela, lu.campania,
    lu.kilo_cosechado / p.superficie AS kg_ha
  FROM lote_uva lu
  JOIN parcelas p ON p.id_finca = lu.id_finca AND p.identificador = lu.id_parcela
)
SELECT r.id_finca, f.nombre AS finca, r.id_parcela, r.campania,
  ROUND(r.kg_ha, 2) AS kg_ha
FROM rendimiento r
JOIN finca f ON f.id = r.id_finca
ORDER BY r.id_finca, r.campania, r.id_parcela;
```

```text
 Sort  (cost=339.70..348.45 rows=3500 width=61) (actual time=11.252..11.522 rows=3500.00 loops=1)
   Sort Key: lu.id_finca, lu.campania, lu.id_parcela
   Sort Method: quicksort  Memory: 283kB
   Buffers: shared hit=2106
   ->  Nested Loop  (cost=1.70..133.67 rows=3500 width=61) (actual time=0.107..6.843 rows=3500.00 loops=1)
         Buffers: shared hit=2106
         ->  Hash Join  (cost=1.41..15.68 rows=700 width=36) (actual time=0.076..0.448 rows=700.00 loops=1)
               Hash Cond: (p.id_finca = f.id)
               Buffers: shared hit=6
               ->  Seq Scan on parcelas p  (cost=0.00..12.00 rows=700 width=13) (actual time=0.033..0.105 rows=700.00 loops=1)
                     Buffers: shared hit=5
               ->  Hash  (cost=1.18..1.18 rows=18 width=23) (actual time=0.024..0.025 rows=18.00 loops=1)
                     Buckets: 1024  Batches: 1  Memory Usage: 9kB
                     Buffers: shared hit=1
                     ->  Seq Scan on finca f  (cost=0.00..1.18 rows=18 width=23) (actual time=0.014..0.017 rows=18.00 loops=1)
                           Buffers: shared hit=1
         ->  Memoize  (cost=0.29..0.69 rows=5 width=16) (actual time=0.003..0.007 rows=5.00 loops=700)
               Cache Key: p.id_finca, p.identificador
               Cache Mode: logical
               Hits: 0  Misses: 700  Evictions: 0  Overflows: 0  Memory Usage: 217kB
               Buffers: shared hit=2100
               ->  Index Scan using lote_uva_id_finca_id_parcela_campania_key on lote_uva lu  (cost=0.28..0.68 rows=5 width=16) (actual time=0.003..0.004 rows=5.00 loops=700)
                     Index Cond: ((id_finca = p.id_finca) AND (id_parcela = p.identificador))
                     Index Searches: 700
                     Buffers: shared hit=2100
 Planning:
   Buffers: shared hit=8
 Planning Time: 0.766 ms
 Execution Time: 11.867 ms
(29 filas)
```

### S10 (b) — Parcelas que rinden menos que el promedio de su finca

```sql
EXPLAIN (ANALYZE, BUFFERS)
WITH rendimiento AS (
  SELECT lu.id_finca, lu.id_parcela, lu.campania,
    lu.kilo_cosechado / p.superficie AS kg_ha
  FROM lote_uva lu
  JOIN parcelas p ON p.id_finca = lu.id_finca AND p.identificador = lu.id_parcela
)
SELECT r.id_finca, f.nombre AS finca, r.id_parcela, r.campania,
  ROUND(r.kg_ha, 2) AS kg_ha
FROM rendimiento r
JOIN finca f ON f.id = r.id_finca
WHERE r.kg_ha < (
  SELECT AVG(lu2.kilo_cosechado / p2.superficie)
  FROM lote_uva lu2
  JOIN parcelas p2 ON p2.id_finca = lu2.id_finca AND p2.identificador = lu2.id_parcela
  WHERE lu2.id_finca = r.id_finca AND lu2.campania = r.campania
)
ORDER BY r.id_finca, r.campania, kg_ha;
```

```text
 Sort  (cost=282.96..285.88 rows=1167 width=61) (actual time=617.380..617.495 rows=1749.00 loops=1)
   Sort Key: lu.id_finca, lu.campania, (round((lu.kilo_cosechado / p.superficie), 2))
   Sort Method: quicksort  Memory: 142kB
   Buffers: shared hit=134981
   ->  Hash Join  (cost=23.91..223.51 rows=1167 width=61) (actual time=0.732..614.348 rows=1749.00 loops=1)
         Hash Cond: (p.id_finca = f.id)
         Buffers: shared hit=134981
         ->  Hash Join  (cost=22.50..212.49 rows=1167 width=25) (actual time=0.688..612.082 rows=1749.00 loops=1)
               Hash Cond: ((lu.id_finca = p.id_finca) AND (lu.id_parcela = p.identificador))
               Join Filter: ((lu.kilo_cosechado / p.superficie) < (SubPlan 1))
               Rows Removed by Join Filter: 1751
               Buffers: shared hit=134980
               ->  Seq Scan on lote_uva lu  (cost=0.00..65.00 rows=3500 width=16) (actual time=0.014..0.713 rows=3500.00 loops=1)
                     Buffers: shared hit=30
               ->  Hash  (cost=12.00..12.00 rows=700 width=13) (actual time=0.286..0.287 rows=700.00 loops=1)
                     Buckets: 1024  Batches: 1  Memory Usage: 41kB
                     Buffers: shared hit=5
                     ->  Seq Scan on parcelas p  (cost=0.00..12.00 rows=700 width=13) (actual time=0.018..0.141 rows=700.00 loops=1)
                           Buffers: shared hit=5
               SubPlan 1
                 ->  Aggregate  (cost=53.28..53.29 rows=1 width=32) (actual time=0.172..0.172 rows=1.00 loops=3500)
                       Buffers: shared hit=134945
                       ->  Hash Join  (cost=20.78..53.08 rows=39 width=11) (actual time=0.099..0.149 rows=38.89 loops=3500)
                             Hash Cond: (lu2.id_parcela = p2.identificador)
                             Buffers: shared hit=134945
                             ->  Bitmap Heap Scan on lote_uva lu2  (cost=10.23..42.42 rows=39 width=14) (actual time=0.043..0.071 rows=38.89 loops=3500)
                                   Recheck Cond: ((id_finca = lu.id_finca) AND (campania = lu.campania))
                                   Heap Blocks: exact=102280
                                   Buffers: shared hit=110445
                                   ->  Bitmap Index Scan on lote_uva_id_finca_id_parcela_campania_key  (cost=0.00..10.22 rows=39 width=0) (actual time=0.039..0.039 rows=38.89 loops=3500)
                                         Index Cond: ((id_finca = lu.id_finca) AND (campania = lu.campania))
                                         Index Searches: 3500
                                         Buffers: shared hit=8165
                             ->  Hash  (cost=10.06..10.06 rows=39 width=13) (actual time=0.045..0.045 rows=38.89 loops=3500)
                                   Buckets: 1024  Batches: 1  Memory Usage: 10kB
                                   Buffers: shared hit=24500
                                   ->  Bitmap Heap Scan on parcelas p2  (cost=4.58..10.06 rows=39 width=13) (actual time=0.011..0.025 rows=38.89 loops=3500)
                                         Recheck Cond: (id_finca = lu.id_finca)
                                         Heap Blocks: exact=17500
                                         Buffers: shared hit=24500
                                         ->  Bitmap Index Scan on parcelas_pkey  (cost=0.00..4.57 rows=39 width=0) (actual time=0.007..0.007 rows=38.89 loops=3500)
                                               Index Cond: (id_finca = lu.id_finca)
                                               Index Searches: 3500
                                               Buffers: shared hit=7000
         ->  Hash  (cost=1.18..1.18 rows=18 width=23) (actual time=0.037..0.037 rows=18.00 loops=1)
               Buckets: 1024  Batches: 1  Memory Usage: 9kB
               Buffers: shared hit=1
               ->  Seq Scan on finca f  (cost=0.00..1.18 rows=18 width=23) (actual time=0.024..0.027 rows=18.00 loops=1)
                     Buffers: shared hit=1
 Planning:
   Buffers: shared hit=8
 Planning Time: 0.829 ms
 Execution Time: 617.749 ms
(53 filas)
```

### S11 (a) — Ranking de vinos dentro de cada sala

```sql
EXPLAIN (ANALYZE, BUFFERS)
WITH ranking AS (
  SELECT c.id_sala, dc.cod_vino, SUM(dc.cantidad) AS botellas,
    RANK() OVER (PARTITION BY c.id_sala ORDER BY SUM(dc.cantidad) DESC) AS puesto
  FROM comprobante c
  JOIN detalle_comprobante dc ON dc.cod_comprobante = c.numero
  GROUP BY c.id_sala, dc.cod_vino
)
SELECT r.id_sala, r.puesto, r.cod_vino, v.nombre, r.botellas
FROM ranking r
JOIN vino v ON v.id = r.cod_vino
WHERE r.puesto <= 3
ORDER BY r.id_sala, r.puesto, r.cod_vino;
```

```text
 Sort  (cost=16351.44..16370.19 rows=7500 width=54) (actual time=208.813..210.670 rows=45.00 loops=1)
   Sort Key: c.id_sala, (rank() OVER w1), dc.cod_vino
   Sort Method: quicksort  Memory: 28kB
   Buffers: shared hit=5654
   ->  Hash Join  (cost=15623.88..15868.71 rows=7500 width=54) (actual time=207.735..210.639 rows=45.00 loops=1)
         Hash Cond: (dc.cod_vino = v.id)
         Buffers: shared hit=5654
         ->  WindowAgg  (cost=15605.63..15755.61 rows=7500 width=24) (actual time=207.523..210.391 rows=45.00 loops=1)
               Window: w1 AS (PARTITION BY c.id_sala ORDER BY (sum(dc.cantidad)) ROWS UNBOUNDED PRECEDING)
               Run Condition: (rank() OVER w1 <= 3)
               Storage: Memory  Maximum Storage: 17kB
               Buffers: shared hit=5647
               ->  Sort  (cost=15605.61..15624.36 rows=7500 width=16) (actual time=207.509..209.771 rows=4500.00 loops=1)
                     Sort Key: c.id_sala, (sum(dc.cantidad)) DESC
                     Sort Method: quicksort  Memory: 333kB
                     Buffers: shared hit=5647
                     ->  Finalize HashAggregate  (cost=15047.88..15122.88 rows=7500 width=16) (actual time=203.590..206.708 rows=4500.00 loops=1)
                           Group Key: c.id_sala, dc.cod_vino
                           Batches: 1  Memory Usage: 537kB
                           Buffers: shared hit=5647
                           ->  Gather  (cost=13037.88..14912.88 rows=18000 width=16) (actual time=195.511..200.552 rows=13500.00 loops=1)
                                 Workers Planned: 2
                                 Workers Launched: 2
                                 Buffers: shared hit=5647
                                 ->  Partial HashAggregate  (cost=12037.88..12112.88 rows=7500 width=16) (actual time=150.934..151.934 rows=4500.00 loops=3)
                                       Group Key: c.id_sala, dc.cod_vino
                                       Batches: 1  Memory Usage: 537kB
                                       Buffers: shared hit=5647
                                       Worker 0:  Batches: 1  Memory Usage: 537kB
                                       Worker 1:  Batches: 1  Memory Usage: 537kB
                                       ->  Parallel Hash Join  (cost=3344.29..10396.05 rows=218911 width=12) (actual time=20.358..99.519 rows=175128.67 loops=3)
                                             Hash Cond: (dc.cod_comprobante = c.numero)
                                             Buffers: shared hit=5647
                                             ->  Parallel Seq Scan on detalle_comprobante dc  (cost=0.00..6477.11 rows=218911 width=12) (actual time=0.015..15.060 rows=175128.67 loops=3)
                                                   Buffers: shared hit=4288
                                             ->  Parallel Hash  (cost=2241.35..2241.35 rows=88235 width=8) (actual time=19.765..19.765 rows=50000.00 loops=3)
                                                   Buckets: 262144  Batches: 1  Memory Usage: 7936kB
                                                   Buffers: shared hit=1359
                                                   ->  Parallel Seq Scan on comprobante c  (cost=0.00..2241.35 rows=88235 width=8) (actual time=0.015..23.189 rows=150000.00 loops=1)
                                                         Buffers: shared hit=1359
         ->  Hash  (cost=12.00..12.00 rows=500 width=34) (actual time=0.204..0.205 rows=500.00 loops=1)
               Buckets: 1024  Batches: 1  Memory Usage: 42kB
               Buffers: shared hit=7
               ->  Seq Scan on vino v  (cost=0.00..12.00 rows=500 width=34) (actual time=0.028..0.100 rows=500.00 loops=1)
                     Buffers: shared hit=7
 Planning:
   Buffers: shared hit=16
 Planning Time: 0.705 ms
 Execution Time: 211.213 ms
(49 filas)
```

### S11 (b) — Ventas mensuales acumuladas por sala

```sql
EXPLAIN (ANALYZE, BUFFERS)
WITH ventas_mes AS (
  SELECT id_sala, DATE_TRUNC('month', fecha)::DATE AS mes, SUM(total) AS monto
  FROM comprobante
  GROUP BY id_sala, DATE_TRUNC('month', fecha)
)
SELECT id_sala, mes, monto,
  SUM(monto) OVER (PARTITION BY id_sala ORDER BY mes) AS acumulado
FROM ventas_mes
ORDER BY id_sala, mes;
```

```text
 WindowAgg  (cost=6299.47..6599.45 rows=15000 width=72) (actual time=120.397..121.661 rows=1065.00 loops=1)
   Window: w1 AS (PARTITION BY ventas_mes.id_sala ORDER BY ventas_mes.mes)
   Storage: Memory  Maximum Storage: 17kB
   Buffers: shared hit=1359
   ->  Sort  (cost=6299.45..6336.95 rows=15000 width=40) (actual time=120.382..120.454 rows=1065.00 loops=1)
         Sort Key: ventas_mes.id_sala, ventas_mes.mes
         Sort Method: quicksort  Memory: 89kB
         Buffers: shared hit=1359
         ->  Subquery Scan on ventas_mes  (cost=4734.00..5259.00 rows=15000 width=40) (actual time=118.800..119.839 rows=1065.00 loops=1)
               Buffers: shared hit=1359
               ->  HashAggregate  (cost=4734.00..5109.00 rows=15000 width=48) (actual time=118.797..119.663 rows=1065.00 loops=1)
                     Group Key: comprobante.id_sala, date_trunc('month'::text, (comprobante.fecha)::timestamp with time zone)
                     Batches: 1  Memory Usage: 1105kB
                     Buffers: shared hit=1359
                     ->  Seq Scan on comprobante  (cost=0.00..3609.00 rows=150000 width=24) (actual time=0.033..65.772 rows=150000.00 loops=1)
                           Buffers: shared hit=1359
 Planning Time: 0.343 ms
 Execution Time: 122.086 ms
(18 filas)
```

### S12 (a) — Clientes que compraron todos los vinos de Bodega Pequeña Selección

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT cl.id, cl.tipoCliente
FROM clientes cl
WHERE NOT EXISTS (
  SELECT 1 FROM vino v
  JOIN bodega b ON b.cuit = v.cuit_bodega
  WHERE b.razon_social = 'Bodega Pequeña Selección'
    AND NOT EXISTS (
      SELECT 1 FROM comprobante c
      JOIN detalle_comprobante dc ON dc.cod_comprobante = c.numero
      WHERE c.id_cliente = cl.id AND dc.cod_vino = v.id
    )
)
ORDER BY cl.id;
```

```text
 Nested Loop Anti Join  (cost=1.45..32612809.27 rows=10000 width=11) (actual time=14.984..838.884 rows=20.00 loops=1)
   Join Filter: (NOT EXISTS(SubPlan 1))
   Rows Removed by Join Filter: 2004
   Buffers: shared hit=681477
   ->  Index Scan using clientes_pkey on clientes cl  (cost=0.29..756.29 rows=20000 width=11) (actual time=0.022..7.371 rows=20000.00 loops=1)
         Index Searches: 1
         Buffers: shared hit=281
   ->  Materialize  (cost=1.16..15.15 rows=42 width=4) (actual time=0.000..0.000 rows=1.10 loops=20000)
         Storage: Memory  Maximum Storage: 17kB
         Buffers: shared hit=8
         ->  Hash Join  (cost=1.16..14.94 rows=42 width=4) (actual time=0.067..0.184 rows=5.00 loops=1)
               Hash Cond: ((v.cuit_bodega)::text = (b.cuit)::text)
               Buffers: shared hit=8
               ->  Seq Scan on vino v  (cost=0.00..12.00 rows=500 width=16) (actual time=0.034..0.077 rows=500.00 loops=1)
                     Buffers: shared hit=7
               ->  Hash  (cost=1.15..1.15 rows=1 width=12) (actual time=0.023..0.024 rows=1.00 loops=1)
                     Buckets: 1024  Batches: 1  Memory Usage: 9kB
                     Buffers: shared hit=1
                     ->  Seq Scan on bodega b  (cost=0.00..1.15 rows=1 width=12) (actual time=0.016..0.017 rows=1.00 loops=1)
                           Filter: ((razon_social)::text = 'Bodega Pequeña Selección'::text)
                           Rows Removed by Filter: 11
                           Buffers: shared hit=1
   SubPlan 1
     ->  Nested Loop  (cost=4.78..74.18 rows=1 width=0) (actual time=0.037..0.037 rows=0.09 loops=21984)
           Buffers: shared hit=681188
           ->  Bitmap Heap Scan on comprobante c  (cost=4.36..34.62 rows=8 width=4) (actual time=0.005..0.010 rows=7.23 loops=21984)
                 Recheck Cond: (id_cliente = cl.id)
                 Heap Blocks: exact=158582
                 Buffers: shared hit=204313
                 ->  Bitmap Index Scan on idx_comprobante_cliente  (cost=0.00..4.35 rows=8 width=0) (actual time=0.003..0.003 rows=7.61 loops=21984)
                       Index Cond: (id_cliente = cl.id)
                       Index Searches: 21984
                       Buffers: shared hit=43968
           ->  Index Only Scan using detalle_comprobante_pkey on detalle_comprobante dc  (cost=0.42..4.94 rows=1 width=4) (actual time=0.002..0.002 rows=0.01 loops=158958)
                 Index Cond: ((cod_comprobante = c.numero) AND (cod_vino = v.id))
                 Heap Fetches: 0
                 Index Searches: 158958
                 Buffers: shared hit=476875
 Planning:
   Buffers: shared hit=36
 Planning Time: 1.073 ms
 Execution Time: 838.977 ms
(42 filas)
```

### S12 (b) — Clientes que nunca compraron vino tinto

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT cl.id, cl.tipoCliente
FROM clientes cl
WHERE EXISTS (SELECT 1 FROM comprobante c WHERE c.id_cliente = cl.id)
  AND NOT EXISTS (
    SELECT 1 FROM comprobante c
    JOIN detalle_comprobante dc ON dc.cod_comprobante = c.numero
    JOIN vino v ON v.id = dc.cod_vino
    WHERE c.id_cliente = cl.id AND v.tipo = 'tinto'
  )
ORDER BY cl.id;
```

```text
 Sort  (cost=22170.57..22173.93 rows=1341 width=11) (actual time=371.776..371.807 rows=402.00 loops=1)
   Sort Key: cl.id
   Sort Method: quicksort  Memory: 37kB
   Buffers: shared hit=8284
   ->  Nested Loop Semi Join  (cost=5426.55..22100.92 rows=1341 width=11) (actual time=369.002..371.659 rows=402.00 loops=1)
         Buffers: shared hit=8284
         ->  Hash Right Anti Join  (cost=5426.25..21594.74 rows=1445 width=11) (actual time=368.959..369.744 rows=1202.00 loops=1)
               Hash Cond: (c_1.id_cliente = cl.id)
               Buffers: shared hit=5879
               ->  Hash Join  (cost=4751.25..16566.61 rows=336247 width=4) (actual time=52.023..298.663 rows=329751.00 loops=1)
                     Hash Cond: (dc.cod_comprobante = c_1.numero)
                     Buffers: shared hit=5654
                     ->  Hash Join  (cost=17.25..10949.94 rows=336247 width=4) (actual time=0.220..146.337 rows=329751.00 loops=1)
                           Hash Cond: (dc.cod_vino = v.id)
                           Buffers: shared hit=4295
                           ->  Seq Scan on detalle_comprobante dc  (cost=0.00..9541.86 rows=525386 width=8) (actual time=0.016..37.783 rows=525386.00 loops=1)
                                 Buffers: shared hit=4288
                           ->  Hash  (cost=13.25..13.25 rows=320 width=4) (actual time=0.155..0.156 rows=320.00 loops=1)
                                 Buckets: 1024  Batches: 1  Memory Usage: 20kB
                                 Buffers: shared hit=7
                                 ->  Seq Scan on vino v  (cost=0.00..13.25 rows=320 width=4) (actual time=0.017..0.111 rows=320.00 loops=1)
                                       Filter: ((tipo)::text = 'tinto'::text)
                                       Rows Removed by Filter: 180
                                       Buffers: shared hit=7
                     ->  Hash  (cost=2859.00..2859.00 rows=150000 width=8) (actual time=51.321..51.321 rows=150000.00 loops=1)
                           Buckets: 262144  Batches: 1  Memory Usage: 7908kB
                           Buffers: shared hit=1359
                           ->  Seq Scan on comprobante c_1  (cost=0.00..2859.00 rows=150000 width=8) (actual time=0.017..22.927 rows=150000.00 loops=1)
                                 Buffers: shared hit=1359
               ->  Hash  (cost=425.00..425.00 rows=20000 width=11) (actual time=6.062..6.063 rows=20000.00 loops=1)
                     Buckets: 32768  Batches: 1  Memory Usage: 1102kB
                     Buffers: shared hit=225
                     ->  Seq Scan on clientes cl  (cost=0.00..425.00 rows=20000 width=11) (actual time=0.046..2.734 rows=20000.00 loops=1)
                           Buffers: shared hit=225
         ->  Index Only Scan using idx_comprobante_cliente on comprobante c  (cost=0.29..0.48 rows=8 width=4) (actual time=0.001..0.001 rows=0.33 loops=1202)
               Index Cond: (id_cliente = cl.id)
               Heap Fetches: 0
               Index Searches: 1202
               Buffers: shared hit=2405
 Planning:
   Buffers: shared hit=54
 Planning Time: 1.198 ms
 Execution Time: 373.043 ms
(43 filas)
```
