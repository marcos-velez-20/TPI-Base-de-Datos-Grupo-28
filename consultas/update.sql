-- Etapa 5 - Consultas UPDATE (U1 a U6)
-- Cada consigna se prueba en una transacción: BEGIN, control previo,
-- sentencia, control posterior y ROLLBACK (no deja cambios). Para aplicar un
-- cambio de verdad, cambiar ROLLBACK por COMMIT.
-- Los parámetros están en el bloque PARÁMETROS: se cambian ahí.
-- Filas afectadas: datos generados con --seed 42 el 2026-11-09 (sin
-- --fecha-ref), ejecutado el 2026-11-09.

-- PARÁMETROS (cada comentario va en su propia línea: \set no admite
-- comentarios al final)
-- U3: bodega
\set bodega_u3 'Bodegas del Atuel'


-- U1. Recalcular el total de todos los comprobantes aplicando el descuento que
-- corresponde al tipo de cliente.
-- Los importes del comprobante no se pueden modificar a mano (RN-08, trigger
-- trg_comprobante_totales_before). Por eso se actualizan los renglones sin
-- cambiar la cantidad: el trigger BEFORE recalcula descuento y subtotal de cada
-- renglón con fn_descuento_cliente, y el trigger AFTER recalcula la cabecera
-- con fn_total_comprobante. Sirve, por ejemplo, después de U6.
-- Filas afectadas: 525.386 renglones (tarda unos 45 s). Con los datos recién
-- generados los controles dan 0 antes y después y la suma no cambia, porque
-- los importes ya eran correctos.
BEGIN;

SELECT COUNT(*) AS renglones_mal_calculados
FROM detalle_comprobante dc
JOIN comprobante c ON c.numero = dc.cod_comprobante
WHERE dc.descuento <> ROUND(dc.precio_unit * dc.cantidad * fn_descuento_cliente(c.id_cliente) / 100, 2);

SELECT COUNT(*) AS comprobantes_mal_calculados
FROM comprobante
WHERE total <> fn_total_comprobante(numero);

SELECT SUM(total) AS suma_totales FROM comprobante;

UPDATE detalle_comprobante SET cantidad = cantidad;

SELECT COUNT(*) AS renglones_mal_calculados
FROM detalle_comprobante dc
JOIN comprobante c ON c.numero = dc.cod_comprobante
WHERE dc.descuento <> ROUND(dc.precio_unit * dc.cantidad * fn_descuento_cliente(c.id_cliente) / 100, 2);

SELECT COUNT(*) AS comprobantes_mal_calculados
FROM comprobante
WHERE total <> fn_total_comprobante(numero);

SELECT SUM(total) AS suma_totales FROM comprobante;

ROLLBACK;


-- U2. Aumentar un 20 % el salario de los empleados con más de 5 años de
-- antigüedad.
-- La antigüedad se calcula con la función fn_antiguedad_anios.
-- Filas afectadas: 20.
BEGIN;

SELECT COUNT(*) AS empleados, SUM(salario) AS masa_salarial
FROM empleado
WHERE fn_antiguedad_anios(fecha_ingreso) > 5;

UPDATE empleado
SET salario = ROUND(salario * 1.20, 2)
WHERE fn_antiguedad_anios(fecha_ingreso) > 5;

SELECT COUNT(*) AS empleados, SUM(salario) AS masa_salarial
FROM empleado
WHERE fn_antiguedad_anios(fecha_ingreso) > 5;

ROLLBACK;


-- U3. Incrementar un 13 % el precio de los vinos elaborados por una bodega
-- determinada.
-- El CUIT se busca con una subconsulta por la razón social. Cada cambio de
-- precio dispara el trigger de auditoría (RN-13).
-- Filas afectadas: 45 vinos (auditoria_precio pasa de 30 a 75 filas).
BEGIN;

SELECT COUNT(*) AS vinos, SUM(precio) AS suma_precios
FROM vino
WHERE cuit_bodega = (SELECT cuit FROM bodega WHERE razon_social = :'bodega_u3');

