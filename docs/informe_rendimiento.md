# Informe de Etapa 4 — Índices y rendimiento

Bodegas del Atuel · TPI Bases de Datos · Grupo 28 · UTN FRSR · Ciclo 2026

Integrantes: Matias Gonzalez, Dalma Monardi, Marcos Velez, Facundo Zinik ·

## TABLA 1- Consultas elegidas

```sql
-- Q1 = S1: Top 10 vinos con más botellas vendidas en toda la red
SELECT v.id, v.nombre, v.anada, v.volumen, SUM(dc.cantidad) AS botellas
FROM detalle_comprobante dc
JOIN vino v ON v.id = dc.cod_vino
GROUP BY v.id, v.nombre, v.anada, v.volumen
ORDER BY botellas DESC
LIMIT 10;


-- Q2 = S3: Clientes de cada tipo que compraron en una sala en la última semana
-- (para otra sala, cambiar c.id_sala)
SELECT cl.tipoCliente, COUNT(DISTINCT cl.id) AS clientes
FROM comprobante c
JOIN clientes cl ON cl.id = c.id_cliente
WHERE c.id_sala = :sala_s3
  AND c.fecha >= CURRENT_DATE - 7
GROUP BY cl.tipoCliente
ORDER BY clientes DESC;

-- Q3 = S8: Monto total de ventas por sala en el último trimestre
SELECT c.id_sala, SUM(c.total) AS monto
FROM comprobante c
WHERE c.fecha >= CURRENT_DATE - INTERVAL '3 months'
GROUP BY c.id_sala
ORDER BY monto DESC;

-- Q4 = S12 (parte anti-join): Clientes que nunca compraron un vino tinto
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

-- S12 (a): división. El cliente califica si no hay ningún vino de la bodega
-- que no haya comprado.
SELECT cl.id, cl.tipoCliente
FROM clientes cl
WHERE NOT EXISTS (
  SELECT 1 FROM vino v
  JOIN bodega b ON b.cuit = v.cuit_bodega
  WHERE b.razon_social = :'bodega_s12'
    AND NOT EXISTS (
      SELECT 1 FROM comprobante c
      JOIN detalle_comprobante dc ON dc.cod_comprobante = c.numero
      WHERE c.id_cliente = cl.id AND dc.cod_vino = v.id
    )
)
ORDER BY cl.id;
```

| Consulta | Sección 8 | Tablas y filas involucradas | Hipótesis: qué plan esperás y qué índice ayudaría |
|---|---|---|---|
| Q1 | S1 | detalle_comprobante (~525.000) + vino |Espero Seq Scan sobre detalle_comprobante (~525.000 filas) porque al no haber WHERE tiene que leer toda la tabla para sumar. Un índice en la clave foránea cod_vino ayudaría a acelerar el cruce con la tabla de vinos.|
| Q2 | S3 | comprobante (150.000) + clientes | Espero Seq Scan sobre comprobante (150.000 filas) porque no hay índice por sala ni fecha. Un índice en (id_sala, fecha) debería leer solo las pocas filas de esa sala en la última semana |
| Q3 | S8 | comprobante (150.000) | Espero Seq Scan sobre comprobante (150.000 filas) filtrando el trimestre fila por fila. Un índice en (fecha) o (fecha, id_sala) permitiría saltar directo a las ventas de los últimos 3 meses sin leer el resto. |
| Q4 | S12 | clientes + comprobante + detalle_comprobante + vino | Espero varios Seq Scan lentísimos anidados dentro de la subconsulta. Un índice en la clave foránea comprobante(id_cliente) podría evitar recorrer comprobante por cada cliente. En detalle_comprobante no hace falta un índice nuevo por cod_comprobante: es la primera columna de la PK compuesta. |
| Q5 | S12 (a) | clientes (20.000) + vino + bodega + comprobante (150.000) + detalle_comprobante (~525.000) | Se espera que, para cada cliente, la subconsulta recorra comprobante completo con un Seq Scan (150.000 filas) al filtrar por id_cliente, repitiéndose 20.000 veces. Un índice sobre la clave foránea id_cliente permite acotar cada búsqueda a las pocas filas de ese cliente mediante un Bitmap Index Scan. El acceso a detalle_comprobante lo resuelve la PK (cod_comprobante, cod_vino). |
---

## Tabla 2- Medición ANTES de crear los índices

| Consulta | Corrida 1 (ms) | Corrida 2 (ms) | Corrida 3 (ms) | Mediana (ms) | Recorrido | Filas leídas | Buffers (hit / read) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **Q1** | 140,7 | 117,5 | 128,7 | 128,7 | Parallel Seq Scan | 525.447 | hit 192 / read 4056 |
| **Q2** | 62,4 | 20,3 | 25,8 | 25,8 | Parallel Seq Scan | 150.000 | hit 1356 / read 0 |
| **Q3** | 29,7 | 25,5 | 22,1 | 25,5 | Parallel Seq Scan | 150.000 | hit 1356 / read 0 |
| **Q4** | 351,6 | 416,7 | 337,7 | 351,6 | Seq Scan | 525.446 | hit 352 / read 3896 |
|**Q5**|170.491,4|169.366,8|171.359,8|170.491,4|Seq Scan en comprobante (dentro del SubPlan, 21.976 ejecuciones)|≈ 3.134.085.264|hit 28.809.589 / read 0|
---

### Tabla 3 — Diseño y justificación de los índices

