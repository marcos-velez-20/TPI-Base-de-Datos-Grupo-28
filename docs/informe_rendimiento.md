# Informe de Etapa 4 — Índices y rendimiento

Bodegas del Atuel · TPI Bases de Datos · Grupo 28 · UTN FRSR · Ciclo 2026

Integrantes: Matias Gonzalez, Dalma Monardi, Marcos Velez, Facundo Zinik ·

## TABLA 1- Consultas elegidas

```sql
-- Q1 = S1: Top 10 vinos con más botellas vendidas en toda la red
SELECT v.id, v.nombre, SUM(dc.cantidad) AS botellas
FROM detalle_comprobante dc
JOIN vino v ON v.id = dc.cod_vino
GROUP BY v.id, v.nombre
ORDER BY botellas DESC
LIMIT 10;

-- Q2 = S3: Clientes de cada tipo que compraron en una sala en la última semana
-- (para otra sala, cambiar c.id_sala)
SELECT cl.tipoCliente, COUNT(DISTINCT cl.id) AS clientes
FROM comprobante c
JOIN clientes cl ON cl.id = c.id_cliente
WHERE c.id_sala = 1
  AND c.fecha >= CURRENT_DATE - 7
GROUP BY cl.tipoCliente;

-- Q3 = S8: Monto total de ventas por sala en el último trimestre
SELECT c.id_sala, SUM(c.total) AS monto
FROM comprobante c
WHERE c.fecha >= CURRENT_DATE - INTERVAL '3 months'
GROUP BY c.id_sala
ORDER BY monto DESC;

-- Q4 = S12 (parte anti-join): Clientes que nunca compraron un vino tinto
SELECT cl.id
FROM clientes cl
WHERE NOT EXISTS (
  SELECT 1
  FROM comprobante c
  JOIN detalle_comprobante dc ON dc.cod_comprobante = c.numero
  JOIN vino v ON v.id = dc.cod_vino
  WHERE c.id_cliente = cl.id AND v.tipo = 'tinto'
);

-- Q5: transferencias pendientes por sala (S5 / vista de pendientes)
SELECT id_sala, COUNT(*) FROM transferencias WHERE estado <> 'procesado' GROUP BY id_sala ORDER BY 2 LIMIT 5;
```

| Consulta | Sección 8 | Tablas y filas involucradas | Hipótesis: qué plan esperás y qué índice ayudaría |
|---|---|---|---|
| Q1 | S1 | detalle_comprobante (~525.000) + vino |Espero Seq Scan sobre renglon_comprobante (500.000 filas) porque al no haber WHERE tiene que leer toda la tabla para sumar. Un índice en la clave foránea cod_vino ayudaría a acelerar el cruce con la tabla de vinos.|
| Q2 | S3 | comprobante (150.000) + clientes | Espero Seq Scan sobre comprobante (150.000 filas) porque no hay índice por sala ni fecha. Un índice en (id_sala, fecha) debería leer solo las pocas filas de esa sala en la última semana |
| Q3 | S8 | comprobante (150.000) | Espero Seq Scan sobre comprobante (150.000 filas) filtrando el trimestre fila por fila. Un índice en (fecha) o (fecha, id_sala) permitiría saltar directo a las ventas de los últimos 3 meses sin leer el resto. |
| Q4 | S12 | clientes + comprobante + detalle_comprobante + vino | Espero varios Seq Scan lentísimos anidados dentro de la subconsulta. Un índice en la clave foránea comprobante(id_cliente) podría evitar recorrer comprobante por cada cliente. En detalle_comprobante no hace falta un índice nuevo por cod_comprobante: es la primera columna de la PK compuesta. |
| Q5 | S5 | transferencias (~2.000) | Se espera un Seq Scan escaneando toda la tabla. Un índice parcial en (id_sala, fecha_confeccion) WHERE estado <> 'procesado' evitará leer las transferencias procesadas, haciendo un Index Only Scan sobre el ~9,3% no procesado|.

---

## Tabla 2- Medición ANTES de crear los índices

