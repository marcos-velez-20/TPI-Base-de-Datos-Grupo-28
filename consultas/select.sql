-- Etapa 5 - Consultas SELECT (S1 a S12)
-- Los parámetros están en el bloque PARÁMETROS: para probar otro valor del
-- dataset se cambia ahí. Los períodos se calculan desde CURRENT_DATE.
-- Resultados de referencia: datos generados con --seed 42 el 2026-11-09 (sin
-- --fecha-ref), consultados el 2026-11-09.

-- PARÁMETROS (cada comentario va en su propia línea: \set no admite
-- comentarios al final)
-- S3: sala
\set sala_s3 13
-- S4: vino
\set vino_s4 177
-- S6: sala
\set sala_s6 1
-- S9: vino (1 = Malbec Reserva)
\set vino_s9 1
-- S12: bodega
\set bodega_s12 'Bodega Pequeña Selección'


-- S1. Ranking de los 10 vinos con mayor cantidad de botellas vendidas en toda
-- la red de salas.
-- Se agrupan los renglones de venta por vino, se suman las botellas y se
-- ordena de mayor a menor.
SELECT v.id, v.nombre, v.anada, v.volumen, SUM(dc.cantidad) AS botellas
FROM detalle_comprobante dc
JOIN vino v ON v.id = dc.cod_vino
GROUP BY v.id, v.nombre, v.anada, v.volumen
ORDER BY botellas DESC
LIMIT 10;


-- S2. Códigos y nombres de los vinos que se vendieron en todas las salas
-- (división relacional).
-- Doble NOT EXISTS: el vino califica si no hay ninguna sala donde no se haya
-- vendido.
SELECT v.id, v.nombre
FROM vino v
WHERE NOT EXISTS (
  SELECT 1 FROM sala_de_ventas s
  WHERE NOT EXISTS (
    SELECT 1 FROM comprobante c
    JOIN detalle_comprobante dc ON dc.cod_comprobante = c.numero
    WHERE c.id_sala = s.id_sala AND dc.cod_vino = v.id
  )
)
ORDER BY v.id;


-- S3. Cantidad de clientes de cada tipo que compraron en una sala determinada
-- en la última semana.
-- Se cuentan clientes distintos, porque un cliente puede comprar varias veces.
SELECT cl.tipoCliente, COUNT(DISTINCT cl.id) AS clientes
FROM comprobante c
JOIN clientes cl ON cl.id = c.id_cliente
WHERE c.id_sala = :sala_s3
  AND c.fecha >= CURRENT_DATE - 7
GROUP BY cl.tipoCliente
ORDER BY clientes DESC;


-- S4. Top 5 de las salas que solicitaron mayor cantidad de un vino determinado
-- mediante transferencias en los últimos 15 días.
-- Se suman las botellas pedidas del vino por sala.
-- Nota: en los datos generados hay solo 10 transferencias en los últimos 15
-- días y cada vino aparece en una sola sala, por eso sale una sola fila.
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


-- S5. Listado de las salas con menor cantidad de transferencias pendientes
-- (no procesadas).
-- LEFT JOIN para que las salas sin pendientes cuenten 0. Se muestran todas las
-- que tienen la cantidad mínima.
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


-- S6. Para una sala determinada, los vinos sin stock en la sala pero con stock
-- en el depósito central.
-- "Sin stock en la sala" es no tener fila en stock_sala o tenerla en 0, por
-- eso se usa LEFT JOIN.
SELECT v.id, v.nombre, sc.cantidad AS stock_deposito
FROM vino v
JOIN stock_central sc ON sc.codigo_vino = v.id
LEFT JOIN stock_sala ss ON ss.cod_vino = v.id AND ss.id_sala = :sala_s6
WHERE sc.cantidad > 0
  AND (ss.cantidad IS NULL OR ss.cantidad = 0)
ORDER BY sc.cantidad DESC, v.id;


-- S7. ¿Cuál es la empresa de transporte con mayor actividad en el último mes?
-- Actividad = cantidad de ingresos que trasladó. Con HAVING se devuelven todas
-- las empresas que empatan en el máximo.
SELECT et.cod_transporte, et.razon_social, COUNT(i.id) AS ingresos
FROM empresa_transporte et
JOIN ingresos i ON i.cod_transporte = et.cod_transporte
WHERE i.fecha >= CURRENT_DATE - INTERVAL '1 month'
GROUP BY et.cod_transporte, et.razon_social
HAVING COUNT(i.id) = (
  SELECT MAX(cant) FROM (
    SELECT COUNT(*) AS cant FROM ingresos
    WHERE fecha >= CURRENT_DATE - INTERVAL '1 month'
    GROUP BY cod_transporte
  ) AS conteos
);