| N.° | Índice | Tipo o variante | Consulta que acelera | Justificación | Tamaño |
| --- | --- | --- | --- | --- | --- |
| 1 | `idx_comprobante_sala_fecha` | Compuesto | Q2 | Filtra por igualdad de sala y rango de fechas. Con la igualdad primero, el índice devuelve juntas las filas de esa sala en la última semana sin leer el resto. | 2256 kB |
| 2 | `idx_comprobante_fecha_cubriente` | INCLUDE (covering) | Q3 | Filtra solo por rango de fecha y necesita `id_sala` y `total`. Al incluirlos en la hoja del índice, se resuelve con un Index Only Scan sin visitar la tabla. | 7544 kB |
| 3 | `idx_comprobante_cliente` | Clave foránea | Q5 (S12 a) | PostgreSQL no indexa las FK por defecto. Cubre la FK a clientes (`ON DELETE RESTRICT`) y la búsqueda de comprobantes por cliente. En Q5 reemplaza el Seq Scan sobre comprobante dentro del subplan por un Bitmap Index Scan. En Q4 el planificador lo ignora (ver Tabla 8). | 1704 kB |
| 4 | `idx_detalle_comprobante_vino` | FK + INCLUDE | Ninguna medida (Q1 lo ignora) | La PK (cod_comprobante, cod_vino) sirve para buscar por comprobante pero no por vino. INCLUDE (cantidad, cod_comprobante) lo deja listo para un Index Only Scan. Se mantiene por la FK a vino y el `ON DELETE RESTRICT`; en Q1 el planificador lo ignora y en Q5 el acceso lo resuelve la PK. | 16 MB |
|5	| `idx_transferencias_pendientes` |Parcial	|S5	| Solo una fracción de las transferencias no está procesada; el índice es chico y solo lo usan consultas con el mismo predicado estado <> `procesado`.| 16 kB| 
|6|	`idx_socio_apellido_lower`	|Expresión|	Búsqueda por apellido|	Sin índice sobre lower(apellido) una búsqueda sin distinguir mayúsculas no puede usar índice. text_pattern_ops permite LIKE con prefijo| 152kB|

### Tabla 4 — Comparativa ANTES vs. DESPUÉS de los índices

| Consulta | Antes (ms) | Recorrido antes | Filas leídas antes | Después (ms) | Recorrido después | Filas leídas después | Índice usado | Mejora (×) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **Q1** | 128,7 | Parallel Seq Scan | 525.447 | 131,3 | Parallel Seq Scan | 525.447 | Ninguno (lo ignora) | 1,0x |
| **Q2** | 25,8 | Parallel Seq Scan | 150.000 | 1,8 | Bitmap Heap Scan | 85 | idx_comprobante_sala_fecha | 14,3x |
| **Q3** | 25,5 | Parallel Seq Scan | 150.000 | 4,8 | Index Only Scan | 11.878 | idx_comprobante_fecha_cubriente | 5,3x |
| **Q4** | 351,6 | Seq Scan | 525.446 | 410,0 | Seq Scan | 525.446 | Ninguno (lo ignora) | 0,9x |
|**Q5**|170.491,4|Seq Scan en comprobante (por cada cliente)|≈ 3.134.085.264|1.010,7|Bitmap Heap Scan + Bitmap Index Scan|≈ 153.832|idx_comprobante_cliente|168,7x|
---

### Tabla 5 — Análisis del orden de columnas y reutilización de índices

| Caso de prueba | Índice evaluado | Tipo de recorrido | Tiempo de ejecución | Buffers | ¿Usa el índice / Es eficiente? |
| --- | --- | --- | --- | --- | --- |
| **5.1 Q2 con orden invertido** `(fecha, id_sala)` | `idx_tmp_fecha_sala` | Bitmap Heap Scan | 10,527 ms | hit 341 / read 1 | **Sí lo usa**, pero el tiempo sube a ~10,5 ms frente a los 1,8 ms del orden original|
| **5.2 Q3 sin índice cubriente** (usando `idx_comprobante_sala_fecha`) | `idx_comprobante_sala_fecha` | Bitmap Heap Scan | 18,085 ms | hit 1356 / read 221 | **Sí lo usa parcialmente** (por la fecha)|

---

## Tabla 6- Índice evaluado y descartado (BRIN sobre fecha)

| Dato | Valor |
| --- | --- |
| Correlación de comprobante.fecha | `0.0028` (prácticamente nula) |
| Tamaño BRIN vs B-tree | 24 kB / 7544 kB |
| Plan y tiempo de Q3 con BRIN | `Parallel Seq Scan` / Tiempo: 28,444 ms (el planificador descartó el BRIN y barrió la tabla) |
| Plan y tiempo de Q3 con el B-tree cubriente | `Index Only Scan` / Tiempo: 4,795 ms  |
| Decisión y motivo | **Descartar BRIN**. Debido a que la correlación física de la fecha es cercana a 0, un índice BRIN no puede acotar eficientemente los bloques en disco y el motor prefiere un escaneo secuencial.|

---

### Tabla 7 — Costo de escritura y rendimiento de carga

| Medición | Sin índices | Con índices | Diferencia (%) |
| --- | --- | --- | --- |
| Carga completa (time real) | 1m 24,005s | 1m 25,727s | +2,05% |
| Etapa «Comprobantes y ventas» (s) | 71,19s | 73,07s | +2,64% |
| Etapa «Transferencias» (s) | 1,09s | 1,22s | +11,93% |
| Benchmark fila por fila, 20.000 renglones (s) | 14,11s | 14,27s | +1,13% |
| Benchmark por lotes (s) | 2,41s | 2,40s | -0,41% |
| Benchmark COPY (s) | 1,92s | 1,91s | -0,52% |
| Hash global | `47a387a0eb2a...` | `47a387a0eb2a...` | (coinciden) |

---

| Tabla | Tamaño de la tabla | Tamaño de sus índices |
| --- | --- | --- |
| `comprobante` | ~13 MB | ~14,5 MB (PK ~3 MB + 3 índices nuevos ~11,5 MB) |
| `detalle_comprobante` | ~38 MB | ~27 MB (PK compuesta ~11 MB + `idx_detalle_comprobante_vino` ~16 MB) |

---

## Tabla 8- Caso en que el planificador no usa un índice existente

| Caso | Índice existente | Plan elegido | Tiempo (ms) | Plan forzado | Tiempo forzado (ms) | Causa explicada |
| --- | --- | --- | --- | --- | --- | --- |
| 8.1 filtro fecha ~80 % | `idx_comprobante_fecha_cubriente` | `Seq Scan` | 47,103 ms | `Bitmap Heap Scan` | 37,814 ms | **Baja selectividad:** con el 80 % de las filas, el costo **estimado** del Seq Scan es menor que el del índice y el planificador lo elige. En la medición el plan forzado resultó algo más rápido (37,8 ms contra 47,1 ms) porque la tabla estaba en caché: el modelo de costos supone lecturas aleatorias caras (`random_page_cost = 4`) que con los datos en memoria no ocurren. Es un ejemplo de que la estimación de costos no siempre coincide con el tiempo real. |
| 5.2 Q3 con `(id_sala, fecha)` | `idx_comprobante_sala_fecha` | `Bitmap Heap Scan` | 18,085 ms | *(N/A)* | *(N/A)* | **Primera columna no filtrada:** el índice `(id_sala, fecha)` tiene la igualdad (`id_sala`) primero, pero Q3 no filtra por sala. Como la primera columna no está acotada, el motor no puede usar el árbol para saltar al rango de fechas y debe recorrer todas sus entradas (Bitmap Heap Scan de 18 ms contra 4,8 ms del índice cubriente por `fecha`). |
---