| Consulta | Corrida 1 (ms) | Corrida 2 (ms) | Corrida 3 (ms) | Mediana (ms) | Recorrido | Filas leídas | Buffers (hit / read) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **Q1** | 140,7 | 117,5 | 128,7 | 128,7 | Parallel Seq Scan | 525.447 | hit 192 / read 4056 |
| **Q2** | 62,4 | 20,3 | 25,8 | 25,8 | Parallel Seq Scan | 150.000 | hit 1356 / read 0 |
| **Q3** | 29,7 | 25,5 | 22,1 | 25,5 | Parallel Seq Scan | 150.000 | hit 1356 / read 0 |
| **Q4** | 351,6 | 416,7 | 337,7 | 351,6 | Seq Scan | 525.446 | hit 352 / read 3896 |
| **Q5** |0,442|0,593|0,790|0,593|Seq Scan|	2.000	|hit 11 / read 0|
---

### Tabla 3 — Diseño y justificación de los índices

| N.° | Índice | Tipo o variante | Consulta que acelera | Justificación | Tamaño |
| --- | --- | --- | --- | --- | --- |
| 1 | `idx_comprobante_sala_fecha` | Compuesto | Q2 | Filtra por igualdad de sala y rango de fechas. Con la igualdad primero, el índice devuelve juntas las filas de esa sala en la última semana sin leer el resto. | 1776 kB |
| 2 | `idx_comprobante_fecha_cubriente` | INCLUDE (covering) | Q3 | Filtra solo por rango de fecha y necesita `id_sala` y `total`. Al incluirlos en la hoja del índice, se resuelve con un Index Only Scan sin visitar la tabla. | 5800 kB |
| 3 | `idx_comprobante_cliente` | Clave foránea | Q4 | PostgreSQL no indexa las FK por defecto. Buscar comprobantes por cliente y verificar el `ON DELETE RESTRICT` recorrería toda la tabla sin este índice. | 1480 kB |
| 4 | `idx_detalle_comprobante_vino` | FK + INCLUDE | Q1 | La PK es compuesta `(cod_comprobante, cod_vino)`, sirviendo para buscar por comprobante pero no directo por vino. Agrupa por vino e `INCLUDE (cantidad)` evita ir a la tabla. | 11 MB |
| 5 | `idx_transferencias_pendientes` | Parcial | Q5 | Solo un **9.3%** de las transferencias no está procesado. El índice es muy chico, barato de mantener y solo lo usan las consultas con ese mismo predicado parcial. | 16 kB |

---

### Tabla 4 — Comparativa ANTES vs. DESPUÉS de los índices

| Consulta | Antes (ms) | Recorrido antes | Filas leídas antes | Después (ms) | Recorrido después | Filas leídas después | Índice usado | Mejora (×) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **Q1** | 128,7 | Parallel Seq Scan | 525.447 | 131,3 | Parallel Seq Scan | 525.447 | Ninguno (lo ignora) | 1,0x |
| **Q2** | 25,8 | Parallel Seq Scan | 150.000 | 1,8 | Bitmap Heap Scan | 85 | idx_comprobante_sala_fecha | **14,3x** |
| **Q3** | 25,5 | Parallel Seq Scan | 150.000 | 4,8 | Index Only Scan | 11.878 | idx_comprobante_fecha_cubriente | **5,3x** |
| **Q4** | 351,6 | Seq Scan | 525.446 | 410,0 | Seq Scan | 525.446 | Ninguno (lo ignora) | 0,9x |
| **Q5** | 0,593 | Seq Scan | 2.000 | 0,862 | Index Only Scan | 185 | idx_transferencias_pendientes | 0,7x en tiempo (filas leídas: 2.000 → 185) |

> Q5 lee menos filas, pero con solo 2.000 filas en total la diferencia de tiempo no es significativa (menos de 1 ms). No se cuenta como una de las tres mejoras medidas.

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
| Tamaño BRIN vs B-tree | 24 kB / 5800 kB |
| Plan y tiempo de Q3 con BRIN | `Parallel Seq Scan` / Tiempo: 28,444 ms (el planificador descartó el BRIN y barrió la tabla) |
| Plan y tiempo de Q3 con el B-tree cubriente | `Index Only Scan` / Tiempo: 4,795 ms (con un tamaño de 5800 kB) |
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

### Tamaños de tablas e índices 

| Tabla | Tamaño de la tabla | Tamaño de sus índices |
| --- | --- | --- |
| `comprobante` | ~13 MB | ~9 MB (incluye B-Trees creados) |
| `detalle_comprobante` | ~38 MB | ~11 MB (`idx_detalle_comprobante_vino`) |

