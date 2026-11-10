-- Etapa 5 - Consultas INSERT (I1 a I6)
-- Cada consigna se prueba en una transacción: BEGIN, control previo,
-- sentencia, control posterior y ROLLBACK (no deja cambios). Para aplicar un
-- cambio de verdad, cambiar ROLLBACK por COMMIT.
-- Aunque se haga ROLLBACK, los números autogenerados (comprobante, ingreso,
-- sala) avanzan en cada ejecución.
-- Los parámetros están en el bloque PARÁMETROS: se cambian ahí.
-- Filas afectadas: datos generados con --seed 42 el 2026-11-09 (sin
-- --fecha-ref), ejecutado el 2026-11-09.

-- PARÁMETROS (cada comentario va en su propia línea: \set no admite
-- comentarios al final)
-- I1: localidad a cubrir
\set localidad_i1 'General Alvear'
-- I3: cliente y sala de la venta
\set cliente_i3 1
\set sala_i3 1
-- I6: vino, volumen, bodega y transportista del ingreso
\set vino_i6 'Malbec Reserva'
\set volumen_i6 750
\set bodega_i6 'Bodega Los Andes'
\set transporte_i6 'Transporte Rojas 02'


-- I1. Insertar en la relación transportista-localidad una nueva cobertura que
-- vincule la localidad de General Alvear con el transportista que menos envíos
-- (ingresos trasladados) haya realizado en el último trimestre.
-- LEFT JOIN con los ingresos del trimestre para contar también a los que no
-- hicieron envíos (0). Se excluyen los que ya cubren General Alvear, porque la
-- cobertura tiene que ser nueva. Los empates se ordenan por código.
-- Filas afectadas: 1 (hay 10 transportistas con 0 envíos; queda el 11).
BEGIN;

SELECT tl.cod_transporte, et.razon_social
FROM transportista_de_localidad tl
JOIN empresa_transporte et ON et.cod_transporte = tl.cod_transporte
WHERE tl.codigo_postal = (SELECT codigo_postal FROM localidades WHERE nombre = :'localidad_i1')
ORDER BY tl.cod_transporte;

INSERT INTO transportista_de_localidad (codigo_postal, cod_transporte)
SELECT (SELECT codigo_postal FROM localidades WHERE nombre = :'localidad_i1'), et.cod_transporte
FROM empresa_transporte et
LEFT JOIN ingresos i ON i.cod_transporte = et.cod_transporte
  AND i.fecha >= CURRENT_DATE - INTERVAL '3 months'
WHERE et.cod_transporte NOT IN (
  SELECT cod_transporte FROM transportista_de_localidad
  WHERE codigo_postal = (SELECT codigo_postal FROM localidades WHERE nombre = :'localidad_i1')
)
GROUP BY et.cod_transporte
ORDER BY COUNT(i.id), et.cod_transporte
LIMIT 1;

SELECT tl.cod_transporte, et.razon_social
FROM transportista_de_localidad tl
JOIN empresa_transporte et ON et.cod_transporte = tl.cod_transporte
WHERE tl.codigo_postal = (SELECT codigo_postal FROM localidades WHERE nombre = :'localidad_i1')
ORDER BY tl.cod_transporte;

ROLLBACK;


-- I2. Si existe algún vino tinto con graduación de 14° o más, crear el maridaje
-- «cordero al disco» y asociarlo a todos los vinos que cumplan esa condición.
-- El maridaje se inserta solo si existe algún vino que cumpla (WHERE EXISTS).
-- Después se asocia a esos vinos; si el maridaje no se hubiera creado, el
-- segundo INSERT no encuentra nada que asociar. Temperatura: 17 °C, como las
-- carnes rojas.
-- Filas afectadas: 1 maridaje y 126 asociaciones.
BEGIN;

SELECT COUNT(*) AS tintos_14_o_mas
FROM vino
WHERE tipo = 'tinto' AND graduacion >= 14;

INSERT INTO maridaje (nombre, temperatura)
SELECT 'Cordero al disco', 17
WHERE EXISTS (SELECT 1 FROM vino WHERE tipo = 'tinto' AND graduacion >= 14);

INSERT INTO vino_maridaje (cod_vino, cod_maridaje)
SELECT v.id, m.id
FROM vino v, maridaje m
WHERE m.nombre = 'Cordero al disco'
  AND v.tipo = 'tinto' AND v.graduacion >= 14;

SELECT m.nombre, m.temperatura, COUNT(vm.cod_vino) AS vinos_asociados
FROM maridaje m
LEFT JOIN vino_maridaje vm ON vm.cod_maridaje = m.id
WHERE m.nombre = 'Cordero al disco'
GROUP BY m.nombre, m.temperatura;

ROLLBACK;