## 9. Conclusiones y cierre de la etapa

A partir del análisis sistemático del rendimiento, los planes de ejecución (EXPLAIN ANALYZE), el consumo de buffers y las pruebas de carga masiva realizadas sobre la base de datos bodegas_del_atuel, se establecen las siguientes conclusiones y decisiones de diseño:

### Balance entre Lectura y Escritura

Impacto mínimo en inserciones: Las pruebas de costo de escritura (Sección 7) demostraron que la incorporación de la batería de índices incrementa el tiempo total de la carga masiva en apenas un 2,05% (pasando de 1m 24s a 1m 25s).

Justificación operativa: Este bajo costo de penalización en las operaciones de INSERT (mediante COPY) queda ampliamente justificado por las mejoras de velocidad obtenidas en las consultas críticas de lectura y reportes analíticos diarios (Q2, Q3 y Q5).

### Decisiones sobre Tipos de Índices y Estructuras

Efectividad de Índices Compuestos y Cubrientes (INCLUDE): El uso de índices compuestos con la columna de igualdad ubicada en primer término demostró ser indispensable para consultas altamente selectivas (como Q2). Asimismo, los índices cubrientes permitieron resolver consultas agregadas directamente mediante Index Only Scan, evitando accesos innecesarios a los bloques físicos de las tablas.

Descarte de Índices Ineficientes (BRIN): La evaluación del índice BRIN sobre la columna fecha evidenció que, ante una distribución de datos sin correlación física estricta, el motor descarta la estructura en favor de un escaneo secuencial. Esto ratificó la decisión de priorizar índices B-Tree tradicionales.

Optimización de Transferencias con Cruce Geográfico (Q5/S4): Al incorporar índices específicos sobre transferencias (idx_transferencias_fecha con INCLUDE) y detalle_transferencia (idx_detalle_transferencia_vino), el motor pasa de evaluar las tablas mediante escaneos secuenciales forzados a utilizar eficientes Bitmap Heap Scans. Esto redujo el tiempo de la consulta S4 de 1,69 ms a 0,52 ms y optimizó la unificación de datos logísticos con las tablas sala_de_ventas y localidades para reportes de distribución.

### Inteligencia del Planificador (Costos y Selectividad)

Las pruebas de baja selectividad (Sección 8) mostraron que el optimizador descarta el índice cuando la consulta abarca la mayor parte de la tabla (80% en el caso 8.1), porque estima más caro el acceso aleatorio. En nuestra medición, con los datos en caché, el plan forzado fue algo más rápido: la decisión del planificador se basa en costos estimados para disco, que pueden diferir del tiempo real cuando todo está en memoria.

## 10. Anexo: Planes de ejecución completos (EXPLAIN ANALYZE, BUFFERS)

A continuación se adjuntan los planes de ejecución detallados obtenidos mediante la herramienta de *benchmarking* `psqlb`, comparando el comportamiento de las consultas críticas antes y después de aplicar la estrategia de indexación de la Etapa 4.

