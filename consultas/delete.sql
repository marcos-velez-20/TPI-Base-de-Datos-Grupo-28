-- Etapa 5 - Consultas DELETE (D1 a D6)
-- Cada consigna se prueba en una transacción: BEGIN, control previo,
-- sentencia, control posterior y ROLLBACK (no deja cambios). Para aplicar un
-- cambio de verdad, cambiar ROLLBACK por COMMIT.
-- Los parámetros están en el bloque PARÁMETROS: se cambian ahí.
-- Filas afectadas: datos generados con --seed 42 el 2026-11-09 (sin
-- --fecha-ref), ejecutado el 2026-11-09.

-- PARÁMETROS (cada comentario va en su propia línea: \set no admite
-- comentarios al final)
-- D3: localidad de la sala dada de baja
\set localidad_d3 'Maipú'
-- D6: localidad de los socios
\set localidad_d6 'Junín'


-- D1. Borrar los comprobantes con más de 5 años de antigüedad asociados a
-- clientes socios del club.
-- Los renglones se borran solos por ON DELETE CASCADE. El trigger de los
-- renglones no devuelve stock al borrar: son ventas históricas.
-- Filas afectadas: 12.867 comprobantes (45.088 renglones).
BEGIN;

SELECT COUNT(*) AS comprobantes_a_borrar
FROM comprobante
WHERE id_cliente IN (SELECT id FROM socio_club)
  AND fecha < CURRENT_DATE - INTERVAL '5 years';

SELECT COUNT(*) AS renglones FROM detalle_comprobante;

DELETE FROM comprobante
WHERE id_cliente IN (SELECT id FROM socio_club)
  AND fecha < CURRENT_DATE - INTERVAL '5 years';

SELECT COUNT(*) AS comprobantes_a_borrar
FROM comprobante
WHERE id_cliente IN (SELECT id FROM socio_club)
  AND fecha < CURRENT_DATE - INTERVAL '5 years';

SELECT COUNT(*) AS renglones FROM detalle_comprobante;

ROLLBACK;


-- D2. Eliminar las cepas que no componen ningún vino ni están plantadas en
-- ninguna parcela.
-- Dos NOT EXISTS: contra composicion y contra parcelas.
-- Filas afectadas: 1 (Semillón).
BEGIN;

SELECT identificador, nombre
FROM cepa ce
WHERE NOT EXISTS (SELECT 1 FROM composicion co WHERE co.id_cepa = ce.identificador)
  AND NOT EXISTS (SELECT 1 FROM parcelas p WHERE p.id_cepa = ce.identificador);

DELETE FROM cepa ce
WHERE NOT EXISTS (SELECT 1 FROM composicion co WHERE co.id_cepa = ce.identificador)
  AND NOT EXISTS (SELECT 1 FROM parcelas p WHERE p.id_cepa = ce.identificador);

SELECT COUNT(*) AS cepas FROM cepa;

ROLLBACK;


-- D3. La sala de una localidad determinada fue dada de baja: eliminar los
-- empleados de esa sala que trabajaron menos de dos años.
-- La sala se busca por la localidad y la antigüedad se calcula con
-- fn_antiguedad_anios.
-- Filas afectadas: 8.
BEGIN;

SELECT e.cuit, e.nombre, e.fecha_ingreso, fn_antiguedad_anios(e.fecha_ingreso) AS antiguedad
FROM empleado e
JOIN sala_de_ventas s ON s.id_sala = e.id_sala
JOIN localidades l ON l.codigo_postal = s.codigo_postal
WHERE l.nombre = :'localidad_d3'
ORDER BY e.fecha_ingreso;

DELETE FROM empleado
WHERE id_sala IN (
  SELECT s.id_sala FROM sala_de_ventas s
  JOIN localidades l ON l.codigo_postal = s.codigo_postal
  WHERE l.nombre = :'localidad_d3'
)
AND fn_antiguedad_anios(fecha_ingreso) < 2;

SELECT e.cuit, e.nombre, e.fecha_ingreso, fn_antiguedad_anios(e.fecha_ingreso) AS antiguedad
FROM empleado e
JOIN sala_de_ventas s ON s.id_sala = e.id_sala
JOIN localidades l ON l.codigo_postal = s.codigo_postal
WHERE l.nombre = :'localidad_d3'
ORDER BY e.fecha_ingreso;

ROLLBACK;


-- D4. Borrar los clientes socios que nunca compraron y se dieron de alta hace
-- más de 5 años.
-- Se borra en clientes (el supertipo) y la fila de socio_club se borra por
-- ON DELETE CASCADE. Como no tienen compras, el ON DELETE RESTRICT de
-- comprobante no lo impide.
-- Filas afectadas: 800.
BEGIN;

SELECT COUNT(*) AS socios FROM socio_club;

DELETE FROM clientes c
WHERE c.tipoCliente = 'socio'
  AND c.fecha_alta < CURRENT_DATE - INTERVAL '5 years'
  AND NOT EXISTS (SELECT 1 FROM comprobante co WHERE co.id_cliente = c.id);

SELECT COUNT(*) AS socios FROM socio_club;

ROLLBACK;


-- D5. Eliminar los ingresos en estado procesado de hace más de 365 días.
-- Los renglones se borran por ON DELETE CASCADE; el trigger de RN-12 lo
-- permite porque se borra el documento completo. El stock del depósito no
-- cambia: esos ingresos ya impactaron.
-- Filas afectadas: 1.700 ingresos (4.500 renglones).
BEGIN;

SELECT COUNT(*) AS ingresos_a_borrar
FROM ingresos
WHERE estado = 'procesado' AND fecha < CURRENT_DATE - 365;

SELECT SUM(cantidad) AS stock_deposito FROM stock_central;

DELETE FROM ingresos
WHERE estado = 'procesado' AND fecha < CURRENT_DATE - 365;

SELECT COUNT(*) AS ingresos_a_borrar
FROM ingresos
WHERE estado = 'procesado' AND fecha < CURRENT_DATE - 365;

SELECT SUM(cantidad) AS stock_deposito FROM stock_central;

ROLLBACK;


-- D6. Borrar los clientes socios sin compras que viven en una localidad
-- específica.
-- Igual que D4, filtrando por la localidad del cliente.
-- Filas afectadas: 33.
BEGIN;

SELECT COUNT(*) AS socios_sin_compras
FROM clientes c
WHERE c.tipoCliente = 'socio'
  AND c.codigo_postal = (SELECT codigo_postal FROM localidades WHERE nombre = :'localidad_d6')
  AND NOT EXISTS (SELECT 1 FROM comprobante co WHERE co.id_cliente = c.id);

DELETE FROM clientes c
WHERE c.tipoCliente = 'socio'
  AND c.codigo_postal = (SELECT codigo_postal FROM localidades WHERE nombre = :'localidad_d6')
  AND NOT EXISTS (SELECT 1 FROM comprobante co WHERE co.id_cliente = c.id);

SELECT COUNT(*) AS socios_sin_compras
FROM clientes c
WHERE c.tipoCliente = 'socio'
  AND c.codigo_postal = (SELECT codigo_postal FROM localidades WHERE nombre = :'localidad_d6')
  AND NOT EXISTS (SELECT 1 FROM comprobante co WHERE co.id_cliente = c.id);

ROLLBACK;