SELECT COUNT(*) AS filas_auditoria FROM auditoria_precio;

UPDATE vino
SET precio = ROUND(precio * 1.13, 2)
WHERE cuit_bodega = (SELECT cuit FROM bodega WHERE razon_social = :'bodega_u3');

SELECT COUNT(*) AS vinos, SUM(precio) AS suma_precios
FROM vino
WHERE cuit_bodega = (SELECT cuit FROM bodega WHERE razon_social = :'bodega_u3');

SELECT COUNT(*) AS filas_auditoria FROM auditoria_precio;

ROLLBACK;


-- U4. En las salas cuyo día de cierre es lunes cambiarlo a miércoles y
-- viceversa, en una sola sentencia.
-- Un solo UPDATE con CASE: cada fila se evalúa con su valor anterior, así que
-- no hace falta un valor intermedio.
-- Filas afectadas: 6 (2 salas con lunes y 4 con miércoles).
BEGIN;

SELECT dia_cierre, COUNT(*) AS salas
FROM sala_de_ventas
WHERE dia_cierre IN ('Lunes', 'Miércoles')
GROUP BY dia_cierre;

UPDATE sala_de_ventas
SET dia_cierre = CASE WHEN dia_cierre = 'Lunes' THEN 'Miércoles' ELSE 'Lunes' END
WHERE dia_cierre IN ('Lunes', 'Miércoles');

SELECT dia_cierre, COUNT(*) AS salas
FROM sala_de_ventas
WHERE dia_cierre IN ('Lunes', 'Miércoles')
GROUP BY dia_cierre;

ROLLBACK;


-- U5. Aplicar un 15 % de descuento de precio a los 10 vinos menos vendidos de
-- toda la red.
-- Se parte de vino con LEFT JOIN para incluir los que nunca se vendieron
-- (cuentan como 0). Los empates se ordenan por código. Cada cambio de precio
-- queda auditado (RN-13).
-- Filas afectadas: 10.
BEGIN;

SELECT v.id, v.nombre, v.precio,
  CASE WHEN SUM(dc.cantidad) IS NULL THEN 0 ELSE SUM(dc.cantidad) END AS botellas
FROM vino v
LEFT JOIN detalle_comprobante dc ON dc.cod_vino = v.id
GROUP BY v.id, v.nombre, v.precio
ORDER BY botellas, v.id
LIMIT 10;

UPDATE vino
SET precio = ROUND(precio * 0.85, 2)
WHERE id IN (
  SELECT v.id
  FROM vino v
  LEFT JOIN detalle_comprobante dc ON dc.cod_vino = v.id
  GROUP BY v.id
  ORDER BY CASE WHEN SUM(dc.cantidad) IS NULL THEN 0 ELSE SUM(dc.cantidad) END, v.id
  LIMIT 10
);

SELECT id_vino, precio_anterior, precio_nuevo
FROM auditoria_precio
WHERE fecha = CURRENT_DATE
ORDER BY id_vino;

ROLLBACK;


-- U6. A los exportadores con más de 3 permisos de exportación, subirles el
-- descuento al 35 %.
-- Subconsulta con GROUP BY y HAVING sobre permisos. El CHECK de clientes
-- admite 30 o 35 % para exportadores. Como fn_descuento_cliente lee esta
-- columna, las ventas siguientes ya usan el 35 % (para las anteriores, U1).
-- Filas afectadas: 400.
BEGIN;

SELECT descuento, COUNT(*) AS exportadores
FROM clientes
WHERE tipoCliente = 'exportador'
GROUP BY descuento;

UPDATE clientes
SET descuento = 35
WHERE tipoCliente = 'exportador'
  AND id IN (SELECT id_exportador FROM permisos GROUP BY id_exportador HAVING COUNT(*) > 3);

SELECT descuento, COUNT(*) AS exportadores
FROM clientes
WHERE tipoCliente = 'exportador'
GROUP BY descuento;

ROLLBACK;