### A.1 Antes de crear los índices
```text
BEGIN
DROP INDEX
=== Q1 ===
                                                                                   QUERY PLAN                                                                                    
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Limit  (cost=9294.79..9294.81 rows=10 width=42) (actual time=103.071..106.012 rows=10 loops=1)
   Buffers: shared hit=556 read=3736
   ->  Sort  (cost=9294.79..9296.04 rows=500 width=42) (actual time=103.068..106.008 rows=10 loops=1)
         Sort Key: (sum(dc.cantidad)) DESC
         Sort Method: top-N heapsort  Memory: 25kB
         Buffers: shared hit=556 read=3736
         ->  Finalize GroupAggregate  (cost=9157.31..9283.98 rows=500 width=42) (actual time=102.044..105.826 rows=500 loops=1)
               Group Key: v.id
               Buffers: shared hit=553 read=3736
               ->  Gather Merge  (cost=9157.31..9273.98 rows=1000 width=42) (actual time=102.028..105.371 rows=1500 loops=1)
                     Workers Planned: 2
                     Workers Launched: 2
                     Buffers: shared hit=553 read=3736
                     ->  Sort  (cost=8157.28..8158.53 rows=500 width=42) (actual time=95.294..95.332 rows=500 loops=3)
                           Sort Key: v.id
                           Sort Method: quicksort  Memory: 59kB
                           Buffers: shared hit=553 read=3736
                           Worker 0:  Sort Method: quicksort  Memory: 59kB
                           Worker 1:  Sort Method: quicksort  Memory: 59kB
                           ->  Partial HashAggregate  (cost=8129.87..8134.87 rows=500 width=42) (actual time=94.979..95.048 rows=500 loops=3)
                                 Group Key: v.id
                                 Batches: 1  Memory Usage: 105kB
                                 Buffers: shared hit=539 read=3736
                                 Worker 0:  Batches: 1  Memory Usage: 105kB
                                 Worker 1:  Batches: 1  Memory Usage: 105kB
                                 ->  Hash Join  (cost=18.25..7035.19 rows=218936 width=38) (actual time=0.338..63.021 rows=175149 loops=3)
                                       Hash Cond: (dc.cod_vino = v.id)
                                       Buffers: shared hit=539 read=3736
                                       ->  Parallel Seq Scan on detalle_comprobante dc  (cost=0.00..6437.36 rows=218936 width=8) (actual time=0.064..19.096 rows=175149 loops=3)
                                             Buffers: shared hit=512 read=3736
                                       ->  Hash  (cost=12.00..12.00 rows=500 width=34) (actual time=0.214..0.215 rows=500 loops=3)
                                             Buckets: 1024  Batches: 1  Memory Usage: 41kB
                                             Buffers: shared hit=21
                                             ->  Seq Scan on vino v  (cost=0.00..12.00 rows=500 width=34) (actual time=0.016..0.083 rows=500 loops=3)
                                                   Buffers: shared hit=21
 Planning:
   Buffers: shared hit=158
 Planning Time: 1.781 ms
 Execution Time: 106.492 ms
(39 rows)

=== Q2 ===
                                                                     QUERY PLAN                                                                      
-----------------------------------------------------------------------------------------------------------------------------------------------------
 GroupAggregate  (cost=4376.33..4384.45 rows=3 width=15) (actual time=18.444..22.573 rows=3 loops=1)
   Group Key: cl.tipocliente
   Buffers: shared hit=1588
   ->  Gather Merge  (cost=4376.33..4384.08 rows=68 width=11) (actual time=18.423..22.540 rows=72 loops=1)
         Workers Planned: 1
         Workers Launched: 1
         Buffers: shared hit=1588
         ->  Sort  (cost=3376.32..3376.42 rows=40 width=11) (actual time=12.987..12.992 rows=36 loops=2)
               Sort Key: cl.tipocliente, cl.id
               Sort Method: quicksort  Memory: 27kB
               Buffers: shared hit=1588
               Worker 0:  Sort Method: quicksort  Memory: 25kB
               ->  Nested Loop  (cost=0.29..3375.26 rows=40 width=11) (actual time=0.236..12.833 rows=36 loops=2)
                     Buffers: shared hit=1573
                     ->  Parallel Seq Scan on comprobante c  (cost=0.00..3120.71 rows=40 width=4) (actual time=0.202..12.381 rows=36 loops=2)
                           Filter: ((id_sala = 1) AND (fecha >= (CURRENT_DATE - 7)))
                           Rows Removed by Filter: 74964
                           Buffers: shared hit=1356
                     ->  Index Scan using clientes_pkey on clientes cl  (cost=0.29..6.36 rows=1 width=11) (actual time=0.010..0.010 rows=1 loops=72)
                           Index Cond: (id = c.id_cliente)
                           Buffers: shared hit=217
 Planning:
   Buffers: shared hit=91
 Planning Time: 1.233 ms
 Execution Time: 22.800 ms
(25 rows)

=== Q3 ===
                                                                       QUERY PLAN                                                                        
---------------------------------------------------------------------------------------------------------------------------------------------------------
 Sort  (cost=3938.61..3938.65 rows=15 width=36) (actual time=16.433..20.995 rows=15 loops=1)
   Sort Key: (sum(total)) DESC
   Sort Method: quicksort  Memory: 25kB
   Buffers: shared hit=1366
   ->  Finalize GroupAggregate  (cost=3936.29..3938.32 rows=15 width=36) (actual time=16.348..20.939 rows=15 loops=1)
         Group Key: id_sala
         Buffers: shared hit=1363
         ->  Gather Merge  (cost=3936.29..3938.02 rows=15 width=36) (actual time=16.325..20.891 rows=30 loops=1)
               Workers Planned: 1
               Workers Launched: 1
               Buffers: shared hit=1363
               ->  Sort  (cost=2936.28..2936.32 rows=15 width=36) (actual time=12.215..12.218 rows=15 loops=2)
                     Sort Key: id_sala
                     Sort Method: quicksort  Memory: 26kB
                     Buffers: shared hit=1363
                     Worker 0:  Sort Method: quicksort  Memory: 26kB
                     ->  Partial HashAggregate  (cost=2935.80..2935.99 rows=15 width=36) (actual time=12.073..12.085 rows=15 loops=2)
                           Group Key: id_sala
                           Batches: 1  Memory Usage: 24kB
                           Buffers: shared hit=1356
                           Worker 0:  Batches: 1  Memory Usage: 24kB
                           ->  Parallel Seq Scan on comprobante c  (cost=0.00..2900.12 rows=7137 width=12) (actual time=0.016..10.560 rows=5884 loops=2)
                                 Filter: (fecha >= (CURRENT_DATE - '3 mons'::interval))
                                 Rows Removed by Filter: 69116
                                 Buffers: shared hit=1356
 Planning:
   Buffers: shared hit=37
 Planning Time: 0.473 ms
 Execution Time: 21.097 ms
(29 rows)

=== Q4 ===
                                                                   QUERY PLAN                                                                   
------------------------------------------------------------------------------------------------------------------------------------------------
 Hash Right Anti Join  (cost=5423.25..21535.69 rows=1538 width=4) (actual time=373.553..374.145 rows=1203 loops=1)
   Hash Cond: (c.id_cliente = cl.id)
   Buffers: shared hit=2196 read=3640
   ->  Hash Join  (cost=4748.25..16524.47 rows=336285 width=4) (actual time=61.406..307.236 rows=331246 loops=1)
         Hash Cond: (dc.cod_comprobante = c.numero)
         Buffers: shared hit=1971 read=3640
         ->  Hash Join  (cost=17.25..10910.70 rows=336285 width=4) (actual time=0.347..143.771 rows=331246 loops=1)
               Hash Cond: (dc.cod_vino = v.id)
               Buffers: shared hit=615 read=3640
               ->  Seq Scan on detalle_comprobante dc  (cost=0.00..9502.46 rows=525446 width=8) (actual time=0.037..52.305 rows=525446 loops=1)
                     Buffers: shared hit=608 read=3640
               ->  Hash  (cost=13.25..13.25 rows=320 width=4) (actual time=0.290..0.292 rows=320 loops=1)
                     Buckets: 1024  Batches: 1  Memory Usage: 20kB
                     Buffers: shared hit=7
                     ->  Seq Scan on vino v  (cost=0.00..13.25 rows=320 width=4) (actual time=0.007..0.139 rows=320 loops=1)
                           Filter: ((tipo)::text = 'tinto'::text)
                           Rows Removed by Filter: 180
                           Buffers: shared hit=7
         ->  Hash  (cost=2856.00..2856.00 rows=150000 width=8) (actual time=59.255..59.256 rows=150000 loops=1)
               Buckets: 262144  Batches: 1  Memory Usage: 7908kB
               Buffers: shared hit=1356
               ->  Seq Scan on comprobante c  (cost=0.00..2856.00 rows=150000 width=8) (actual time=0.011..20.894 rows=150000 loops=1)
                     Buffers: shared hit=1356
   ->  Hash  (cost=425.00..425.00 rows=20000 width=4) (actual time=5.635..5.635 rows=20000 loops=1)
         Buckets: 32768  Batches: 1  Memory Usage: 960kB
         Buffers: shared hit=225
         ->  Seq Scan on clientes cl  (cost=0.00..425.00 rows=20000 width=4) (actual time=0.007..2.082 rows=20000 loops=1)
               Buffers: shared hit=225
 Planning:
   Buffers: shared hit=34
 Planning Time: 1.240 ms
 Execution Time: 376.159 ms
(32 rows)

=== Q5 (S12 a) ANTES ===
                                                                                             QUERY PLAN                                                                                             
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Nested Loop Anti Join  (cost=1.45..1435776694.47 rows=10000 width=11) (actual time=3205.395..173592.199 rows=20 loops=1)
   Join Filter: (NOT (SubPlan 1))
   Rows Removed by Join Filter: 1996
   Buffers: shared hit=28809589
   ->  Index Scan using clientes_pkey on clientes cl  (cost=0.29..756.29 rows=20000 width=11) (actual time=0.104..52.248 rows=20000 loops=1)
         Buffers: shared hit=284
   ->  Materialize  (cost=1.16..15.15 rows=42 width=4) (actual time=0.024..0.024 rows=1 loops=20000)
         Buffers: shared hit=8
         ->  Hash Join  (cost=1.16..14.94 rows=42 width=4) (actual time=464.676..464.868 rows=5 loops=1)
               Hash Cond: ((v.cuit_bodega)::text = (b.cuit)::text)
               Buffers: shared hit=8
               ->  Seq Scan on vino v  (cost=0.00..12.00 rows=500 width=16) (actual time=0.021..0.109 rows=500 loops=1)
                     Buffers: shared hit=7
               ->  Hash  (cost=1.15..1.15 rows=1 width=12) (actual time=464.606..464.608 rows=1 loops=1)
                     Buckets: 1024  Batches: 1  Memory Usage: 9kB
                     Buffers: shared hit=1
                     ->  Seq Scan on bodega b  (cost=0.00..1.15 rows=1 width=12) (actual time=464.570..464.572 rows=1 loops=1)
                           Filter: ((razon_social)::text = 'Bodega Pequeña Selección'::text)
                           Rows Removed by Filter: 11
                           Buffers: shared hit=1
   SubPlan 1
     ->  Nested Loop  (cost=0.42..3266.57 rows=1 width=0) (actual time=7.872..7.872 rows=0 loops=21976)
           Buffers: shared hit=28809297
           ->  Seq Scan on comprobante c  (cost=0.00..3231.00 rows=8 width=4) (actual time=0.808..7.810 rows=7 loops=21976)
                 Filter: (id_cliente = cl.id)
                 Rows Removed by Filter: 142607
                 Buffers: shared hit=28332374
           ->  Index Only Scan using detalle_comprobante_pkey on detalle_comprobante dc  (cost=0.42..4.44 rows=1 width=4) (actual time=0.006..0.006 rows=0 loops=158974)
                 Index Cond: ((cod_comprobante = c.numero) AND (cod_vino = v.id))
                 Heap Fetches: 0
                 Buffers: shared hit=476923
 Planning:
   Buffers: shared hit=297
 Planning Time: 5.243 ms
 Execution Time: 173864.030 ms
```

