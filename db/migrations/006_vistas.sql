-- Vista 1: Stock total por vino
CREATE OR REPLACE VIEW vista_stock_total_vino AS
SELECT 
    v.id AS cod_vino,
    v.nombre AS vino_nombre,
    v.anada,
    v.volumen,
    COALESCE(dc.cantidad, 0) AS stock_deposito,
    COALESCE(SUM(ds.cantidad), 0)::INTEGER AS stock_salas,
    (COALESCE(dc.cantidad, 0) + COALESCE(SUM(ds.cantidad), 0))::INTEGER AS stock_total
FROM vino v
LEFT JOIN stock_central dc ON v.id = dc.codigo_vino
LEFT JOIN stock_sala ds ON v.id = ds.cod_vino
GROUP BY v.id, v.nombre, v.anada, v.volumen, dc.cantidad;

-- Vista 2: Ventas mensuales por sala
CREATE OR REPLACE VIEW vista_ventas_mensuales_sala AS
SELECT 
    s.id_sala,
    l.nombre AS localidad,
    DATE_TRUNC('month', c.fecha)::DATE AS mes,
    COUNT(c.numero) AS cantidad_ventas,
    COALESCE(SUM(c.total), 0.00) AS recaudacion_total
FROM sala_de_ventas s
JOIN localidades l ON s.codigo_postal = l.codigo_postal
JOIN comprobante c ON s.id_sala = c.id_sala
GROUP BY s.id_sala, l.nombre, DATE_TRUNC('month', c.fecha);

-- Vista 3: Transferencias e ingresos pendientes
CREATE OR REPLACE VIEW vista_documentos_pendientes AS
SELECT 
    'TRANSFERENCIA' AS tipo_documento,
    t.num_solicitud AS identificador,
    t.fecha_confeccion AS fecha,
    t.estado,
    t.id_sala AS sala_destino
FROM transferencias t
WHERE t.estado <> 'procesado'
UNION ALL
SELECT 
    'INGRESO' AS tipo_documento,
    i.id AS identificador,
    i.fecha,
    i.estado,
    NULL::INTEGER AS sala_destino
FROM ingresos i
WHERE i.estado <> 'procesado';