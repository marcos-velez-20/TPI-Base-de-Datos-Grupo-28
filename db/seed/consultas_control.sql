-- Control 1: Filas huérfanas en FKs principales
SELECT 'stock_sala.id_sala' AS ctrl, COUNT(*) AS filas_problematicas
FROM stock_sala s
LEFT JOIN sala_de_ventas v ON s.id_sala = v.id_sala
WHERE v.id_sala IS NULL
UNION ALL
SELECT 'stock_sala.cod_vino', COUNT(*)
FROM stock_sala s
LEFT JOIN vino v ON s.cod_vino = v.id
WHERE v.id IS NULL
UNION ALL
SELECT 'stock_central.codigo_vino', COUNT(*)
FROM stock_central s
LEFT JOIN vino v ON s.codigo_vino = v.id
WHERE v.id IS NULL
UNION ALL
SELECT 'comprobante.id_sala', COUNT(*)
FROM comprobante c
LEFT JOIN sala_de_ventas v ON c.id_sala = v.id_sala
WHERE v.id_sala IS NULL
UNION ALL
SELECT 'comprobante.id_cliente', COUNT(*)
FROM comprobante c
LEFT JOIN clientes cl ON c.id_cliente = cl.id
WHERE cl.id IS NULL
UNION ALL
SELECT 'detalle_comprobante.cod_comprobante', COUNT(*)
FROM detalle_comprobante dc
LEFT JOIN comprobante c ON dc.cod_comprobante = c.numero
WHERE c.numero IS NULL
UNION ALL
SELECT 'detalle_comprobante.cod_vino', COUNT(*)
FROM detalle_comprobante dc
LEFT JOIN vino v ON dc.cod_vino = v.id
WHERE v.id IS NULL
UNION ALL
SELECT 'detalle_ingreso.num_ingreso', COUNT(*)
FROM detalle_ingreso di
LEFT JOIN ingresos i ON di.num_ingreso = i.id
WHERE i.id IS NULL
UNION ALL
SELECT 'detalle_ingreso.cod_vino', COUNT(*)
FROM detalle_ingreso di
LEFT JOIN vino v ON di.cod_vino = v.id
WHERE v.id IS NULL
UNION ALL
SELECT 'detalle_transferencia.num_transferencia', COUNT(*)
FROM detalle_transferencia dt
LEFT JOIN transferencias t ON dt.num_transferencia = t.num_solicitud
WHERE t.num_solicitud IS NULL
UNION ALL
SELECT 'detalle_transferencia.cod_vino', COUNT(*)
FROM detalle_transferencia dt
LEFT JOIN vino v ON dt.cod_vino = v.id
WHERE v.id IS NULL
UNION ALL
SELECT 'permisos.id_exportador', COUNT(*)
FROM permisos p
LEFT JOIN exportadores e ON p.id_exportador = e.id
WHERE e.id IS NULL
UNION ALL
SELECT 'stock_sala.cantidad < 0', COUNT(*)
FROM stock_sala
WHERE cantidad < 0
UNION ALL
SELECT 'stock_central.cantidad < 0', COUNT(*)
FROM stock_central
WHERE cantidad < 0
UNION ALL
SELECT 'comprobante subtotal/descuento/total inconsistente', COUNT(*)
FROM comprobante c
WHERE (
    SELECT COALESCE(SUM(dc.precio_unit * dc.cantidad), 0.00)
    FROM detalle_comprobante dc
    WHERE dc.cod_comprobante = c.numero
) != c.subtotal
UNION ALL
SELECT 'comprobante descuento inconsistente', COUNT(*)
FROM comprobante c
WHERE (
    SELECT COALESCE(SUM(dc.descuento), 0.00)
    FROM detalle_comprobante dc
    WHERE dc.cod_comprobante = c.numero
) != c.descuento
UNION ALL
SELECT 'comprobante total inconsistente', COUNT(*)
FROM comprobante c
WHERE (
    SELECT COALESCE(SUM(dc.subtotal), 0.00)
    FROM detalle_comprobante dc
    WHERE dc.cod_comprobante = c.numero
) != c.total
UNION ALL
SELECT 'vino composicion suma <> 100', COUNT(*)
FROM vino v
WHERE (
    SELECT COALESCE(SUM(porcentaje), 0.00)
    FROM composicion c
    WHERE c.id_vino = v.id
) != 100.00
UNION ALL
SELECT 'permisos vencimiento <= emision', COUNT(*)
FROM permisos
WHERE fecha_vencimiento <= fecha_emision
UNION ALL
SELECT 'comprobante fecha > CURRENT_DATE', COUNT(*)
FROM comprobante
WHERE fecha > CURRENT_DATE
UNION ALL
SELECT 'ingresos fecha > CURRENT_DATE', COUNT(*)
FROM ingresos
WHERE fecha > CURRENT_DATE
UNION ALL
SELECT 'transferencias fecha_confeccion > CURRENT_DATE', COUNT(*)
FROM transferencias
WHERE fecha_confeccion > CURRENT_DATE
UNION ALL
SELECT 'ingresos estado inválido', COUNT(*)
FROM ingresos
WHERE estado NOT IN ('en_confeccion', 'terminado', 'procesado')
UNION ALL
SELECT 'transferencias estado inválido', COUNT(*)
FROM transferencias
WHERE estado NOT IN ('en_confeccion', 'terminado', 'procesado');