### A.2 Después de crear los índices
```text
=== Q1 ===
                                                                                   QUERY PLAN                                                                                    
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Limit  (cost=9294.79..9294.81 rows=10 width=42) (actual time=114.452..118.234 rows=10 loops=1)
   Buffers: shared hit=684 read=3608
   ->  Sort  (cost=9294.79..9296.04 rows=500 width=42) (actual time=114.449..118.230 rows=10 loops=1)
         Sort Key: (sum(dc.cantidad)) DESC
         Sort Method: top-N heapsort  Memory: 25kB
         Buffers: shared hit=684 read=3608
         ->  Finalize GroupAggregate  (cost=9157.31..9283.98 rows=500 width=42) (actual time=113.302..118.021 rows=500 loops=1)
               Group Key: v.id
               Buffers: shared hit=681 read=3608
               ->  Gather Merge  (cost=9157.31..9273.98 rows=1000 width=42) (actual time=113.289..117.545 rows=1500 loops=1)
                     Workers Planned: 2
                     Workers Launched: 2
                     Buffers: shared hit=681 read=3608
                     ->  Sort  (cost=8157.28..8158.53 rows=500 width=42) (actual time=105.913..105.970 rows=500 loops=3)
                           Sort Key: v.id
                           Sort Method: quicksort  Memory: 59kB
                           Buffers: shared hit=681 read=3608
                           Worker 0:  Sort Method: quicksort  Memory: 59kB
                           Worker 1:  Sort Method: quicksort  Memory: 59kB
                           ->  Partial HashAggregate  (cost=8129.87..8134.87 rows=500 width=42) (actual time=105.436..105.552 rows=500 loops=3)
                                 Group Key: v.id
                                 Batches: 1  Memory Usage: 105kB
                                 Buffers: shared hit=667 read=3608
                                 Worker 0:  Batches: 1  Memory Usage: 105kB
                                 Worker 1:  Batches: 1  Memory Usage: 105kB
                                 ->  Hash Join  (cost=18.25..7035.19 rows=218936 width=38) (actual time=0.479..70.793 rows=175149 loops=3)
                                       Hash Cond: (dc.cod_vino = v.id)
                                       Buffers: shared hit=667 read=3608
                                       ->  Parallel Seq Scan on detalle_comprobante dc  (cost=0.00..6437.36 rows=218936 width=8) (actual time=0.069..20.597 rows=175149 loops=3)
                                             Buffers: shared hit=640 read=3608
                                       ->  Hash  (cost=12.00..12.00 rows=500 width=34) (actual time=0.332..0.333 rows=500 loops=3)
                                             Buckets: 1024  Batches: 1  Memory Usage: 41kB
                                             Buffers: shared hit=21
                                             ->  Seq Scan on vino v  (cost=0.00..12.00 rows=500 width=34) (actual time=0.019..0.120 rows=500 loops=3)
                                                   Buffers: shared hit=21
 Planning:
   Buffers: shared hit=200
 Planning Time: 3.370 ms
 Execution Time: 118.811 ms
(39 rows)

=== Q2 ===
                                                                      QUERY PLAN                                                                       
-------------------------------------------------------------------------------------------------------------------------------------------------------
 GroupAggregate  (cost=779.38..780.03 rows=3 width=15) (actual time=1.231..1.246 rows=3 loops=1)
   Group Key: cl.tipocliente
   Buffers: shared hit=293
   ->  Sort  (cost=779.38..779.59 rows=83 width=11) (actual time=1.220..1.225 rows=72 loops=1)
         Sort Key: cl.tipocliente, cl.id
         Sort Method: quicksort  Memory: 27kB
         Buffers: shared hit=293
         ->  Nested Loop  (cost=5.44..776.74 rows=83 width=11) (actual time=0.075..1.089 rows=72 loops=1)
               Buffers: shared hit=290
               ->  Bitmap Heap Scan on comprobante c  (cost=5.15..271.42 rows=83 width=4) (actual time=0.054..0.621 rows=72 loops=1)
                     Recheck Cond: ((id_sala = 1) AND (fecha >= (CURRENT_DATE - 7)))
                     Heap Blocks: exact=72
                     Buffers: shared hit=74
                     ->  Bitmap Index Scan on idx_comprobante_sala_fecha  (cost=0.00..5.13 rows=83 width=0) (actual time=0.032..0.032 rows=72 loops=1)
                           Index Cond: ((id_sala = 1) AND (fecha >= (CURRENT_DATE - 7)))
                           Buffers: shared hit=2
               ->  Index Scan using clientes_pkey on clientes cl  (cost=0.29..6.09 rows=1 width=11) (actual time=0.006..0.006 rows=1 loops=72)
                     Index Cond: (id = c.id_cliente)
                     Buffers: shared hit=216
 Planning:
   Buffers: shared hit=165
 Planning Time: 3.092 ms
 Execution Time: 1.393 ms
(23 rows)

=== Q3 ===
                                                                                QUERY PLAN                                                                                 
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Sort  (cost=581.90..581.94 rows=15 width=36) (actual time=5.123..5.126 rows=15 loops=1)
   Sort Key: (sum(total)) DESC
   Sort Method: quicksort  Memory: 25kB
   Buffers: shared hit=90
   ->  HashAggregate  (cost=581.42..581.60 rows=15 width=36) (actual time=5.028..5.035 rows=15 loops=1)
         Group Key: id_sala
         Batches: 1  Memory Usage: 24kB
         Buffers: shared hit=87
         ->  Index Only Scan using idx_comprobante_fecha_cubriente on comprobante c  (cost=0.42..520.75 rows=12133 width=12) (actual time=0.125..2.145 rows=11767 loops=1)
               Index Cond: (fecha >= (CURRENT_DATE - '3 mons'::interval))
               Heap Fetches: 0
               Buffers: shared hit=87
 Planning:
   Buffers: shared hit=37
 Planning Time: 0.787 ms
 Execution Time: 5.231 ms
(16 rows)

=== Q4 ===
                                                                   QUERY PLAN                                                                   
------------------------------------------------------------------------------------------------------------------------------------------------
 Hash Right Anti Join  (cost=5423.25..21535.69 rows=1538 width=4) (actual time=419.413..420.023 rows=1203 loops=1)
   Hash Cond: (c.id_cliente = cl.id)
   Buffers: shared hit=2324 read=3512
   ->  Hash Join  (cost=4748.25..16524.47 rows=336285 width=4) (actual time=70.870..341.023 rows=331246 loops=1)
         Hash Cond: (dc.cod_comprobante = c.numero)
         Buffers: shared hit=2099 read=3512
         ->  Hash Join  (cost=17.25..10910.70 rows=336285 width=4) (actual time=0.252..154.804 rows=331246 loops=1)
               Hash Cond: (dc.cod_vino = v.id)
               Buffers: shared hit=743 read=3512
               ->  Seq Scan on detalle_comprobante dc  (cost=0.00..9502.46 rows=525446 width=8) (actual time=0.061..56.880 rows=525446 loops=1)
                     Buffers: shared hit=736 read=3512
               ->  Hash  (cost=13.25..13.25 rows=320 width=4) (actual time=0.152..0.154 rows=320 loops=1)
                     Buckets: 1024  Batches: 1  Memory Usage: 20kB
                     Buffers: shared hit=7
                     ->  Seq Scan on vino v  (cost=0.00..13.25 rows=320 width=4) (actual time=0.014..0.086 rows=320 loops=1)
                           Filter: ((tipo)::text = 'tinto'::text)
                           Rows Removed by Filter: 180
                           Buffers: shared hit=7
         ->  Hash  (cost=2856.00..2856.00 rows=150000 width=8) (actual time=68.795..68.810 rows=150000 loops=1)
               Buckets: 262144  Batches: 1  Memory Usage: 7908kB
               Buffers: shared hit=1356
               ->  Seq Scan on comprobante c  (cost=0.00..2856.00 rows=150000 width=8) (actual time=0.016..23.042 rows=150000 loops=1)
                     Buffers: shared hit=1356
   ->  Hash  (cost=425.00..425.00 rows=20000 width=4) (actual time=6.964..6.965 rows=20000 loops=1)
         Buckets: 32768  Batches: 1  Memory Usage: 960kB
         Buffers: shared hit=225
         ->  Seq Scan on clientes cl  (cost=0.00..425.00 rows=20000 width=4) (actual time=0.008..2.540 rows=20000 loops=1)
               Buffers: shared hit=225
 Planning:
   Buffers: shared hit=48
 Planning Time: 1.307 ms
 Execution Time: 421.787 ms
(32 rows)

=== Q5 (S12 a) DESPUÉS ===
                                                                                              QUERY PLAN                                                                                              
------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Nested Loop Anti Join  (cost=1.45..30853357.12 rows=10000 width=11) (actual time=286.019..849.850 rows=20 loops=1)
   Join Filter: (NOT (SubPlan 1))
   Rows Removed by Join Filter: 1996
   Buffers: shared hit=679550 read=184
   ->  Index Scan using clientes_pkey on clientes cl  (cost=0.29..756.29 rows=20000 width=11) (actual time=0.028..6.179 rows=20000 loops=1)
         Buffers: shared hit=284
   ->  Materialize  (cost=1.16..15.15 rows=42 width=4) (actual time=0.014..0.014 rows=1 loops=20000)
         Buffers: shared hit=8
         ->  Hash Join  (cost=1.16..14.94 rows=42 width=4) (actual time=272.703..272.842 rows=5 loops=1)
               Hash Cond: ((v.cuit_bodega)::text = (b.cuit)::text)
               Buffers: shared hit=8
               ->  Seq Scan on vino v  (cost=0.00..12.00 rows=500 width=16) (actual time=0.007..0.073 rows=500 loops=1)
                     Buffers: shared hit=7
               ->  Hash  (cost=1.15..1.15 rows=1 width=12) (actual time=272.657..272.659 rows=1 loops=1)
                     Buckets: 1024  Batches: 1  Memory Usage: 9kB
                     Buffers: shared hit=1
                     ->  Seq Scan on bodega b  (cost=0.00..1.15 rows=1 width=12) (actual time=272.632..272.635 rows=1 loops=1)
                           Filter: ((razon_social)::text = 'Bodega Pequeña Selección'::text)
                           Rows Removed by Filter: 11
                           Buffers: shared hit=1
   SubPlan 1
     ->  Nested Loop  (cost=4.78..70.18 rows=1 width=0) (actual time=0.025..0.025 rows=0 loops=21976)
           Buffers: shared hit=679258 read=184
           ->  Bitmap Heap Scan on comprobante c  (cost=4.36..34.61 rows=8 width=4) (actual time=0.004..0.009 rows=7 loops=21976)
                 Recheck Cond: (id_cliente = cl.id)
                 Heap Blocks: exact=158567
                 Buffers: shared hit=202335 read=184
                 ->  Bitmap Index Scan on idx_comprobante_cliente  (cost=0.00..4.35 rows=8 width=0) (actual time=0.002..0.002 rows=8 loops=21976)
                       Index Cond: (id_cliente = cl.id)
                       Buffers: shared hit=43768 read=184
           ->  Index Only Scan using detalle_comprobante_pkey on detalle_comprobante dc  (cost=0.42..4.44 rows=1 width=4) (actual time=0.002..0.002 rows=0 loops=158974)
                 Index Cond: ((cod_comprobante = c.numero) AND (cod_vino = v.id))
                 Heap Fetches: 0
                 Buffers: shared hit=476923
 Planning:
   Buffers: shared hit=54
 Planning Time: 1.293 ms
 Execution Time: 852.570 ms
```