-- I3. Crear un nuevo comprobante con tres renglones para un cliente dado, en la
-- sala con ID 1, dentro de una transacción y usando las funciones de cálculo.
-- Antes se consulta el stock con fn_stock_sala y el descuento del cliente con
-- fn_descuento_cliente. La cabecera arranca con importes en 0. Los renglones
-- se cargan solo con vino y cantidad: los triggers validan el stock (RN-09),
-- toman el precio, calculan el descuento (RN-06), descuentan el stock y
-- recalculan la cabecera con fn_total_comprobante (RN-08).
-- El número del comprobante nuevo es el máximo, porque se acaba de crear.
-- Filas afectadas: 1 comprobante y 3 renglones.
BEGIN;

SELECT id, precio, fn_stock_sala(:sala_i3, id) AS stock_sala, fn_descuento_cliente(:cliente_i3) AS descuento_cliente
FROM vino
WHERE id IN (2, 4, 5);

INSERT INTO comprobante (id_sala, id_cliente) VALUES (:sala_i3, :cliente_i3);

INSERT INTO detalle_comprobante (cod_comprobante, cod_vino, cantidad)
VALUES ((SELECT MAX(numero) FROM comprobante), 2, 3),
       ((SELECT MAX(numero) FROM comprobante), 4, 2),
       ((SELECT MAX(numero) FROM comprobante), 5, 1);

SELECT numero, fecha, subtotal, descuento, total, fn_total_comprobante(numero) AS total_funcion
FROM comprobante
WHERE numero = (SELECT MAX(numero) FROM comprobante);

SELECT cod_vino, cantidad, precio_unit, descuento, subtotal, fn_stock_sala(:sala_i3, cod_vino) AS stock_despues
FROM detalle_comprobante
WHERE cod_comprobante = (SELECT MAX(numero) FROM comprobante)
ORDER BY cod_vino;

ROLLBACK;


-- I4. Insertar una nueva bodega.
-- El CUIT debe tener 11 dígitos (dominio cuit_dom).
-- Filas afectadas: 1.
BEGIN;

SELECT COUNT(*) AS bodegas FROM bodega;

INSERT INTO bodega (cuit, razon_social, calle, num_calle)
VALUES ('30712345674', 'Bodega Las Acequias', 'Ruta Provincial 143', 1250);

SELECT COUNT(*) AS bodegas FROM bodega;
SELECT * FROM bodega WHERE cuit = '30712345674';

ROLLBACK;


-- I5. Insertar una nueva sala de venta.
-- La localidad debe existir (FK, RN-02) y el día de cierre debe ser válido
-- (CHECK). Se usa Tunuyán, que todavía no tiene sala.
-- Filas afectadas: 1.
BEGIN;

SELECT COUNT(*) AS salas FROM sala_de_ventas;

INSERT INTO sala_de_ventas (calle, numero, dia_cierre, codigo_postal)
VALUES ('Av. San Martín', 850, 'Martes', (SELECT codigo_postal FROM localidades WHERE nombre = 'Tunuyán'));

SELECT COUNT(*) AS salas FROM sala_de_ventas;
SELECT * FROM sala_de_ventas WHERE id_sala = (SELECT MAX(id_sala) FROM sala_de_ventas);

ROLLBACK;


-- I6. Crear un ingreso en confección de 120 botellas de un vino determinado
-- («Malbec Reserva» de 750 ml), elaborado por una bodega dada y trasladado por
-- un transportista dado.
-- La cabecera se inserta sin estado ni fecha: los DEFAULT ponen en_confeccion
-- y la fecha actual. El renglón busca el vino por nombre, volumen y bodega.
-- Filas afectadas: 1 ingreso y 1 renglón.
BEGIN;

SELECT estado, COUNT(*) AS ingresos FROM ingresos GROUP BY estado;

INSERT INTO ingresos (cuit_bodega, cod_transporte)
VALUES ((SELECT cuit FROM bodega WHERE razon_social = :'bodega_i6'),
        (SELECT cod_transporte FROM empresa_transporte WHERE razon_social = :'transporte_i6'));

INSERT INTO detalle_ingreso (num_ingreso, cod_vino, cantidad)
SELECT (SELECT MAX(id) FROM ingresos), v.id, 120
FROM vino v
JOIN bodega b ON b.cuit = v.cuit_bodega
WHERE v.nombre = :'vino_i6' AND v.volumen = :volumen_i6
  AND b.razon_social = :'bodega_i6';

SELECT i.id, i.fecha, i.estado, b.razon_social AS bodega, et.razon_social AS transportista,
  v.nombre AS vino, v.volumen, di.cantidad
FROM ingresos i
JOIN bodega b ON b.cuit = i.cuit_bodega
JOIN empresa_transporte et ON et.cod_transporte = i.cod_transporte
JOIN detalle_ingreso di ON di.num_ingreso = i.id
JOIN vino v ON v.id = di.cod_vino
WHERE i.id = (SELECT MAX(id) FROM ingresos);

ROLLBACK;