-- S8. Monto total de ventas por sala en el último trimestre, en orden
-- descendente.
-- Se suma el total de los comprobantes (ya tiene el descuento aplicado).
SELECT c.id_sala, l.nombre AS localidad, SUM(c.total) AS monto
FROM comprobante c
JOIN sala_de_ventas s ON s.id_sala = c.id_sala
JOIN localidades l ON l.codigo_postal = s.codigo_postal
WHERE c.fecha >= CURRENT_DATE - INTERVAL '3 months'
GROUP BY c.id_sala, l.nombre
ORDER BY monto DESC;


-- S9. Ficha de un vino: cepas con sus porcentajes, bodega elaboradora,
-- maridajes y stock total (depósito más salas).
-- Herramienta: joins, agregación (COUNT y la suma de stock de la vista) y vista.
-- Se resuelve en tres consultas para
-- no multiplicar filas (si se unieran cepas y maridajes en una sola, cada cepa
-- se repetiría por cada maridaje). El stock sale de la vista
-- vista_stock_total_vino.

-- S9 (a): datos del vino, bodega, cantidad de cepas y maridajes, y stock
SELECT v.id, v.nombre, v.tipo, v.anada, v.volumen, v.graduacion, v.precio,
  b.razon_social AS bodega,
  (SELECT COUNT(*) FROM composicion co WHERE co.id_vino = v.id) AS cantidad_cepas,
  (SELECT COUNT(*) FROM vino_maridaje vm WHERE vm.cod_vino = v.id) AS cantidad_maridajes,
  st.stock_deposito, st.stock_salas, st.stock_total
FROM vino v
JOIN bodega b ON b.cuit = v.cuit_bodega
JOIN vista_stock_total_vino st ON st.cod_vino = v.id
WHERE v.id = :vino_s9;

-- S9 (b): cepas y porcentajes
SELECT ce.nombre AS cepa, co.porcentaje
FROM composicion co
JOIN cepa ce ON ce.identificador = co.id_cepa
WHERE co.id_vino = :vino_s9
ORDER BY co.porcentaje DESC;

-- S9 (c): maridajes
SELECT m.nombre AS maridaje, m.temperatura
FROM vino_maridaje vm
JOIN maridaje m ON m.id = vm.cod_maridaje
WHERE vm.cod_vino = :vino_s9
ORDER BY m.nombre;


-- S10. Rendimiento en kg por hectárea de cada parcela y campaña, e
-- identificación de las parcelas que rinden menos que el promedio de su finca.
-- Herramienta: CTE y subconsulta correlacionada.
-- La CTE calcula los kg/ha. La subconsulta correlacionada calcula el promedio
-- de la misma finca en la misma campaña. Va contra las tablas base y no contra
-- la CTE para poder usar los índices de lote_uva y parcelas (una CTE no tiene
-- índices y habría que recorrerla entera en cada ejecución).

-- S10 (a): rendimiento de todas las parcelas
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

-- S10 (b): parcelas que rinden menos que el promedio de su finca
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


-- S11. Ranking de vinos dentro de cada sala por botellas vendidas y ventas
-- acumuladas mensuales por sala.
-- Herramienta: RANK() OVER (PARTITION BY ...) y suma acumulada con ventana.

-- S11 (a): ranking de vinos por sala (los 3 primeros de cada sala).
-- RANK() numera los vinos dentro de cada sala según las botellas vendidas; los
-- empates comparten puesto.
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

-- S11 (b): ventas mensuales por sala y su acumulado.
-- SUM() OVER con ORDER BY mes suma el mes actual y los anteriores de la misma
-- sala; PARTITION BY hace que el acumulado empiece de nuevo en cada sala.
WITH ventas_mes AS (
  SELECT id_sala, DATE_TRUNC('month', fecha)::DATE AS mes, SUM(total) AS monto
  FROM comprobante
  GROUP BY id_sala, DATE_TRUNC('month', fecha)
)
SELECT id_sala, mes, monto,
  SUM(monto) OVER (PARTITION BY id_sala ORDER BY mes) AS acumulado
FROM ventas_mes
ORDER BY id_sala, mes;


-- S12. Clientes que compraron todos los vinos de una bodega determinada, y
-- clientes que nunca compraron ningún vino tinto.
-- Herramienta: NOT EXISTS (división) y anti-join.

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

-- S12 (b): anti-join. Clientes con al menos una compra pero ninguna de vino
-- tinto (los que nunca compraron nada no se cuentan).
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