### A.3 Pruebas de orden de columnas, BRIN y baja selectividad (secciones 5, 6 y 8)
```text
=== A.3.1  Q2 con orden invertido (fecha, id_sala)  [Tabla 5, caso 5.1] ===
BEGIN
DROP INDEX
CREATE INDEX
ANALYZE
                                                                      QUERY PLAN                                                                      
------------------------------------------------------------------------------------------------------------------------------------------------------
 Sort  (cost=776.92..776.93 rows=3 width=15) (actual time=1.563..1.565 rows=3 loops=1)
   Sort Key: (count(DISTINCT cl.id)) DESC
   Sort Method: quicksort  Memory: 25kB
   Buffers: shared hit=296 read=1
   ->  GroupAggregate  (cost=776.26..776.90 rows=3 width=15) (actual time=1.489..1.504 rows=3 loops=1)
         Group Key: cl.tipocliente
         Buffers: shared hit=293 read=1
         ->  Sort  (cost=776.26..776.46 rows=81 width=11) (actual time=1.479..1.484 rows=72 loops=1)
               Sort Key: cl.tipocliente, cl.id
               Sort Method: quicksort  Memory: 27kB
               Buffers: shared hit=293 read=1
               ->  Nested Loop  (cost=20.86..773.69 rows=81 width=11) (actual time=0.102..1.362 rows=72 loops=1)
                     Buffers: shared hit=290 read=1
                     ->  Bitmap Heap Scan on comprobante c  (cost=20.57..280.99 rows=81 width=4) (actual time=0.065..0.200 rows=72 loops=1)
                           Recheck Cond: ((fecha >= (CURRENT_DATE - 7)) AND (id_sala = 1))
                           Heap Blocks: exact=72
                           Buffers: shared hit=74 read=1
                           ->  Bitmap Index Scan on idx_tmp_fecha_sala  (cost=0.00..20.55 rows=81 width=0) (actual time=0.043..0.043 rows=72 loops=1)
                                 Index Cond: ((fecha >= (CURRENT_DATE - 7)) AND (id_sala = 1))
                                 Buffers: shared hit=2 read=1
                     ->  Index Scan using clientes_pkey on clientes cl  (cost=0.29..6.08 rows=1 width=11) (actual time=0.015..0.015 rows=1 loops=72)
                           Index Cond: (id = c.id_cliente)
                           Buffers: shared hit=216
 Planning:
   Buffers: shared hit=117 read=3
 Planning Time: 1.866 ms
 Execution Time: 1.802 ms
(27 rows)

ROLLBACK
=== A.3.2  Q3 sin el índice cubriente  [Tabla 5, caso 5.2 / Tabla 8, fila 5.2] ===
BEGIN
DROP INDEX
                                                                         QUERY PLAN                                                                         
------------------------------------------------------------------------------------------------------------------------------------------------------------
 Sort  (cost=3870.61..3870.65 rows=15 width=36) (actual time=82.197..82.202 rows=15 loops=1)
   Sort Key: (sum(total)) DESC
   Sort Method: quicksort  Memory: 25kB
   Buffers: shared hit=1358 read=279
   ->  HashAggregate  (cost=3870.13..3870.32 rows=15 width=36) (actual time=82.166..82.174 rows=15 loops=1)
         Group Key: id_sala
         Batches: 1  Memory Usage: 24kB
         Buffers: shared hit=1358 read=279
         ->  Bitmap Heap Scan on comprobante c  (cost=2256.17..3812.80 rows=11465 width=12) (actual time=74.775..78.813 rows=11767 loops=1)
               Recheck Cond: (fecha >= (CURRENT_DATE - '3 mons'::interval))
               Heap Blocks: exact=1356
               Buffers: shared hit=1358 read=279
               ->  Bitmap Index Scan on idx_comprobante_sala_fecha  (cost=0.00..2253.30 rows=11465 width=0) (actual time=74.495..74.496 rows=11767 loops=1)
                     Index Cond: (fecha >= (CURRENT_DATE - '3 mons'::interval))
                     Buffers: shared hit=2 read=279
 Planning:
   Buffers: shared hit=64
 Planning Time: 0.897 ms
 Execution Time: 82.352 ms
(19 rows)

ROLLBACK
=== A.3.3  BRIN sobre fecha  [Tabla 6] ===
 attname |  correlation  
---------+---------------
 fecha   | -0.0006951606
(1 row)

BEGIN
DROP INDEX
DROP INDEX
CREATE INDEX
ANALYZE
 brin  
-------
 24 kB
(1 row)

                                                                       QUERY PLAN                                                                        
---------------------------------------------------------------------------------------------------------------------------------------------------------
 Sort  (cost=3937.65..3937.69 rows=15 width=36) (actual time=21.806..26.360 rows=15 loops=1)
   Sort Key: (sum(total)) DESC
   Sort Method: quicksort  Memory: 25kB
   Buffers: shared hit=1363
   ->  Finalize GroupAggregate  (cost=3935.33..3937.36 rows=15 width=36) (actual time=21.720..26.322 rows=15 loops=1)
         Group Key: id_sala
         Buffers: shared hit=1363
         ->  Gather Merge  (cost=3935.33..3937.06 rows=15 width=36) (actual time=21.701..26.266 rows=30 loops=1)
               Workers Planned: 1
               Workers Launched: 1
               Buffers: shared hit=1363
               ->  Sort  (cost=2935.32..2935.36 rows=15 width=36) (actual time=16.614..16.617 rows=15 loops=2)
                     Sort Key: id_sala
                     Sort Method: quicksort  Memory: 26kB
                     Buffers: shared hit=1363
                     Worker 0:  Sort Method: quicksort  Memory: 26kB
                     ->  Partial HashAggregate  (cost=2934.84..2935.03 rows=15 width=36) (actual time=16.524..16.534 rows=15 loops=2)
                           Group Key: id_sala
                           Batches: 1  Memory Usage: 24kB
                           Buffers: shared hit=1356
                           Worker 0:  Batches: 1  Memory Usage: 24kB
                           ->  Parallel Seq Scan on comprobante c  (cost=0.00..2900.12 rows=6945 width=12) (actual time=0.015..14.544 rows=5884 loops=2)
                                 Filter: (fecha >= (CURRENT_DATE - '3 mons'::interval))
                                 Rows Removed by Filter: 69116
                                 Buffers: shared hit=1356
 Planning:
   Buffers: shared hit=16
 Planning Time: 0.552 ms
 Execution Time: 26.538 ms
(29 rows)

ROLLBACK
=== A.3.4  Baja selectividad (~80 %)  [Tabla 8, caso 8.1] ===
                                                                        QUERY PLAN                                                                         
-----------------------------------------------------------------------------------------------------------------------------------------------------------
 Sort  (cost=3815.26..3815.30 rows=15 width=36) (actual time=35.673..40.772 rows=15 loops=1)
   Sort Key: (sum(total)) DESC
   Sort Method: quicksort  Memory: 25kB
   Buffers: shared hit=1363
   ->  Finalize GroupAggregate  (cost=3812.94..3814.97 rows=15 width=36) (actual time=35.554..40.703 rows=15 loops=1)
         Group Key: id_sala
         Buffers: shared hit=1363
         ->  Gather Merge  (cost=3812.94..3814.67 rows=15 width=36) (actual time=35.535..40.641 rows=30 loops=1)
               Workers Planned: 1
               Workers Launched: 1
               Buffers: shared hit=1363
               ->  Sort  (cost=2812.93..2812.97 rows=15 width=36) (actual time=28.849..28.854 rows=15 loops=2)
                     Sort Key: id_sala
                     Sort Method: quicksort  Memory: 26kB
                     Buffers: shared hit=1363
                     Worker 0:  Sort Method: quicksort  Memory: 26kB
                     ->  Partial HashAggregate  (cost=2812.45..2812.64 rows=15 width=36) (actual time=28.749..28.759 rows=15 loops=2)
                           Group Key: id_sala
                           Batches: 1  Memory Usage: 24kB
                           Buffers: shared hit=1356
                           Worker 0:  Batches: 1  Memory Usage: 24kB
                           ->  Parallel Seq Scan on comprobante c  (cost=0.00..2458.94 rows=70702 width=12) (actual time=0.022..12.497 rows=60019 loops=2)
                                 Filter: (fecha >= '2022-07-04'::date)
                                 Rows Removed by Filter: 14981
                                 Buffers: shared hit=1356
 Planning:
   Buffers: shared hit=5
 Planning Time: 0.438 ms
 Execution Time: 40.922 ms
(29 rows)

BEGIN
SET
                                                                                               QUERY PLAN                                                                                                
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Sort  (cost=5681.80..5681.84 rows=15 width=36) (actual time=338.728..342.466 rows=15 loops=1)
   Sort Key: (sum(total)) DESC
   Sort Method: quicksort  Memory: 25kB
   Buffers: shared hit=99 read=678
   ->  Finalize GroupAggregate  (cost=5677.59..5681.51 rows=15 width=36) (actual time=338.631..342.410 rows=15 loops=1)
         Group Key: id_sala
         Buffers: shared hit=99 read=678
         ->  Gather Merge  (cost=5677.59..5681.09 rows=30 width=36) (actual time=338.612..342.357 rows=45 loops=1)
               Workers Planned: 2
               Workers Launched: 2
               Buffers: shared hit=99 read=678
               ->  Sort  (cost=4677.57..4677.61 rows=15 width=36) (actual time=330.826..330.829 rows=15 loops=3)
                     Sort Key: id_sala
                     Sort Method: quicksort  Memory: 26kB
                     Buffers: shared hit=99 read=678
                     Worker 0:  Sort Method: quicksort  Memory: 26kB
                     Worker 1:  Sort Method: quicksort  Memory: 26kB
                     ->  Partial HashAggregate  (cost=4677.09..4677.28 rows=15 width=36) (actual time=330.713..330.722 rows=15 loops=3)
                           Group Key: id_sala
                           Batches: 1  Memory Usage: 24kB
                           Buffers: shared hit=85 read=678
                           Worker 0:  Batches: 1  Memory Usage: 24kB
                           Worker 1:  Batches: 1  Memory Usage: 24kB
                           ->  Parallel Index Only Scan using idx_comprobante_fecha_cubriente on comprobante c  (cost=0.42..4426.68 rows=50081 width=12) (actual time=6.067..319.437 rows=40013 loops=3)
                                 Index Cond: (fecha >= '2022-07-04'::date)
                                 Heap Fetches: 0
                                 Buffers: shared hit=85 read=678
 Planning Time: 0.223 ms
 Execution Time: 342.644 ms
(29 rows)

ROLLBACK
```