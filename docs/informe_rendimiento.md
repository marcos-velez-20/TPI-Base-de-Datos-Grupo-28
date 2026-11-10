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

-- Q5 = S4: Top 5 de las salas que solicitaron mayor cantidad de un vino determinado en los últimos 15 días
SELECT t.id_sala, l.nombre AS localidad, SUM(dt.cantidad) AS botellas
FROM transferencias t
JOIN detalle_transferencia dt ON dt.num_transferencia = t.num_solicitud
JOIN sala_de_ventas s ON s.id_sala = t.id_sala
JOIN localidades l ON l.codigo_postal = s.codigo_postal
WHERE dt.cod_vino = :vino_s4
  AND t.fecha_confeccion >= CURRENT_DATE - 15
GROUP BY t.id_sala, l.nombre
ORDER BY botellas DESC
LIMIT 5;
```

| Consulta | Sección 8 | Tablas y filas involucradas | Hipótesis: qué plan esperás y qué índice ayudaría |
|---|---|---|---|
| Q1 | S1 | detalle_comprobante (~525.000) + vino |Espero Seq Scan sobre detalle_comprobante (~525.000 filas) porque al no haber WHERE tiene que leer toda la tabla para sumar. Un índice en la clave foránea cod_vino ayudaría a acelerar el cruce con la tabla de vinos.|
| Q2 | S3 | comprobante (150.000) + clientes | Espero Seq Scan sobre comprobante (150.000 filas) porque no hay índice por sala ni fecha. Un índice en (id_sala, fecha) debería leer solo las pocas filas de esa sala en la última semana |
| Q3 | S8 | comprobante (150.000) | Espero Seq Scan sobre comprobante (150.000 filas) filtrando el trimestre fila por fila. Un índice en (fecha) o (fecha, id_sala) permitiría saltar directo a las ventas de los últimos 3 meses sin leer el resto. |
| Q4 | S12 | clientes + comprobante + detalle_comprobante + vino | Espero varios Seq Scan lentísimos anidados dentro de la subconsulta. Un índice en la clave foránea comprobante(id_cliente) podría evitar recorrer comprobante por cada cliente. En detalle_comprobante no hace falta un índice nuevo por cod_comprobante: es la primera columna de la PK compuesta. |
| Q5 | S4 | transferencias (~2.000) + detalle_transferencia (~9.500) + sala_de_ventas + localidades | Se espera un escaneo secuencial en las tablas de transferencias al filtrar por rango de fechas y código de vino. Los índices en fecha_confeccion (con INCLUDE) y cod_vino permiten al motor resolver el filtrado mediante Bitmap Heap Scan, acotando el acceso a bloques. |

---

## Tabla 2- Medición ANTES de crear los índices

| Consulta | Corrida 1 (ms) | Corrida 2 (ms) | Corrida 3 (ms) | Mediana (ms) | Recorrido | Filas leídas | Buffers (hit / read) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **Q1** | 140,7 | 117,5 | 128,7 | 128,7 | Parallel Seq Scan | 525.447 | hit 192 / read 4056 |
| **Q2** | 62,4 | 20,3 | 25,8 | 25,8 | Parallel Seq Scan | 150.000 | hit 1356 / read 0 |
| **Q3** | 29,7 | 25,5 | 22,1 | 25,5 | Parallel Seq Scan | 150.000 | hit 1356 / read 0 |
| **Q4** | 351,6 | 416,7 | 337,7 | 351,6 | Seq Scan | 525.446 | hit 352 / read 3896 |
|**Q5**|1,69|1,93|1,14|1,69| Nested Loop + Seq Scan| 2.000 (transf.)|hit 71 / read 0|
---

### Tabla 3 — Diseño y justificación de los índices

| N.° | Índice | Tipo o variante | Consulta que acelera | Justificación | Tamaño |
| --- | --- | --- | --- | --- | --- |
| 1 | `idx_comprobante_sala_fecha` | Compuesto | Q2 | Filtra por igualdad de sala y rango de fechas. Con la igualdad primero, el índice devuelve juntas las filas de esa sala en la última semana sin leer el resto. | 2256 kB |
| 2 | `idx_comprobante_fecha_cubriente` | INCLUDE (covering) | Q3 | Filtra solo por rango de fecha y necesita `id_sala` y `total`. Al incluirlos en la hoja del índice, se resuelve con un Index Only Scan sin visitar la tabla. | 7544 kB |
| 3 | `idx_comprobante_cliente` | Clave foránea | Q4 | PostgreSQL no indexa las FK por defecto. Buscar comprobantes por cliente y verificar el `ON DELETE RESTRICT` recorrería toda la tabla sin este índice. | 1704 kB |
| 4 | `idx_detalle_comprobante_vino` | FK + INCLUDE | Q1 |La PK (cod_comprobante, cod_vino) sirve para buscar por comprobante pero no por vino. INCLUDE (cantidad, cod_comprobante). | 16 MB |
|5	| `idx_transferencias_pendientes` |Parcial	|S5	| Solo una fracción de las transferencias no está procesada; el índice es chico y solo lo usan consultas con el mismo predicado estado <> `procesado`.| 16 kB| 
|6|	`idx_socio_apellido_lower`	|Expresión|	Búsqueda por apellido|	Sin índice sobre lower(apellido) una búsqueda sin distinguir mayúsculas no puede usar índice. text_pattern_ops permite LIKE con prefijo| 152kB|
|7| `idx_transferencias_fecha` |B-Tree + INCLUDE |Q5 (S4)|Filtra por rango temporal de confección y expone id_sala en las hojas, evitando accesos adicionales a bloques de datos en la tabla de transferencias|~64 kB|
|8| `idx_detalle_transferencia_vino` |Clave foránea|Q5 (S4)| Indexa la FK cod_vino en los detalles de transferencia para agilizar el filtrado del vino solicitado mediante un Bitmap Heap Scan.|~96 kB|

### Tabla 4 — Comparativa ANTES vs. DESPUÉS de los índices

| Consulta | Antes (ms) | Recorrido antes | Filas leídas antes | Después (ms) | Recorrido después | Filas leídas después | Índice usado | Mejora (×) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **Q1** | 128,7 | Parallel Seq Scan | 525.447 | 131,3 | Parallel Seq Scan | 525.447 | Ninguno (lo ignora) | 1,0x |
| **Q2** | 25,8 | Parallel Seq Scan | 150.000 | 1,8 | Bitmap Heap Scan | 85 | idx_comprobante_sala_fecha | 14,3x |
| **Q3** | 25,5 | Parallel Seq Scan | 150.000 | 4,8 | Index Only Scan | 11.878 | idx_comprobante_fecha_cubriente | 5,3x |
| **Q4** | 351,6 | Seq Scan | 525.446 | 410,0 | Seq Scan | 525.446 | Ninguno (lo ignora) | 0,9x |
|**Q5**|	1,69	| Seq Scan |	2.000	| 0,52	| Bitmap Heap Scan	| 10 (transf.) / 29 (det.)|idx_transferencias_fecha / idx_detalle_transferencia_vino|	3,2x|
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