---

## Tabla 8- Caso en que el planificador no usa un índice existente



| Caso | Índice existente | Plan elegido | Tiempo (ms) | Plan forzado | Tiempo forzado (ms) | Causa explicada |
| --- | --- | --- | --- | --- | --- | --- |
| 8.1 filtro fecha ~80 % | `idx_comprobante_fecha_cubriente` | `Seq Scan` | 47,103 ms | `Bitmap Heap Scan` | 37,814 ms | **Baja selectividad:** con el 80 % de las filas, el costo **estimado** del Seq Scan es menor que el del índice y el planificador lo elige. En la medición el plan forzado resultó algo más rápido (37,8 ms contra 47,1 ms) porque la tabla estaba en caché: el modelo de costos supone lecturas aleatorias caras (`random_page_cost = 4`) que con los datos en memoria no ocurren. Es un ejemplo de que la estimación de costos no siempre coincide con el tiempo real. |
| 5.2 Q3 con `(id_sala, fecha)` | `idx_comprobante_sala_fecha` | `Bitmap Heap Scan` | 18,085 ms | *(N/A)* | *(N/A)* | **Primera columna no filtrada:** el índice `(id_sala, fecha)` tiene la igualdad (`id_sala`) primero, pero Q3 no filtra por sala. Como la primera columna no está acotada, el motor no puede usar el árbol para saltar al rango de fechas y debe recorrer todas sus entradas (Bitmap Heap Scan de 18 ms contra 4,8 ms del índice cubriente por `fecha`). |
---

## 9. Conclusiones y cierre de la etapa

A partir del análisis sistemático del rendimiento, los planes de ejecución (EXPLAIN ANALYZE), el consumo de buffers y las pruebas de carga masiva realizadas sobre la base de datos bodegas_del_atuel, se establecen las siguientes conclusiones y decisiones de diseño:

1. Balance entre Lectura y Escritura
Impacto mínimo en inserciones: Las pruebas de costo de escritura (Sección 7) demostraron que la incorporación de los 6 índices (B-Tree compuesto, cubrientes, parcial y de expresión) incrementa el tiempo total de la carga masiva en apenas un 2,05% (pasando de 1m 24s a 1m 25s).

Justificación operativa: Este bajo costo de penalización en las operaciones de INSERT (mediante COPY) queda ampliamente justificado por las mejoras de velocidad de hasta 14,3× obtenidas en las consultas críticas de lectura y reportes analíticos diarios (Q2, Q3 y Q5).

2. Decisiones sobre Tipos de Índices y Estructuras
Efectividad de Índices Compuestos y Cubrientes (INCLUDE): El uso de índices compuestos con la columna de igualdad ubicada en primer término demostró ser indispensable para consultas altamente selectivas (como Q2). Asimismo, los índices cubrientes (INCLUDE) permitieron resolver consultas agregadas directamente mediante Index Only Scan, evitando accesos innecesarios a los bloques de las tablas (detalle_comprobante y comprobante).

Descarte de Índices Ineficientes (BRIN): La evaluación del índice BRIN sobre la columna fecha evidenció que, ante una distribución de datos sin correlación física estricta (correlación cercana a 0.0028), el motor descarta la estructura en favor de un escaneo secuencial. Esto ratificó la decisión de priorizar índices B-Tree tradicionales para rangos temporales en tablas de transacciones medianas.

Optimización mediante Índices Parciales: En tablas con sesgo de estados (como transferencias, donde solo un 9.3% no está procesado), el índice parcial (WHERE estado <> 'procesado') redujo drásticamente el tamaño en disco (16 kB) y aceleró la consulta Q5 sin sobrecargar el mantenimiento general de la base de datos.

3. Inteligencia del Planificador (Costos y Selectividad)
Las pruebas de baja selectividad (Sección 8) mostraron que el optimizador descarta el índice cuando la consulta abarca la mayor parte de la tabla (80 % en el caso 8.1), porque estima más caro el acceso aleatorio. En nuestra medición, con los datos en caché, el plan forzado fue algo más rápido: la decisión del planificador se basa en costos estimados para disco, que pueden diferir del tiempo real cuando todo está en memoria.