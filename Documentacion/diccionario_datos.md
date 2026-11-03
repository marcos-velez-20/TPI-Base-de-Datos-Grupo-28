Trabajo Práctico Integrador: Bodegas del Atuel - Etapa 1

Integrantes: Marcos Velez, Dalma, Vale, Nico

Curso: 3er Año - Ingeniería en Sistemas de Información (UTN FRSR)

# Diccionario de Datos

## Convenciones

- `PK`: clave primaria.
- `FK`: clave foránea.
- `NN`: columna `NOT NULL`.
- `IDENTITY`: valor autogenerado por PostgreSQL.
- `UNIQUE`: restricción de unicidad.
- `DEFAULT`: valor por defecto.
- Las reglas marcadas como **Etapa 2** se implementan en `002_constraints.sql`, `003_funciones.sql`, `004_procedimientos.sql` o `005_triggers.sql`. No forman parte del DDL base de `001_esquema.sql`.
- Los importes usan `NUMERIC`; no se usa `FLOAT`.

---

## 1. Tabla: `localidades`

Catálogo de localidades donde la empresa tiene salas de venta.

| Columna | Tipo | Nulo | Restricciones en 001 | Regla de negocio / Etapa 2 | Descripción |
| --- | --- | --- | --- | --- | --- |
| `codigo_postal` | `INTEGER` | NO | PK |  | Código postal que identifica la localidad. |
| `nombre` | `VARCHAR(100)` | NO |  | Etapa 2: `UNIQUE (nombre, provincia)` sugerido. | Nombre de la localidad. |
| `provincia` | `VARCHAR(100)` | NO |  |  | Provincia a la que pertenece la localidad. |

---

## 2. Tabla: `encargado_regional`

Responsable comercial de una localidad. Cada localidad tiene un único encargado regional (RN-02).

| Columna | Tipo | Nulo | Restricciones en 001 | Regla de negocio / Etapa 2 | Descripción |
| --- | --- | --- | --- | --- | --- |
| `identificador` | `INTEGER` | NO | PK, IDENTITY |  | Identificador interno del encargado. |
| `nombre` | `VARCHAR(100)` | NO |  |  | Nombre completo del encargado regional. |
| `codigo_postal_localidad` | `INTEGER` | NO | FK → `localidades(codigo_postal)`, `UNIQUE`; `ON DELETE RESTRICT`, `ON UPDATE CASCADE` | RN-02: una localidad tiene un solo encargado. | Localidad que tiene a cargo. |

**Nota:** `UNIQUE` impide más de un encargado por localidad. La obligación de que toda localidad tenga encargado se controla en Etapa 2.

---

## 3. Tabla: `sala_de_ventas`

Salas de venta distribuidas en las localidades.

| Columna | Tipo | Nulo | Restricciones en 001 | Regla de negocio / Etapa 2 | Descripción |
| --- | --- | --- | --- | --- | --- |
| `id_sala` | `INTEGER` | NO | PK, IDENTITY |  | Identificador único de la sala. |
| `calle` | `VARCHAR(100)` | NO |  |  | Calle de la ubicación. |
| `numero` | `INTEGER` | NO |  |  | Número de la dirección. |
| `dia_cierre` | `VARCHAR(20)` | NO |  | Etapa 2: `CHECK (dia_cierre IN ('Lunes','Martes','Miércoles','Jueves','Viernes','Sábado','Domingo'))`. | Día de cierre semanal. |
| `codigo_postal` | `INTEGER` | NO | FK → `localidades(codigo_postal)`; `ON DELETE RESTRICT`, `ON UPDATE CASCADE` | RN-02: una sala pertenece a una sola localidad. | Localidad donde se ubica la sala. |

---

## 4. Tabla: `empleado`

Empleados que trabajan en una sala de ventas.

| Columna | Tipo | Nulo | Restricciones en 001 | Regla de negocio / Etapa 2 | Descripción |
| --- | --- | --- | --- | --- | --- |
| `cuit` | `cuit_dom` | NO | PK |  | CUIT del empleado. |
| `nombre` | `VARCHAR(100)` | NO |  |  | Nombre completo. |
| `fecha_ingreso` | `DATE` | NO |  |  | Fecha de ingreso laboral. |
| `salario` | `NUMERIC(10,2)` | NO |  | Etapa 2: `CHECK (salario > 0)`. | Salario mensual. |
| `id_sala` | `INTEGER` | NO | FK → `sala_de_ventas(id_sala)`; `ON DELETE RESTRICT`, `ON UPDATE CASCADE` | RN-03: cada empleado trabaja en una sola sala. | Sala donde trabaja. |

---

## 5. Tabla: `bodega`

Bodegas elaboradoras de vino.

| Columna | Tipo | Nulo | Restricciones en 001 | Regla de negocio / Etapa 2 | Descripción |
| --- | --- | --- | --- | --- | --- |
| `cuit` | `cuit_dom` | NO | PK |  | CUIT de la bodega. |
| `nombre` | `VARCHAR(100)` | NO |  |  | Razón social o nombre comercial. |
| `calle` | `VARCHAR(100)` | NO |  |  | Calle del domicilio. |
| `num_calle` | `INTEGER` | NO |  |  | Número del domicilio. |

---

## 6. Tabla: `empresa_transporte`

Empresas que trasladan mercadería.

| Columna | Tipo | Nulo | Restricciones en 001 | Regla de negocio / Etapa 2 | Descripción |
| --- | --- | --- | --- | --- | --- |
| `cod_transporte` | `INTEGER` | NO | PK, IDENTITY |  | Identificador de la empresa. |
| `razon_social` | `VARCHAR(100)` | NO |  |  | Razón social. |
| `cuit` | `cuit_dom` | NO | `UNIQUE` |  | CUIT de la empresa. |
| `email` | `VARCHAR(100)` | NO |  |  | Correo electrónico de contacto. |
| `telefono` | `VARCHAR(20)` | NO |  |  | Teléfono de contacto. |
| `calle` | `VARCHAR(100)` | NO |  |  | Calle del domicilio. |
| `num_calle` | `INTEGER` | NO |  |  | Número del domicilio. |

---

## 7. Tabla: `transportista_de_localidad`

Relación N:M entre empresas de transporte y localidades cubiertas.

| Columna | Tipo | Nulo | Restricciones en 001 | Regla de negocio / Etapa 2 | Descripción |
| --- | --- | --- | --- | --- | --- |
| `codigo_postal` | `INTEGER` | NO | PK, FK → `localidades(codigo_postal)`; `ON DELETE CASCADE`, `ON UPDATE CASCADE` |  | Localidad cubierta. |
| `cod_transporte` | `INTEGER` | NO | PK, FK → `empresa_transporte(cod_transporte)`; `ON DELETE CASCADE`, `ON UPDATE CASCADE` |  | Empresa que presta el servicio. |

---

## 8. Tabla: `finca`

Fincas donde se cultiva la uva.

| Columna | Tipo | Nulo | Restricciones en 001 | Regla de negocio / Etapa 2 | Descripción |
| --- | --- | --- | --- | --- | --- |
| `id` | `INTEGER` | NO | PK, IDENTITY |  | Identificador de la finca. |
| `nombre` | `VARCHAR(100)` | NO |  |  | Nombre de la finca. |
| `superficie` | `NUMERIC(8,2)` | NO |  | Etapa 2: `CHECK (superficie > 0)`. | Superficie total en hectáreas. |
| `departamento` | `VARCHAR(100)` | NO |  |  | Departamento donde se ubica. |
| `provincia` | `VARCHAR(100)` | NO |  |  | Provincia donde se ubica. |

---

## 9. Tabla: `cepa`

Catálogo de cepas de uva.

| Columna | Tipo | Nulo | Restricciones en 001 | Regla de negocio / Etapa 2 | Descripción |
| --- | --- | --- | --- | --- | --- |
| `identificador` | `INTEGER` | NO | PK, IDENTITY |  | Identificador de la cepa. |
| `tipo` | `VARCHAR(10)` | NO |  | Etapa 2: `CHECK (tipo IN ('tinta','blanca'))`. | Tipo de cepa. |
| `nombre` | `VARCHAR(50)` | NO | `UNIQUE` |  | Nombre de la cepa, por ejemplo Malbec. |

---

## 10. Tabla: `parcelas`

Entidad débil de `finca`. Cada parcela pertenece a una finca y tiene una sola cepa.

| Columna | Tipo | Nulo | Restricciones en 001 | Regla de negocio / Etapa 2 | Descripción |
| --- | --- | --- | --- | --- | --- |
| `id_finca` | `INTEGER` | NO | PK, FK → `finca(id)`; `ON DELETE CASCADE`, `ON UPDATE CASCADE` |  | Finca a la que pertenece. |
| `identificador` | `INTEGER` | NO | PK |  | Número de parcela dentro de la finca. |
| `superficie` | `NUMERIC(8,2)` | NO |  | Etapa 2: `CHECK (superficie > 0)`. | Superficie en hectáreas. |
| `ano_plantacion` | `SMALLINT` | NO |  | Etapa 2: `CHECK (ano_plantacion > 0)`. | Año de plantación. |
| `id_cepa` | `INTEGER` | NO | FK → `cepa(identificador)`; `ON DELETE RESTRICT`, `ON UPDATE CASCADE` | RN-04: una parcela tiene una sola cepa. | Cepa implantada. |

---

## 11. Tabla: `lote_uva`

Cosecha de una parcela en una campaña. Una parcela se cosecha como máximo una vez por campaña (RN-04).

| Columna | Tipo | Nulo | Restricciones en 001 | Regla de negocio / Etapa 2 | Descripción |
| --- | --- | --- | --- | --- | --- |
| `num_lote` | `INTEGER` | NO | PK, IDENTITY |  | Identificador del lote de uva. |
| `fecha_cosecha` | `DATE` | NO |  |  | Fecha de cosecha. |
| `campania` | `SMALLINT` | NO | `UNIQUE (id_finca, id_parcela, campania)` | Etapa 2: `CHECK (campania > 0)`. | Año de cosecha. |
| `kilo_cosechado` | `NUMERIC(10,2)` | NO |  | Etapa 2: `CHECK (kilo_cosechado > 0)`. | Kilos cosechados. |
| `bodega_entrega` | `cuit_dom` | NO | FK → `bodega(cuit)`; `ON DELETE RESTRICT`, `ON UPDATE CASCADE` |  | Bodega destino. |
| `id_finca` | `INTEGER` | NO | Parte de FK compuesta |  | Parte 1 de la clave de parcela. |
| `id_parcela` | `INTEGER` | NO | Parte de FK compuesta |  | Parte 2 de la clave de parcela. |

**Clave foránea compuesta:** `(id_finca, id_parcela)` → `parcelas(id_finca, identificador)`, `ON DELETE RESTRICT`, `ON UPDATE CASCADE`.

---

## 12. Tabla: `analisis_calidad`

Análisis de calidad de un lote de uva.

| Columna | Tipo | Nulo | Restricciones en 001 | Regla de negocio / Etapa 2 | Descripción |
| --- | --- | --- | --- | --- | --- |
| `identificador` | `INTEGER` | NO | PK, IDENTITY |  | Identificador del análisis. |
| `fecha` | `DATE` | NO |  |  | Fecha de la muestra. |
| `brix` | `NUMERIC(5,2)` | NO |  | Etapa 2: `CHECK (brix > 0)`. | Grado de azúcar. |
| `ph` | `NUMERIC(3,2)` | NO |  | Etapa 2: `CHECK (ph > 0)`. | Nivel de acidez/alcalinidad. |
| `acidez_total` | `NUMERIC(5,2)` | NO |  | Etapa 2: `CHECK (acidez_total > 0)`. | Acidez total en g/L. |
| `num_lote` | `INTEGER` | NO | FK → `lote_uva(num_lote)`; `ON DELETE CASCADE`, `ON UPDATE CASCADE` |  | Lote analizado. |

---

## 13. Tabla: `vino`

Vinos elaborados por las bodegas.

| Columna | Tipo | Nulo | Restricciones en 001 | Regla de negocio / Etapa 2 | Descripción |
| --- | --- | --- | --- | --- | --- |
| `codigo` | `INTEGER` | NO | PK, IDENTITY |  | Identificador del vino. |
| `nombre` | `VARCHAR(100)` | NO |  |  | Nombre comercial. No se declara `UNIQUE` global porque puede repetirse entre bodegas. |
| `volumen` | `INTEGER` | NO |  | Etapa 2: `CHECK (volumen > 0)`. | Presentación en mililitros. |
| `precio` | `NUMERIC(10,2)` | NO |  | RN-01 / Etapa 2: `CHECK (precio > 0)`. | Precio único para todas las salas. |
| `graduacion` | `NUMERIC(4,2)` | NO |  | Etapa 2: `CHECK (graduacion BETWEEN 5 AND 20)`. | Graduación alcohólica. |
| `tipo` | `VARCHAR(20)` | NO |  | Etapa 2: `CHECK (tipo IN ('tinto','blanco','rosado','espumante'))`. | Tipo de vino. |
| `anada` | `SMALLINT` | NO |  | Etapa 2: `CHECK (anada > 0)`. | Año de cosecha. |
| `cuit_bodega` | `cuit_dom` | NO | FK → `bodega(cuit)`; `ON DELETE RESTRICT`, `ON UPDATE CASCADE` | RN-14. | Bodega que lo elabora. |

---

## 14. Tabla: `elaboracion_vino`

Composición de un vino a partir de una o más cepas.

| Columna | Tipo | Nulo | Restricciones en 001 | Regla de negocio / Etapa 2 | Descripción |
| --- | --- | --- | --- | --- | --- |
| `id_cepa` | `INTEGER` | NO | PK, FK → `cepa(identificador)`; `ON DELETE RESTRICT`, `ON UPDATE CASCADE` |  | Cepa que compone el vino. |
| `id_vino` | `INTEGER` | NO | PK, FK → `vino(codigo)`; `ON DELETE CASCADE`, `ON UPDATE CASCADE` |  | Vino elaborado. |
| `porcentaje` | `NUMERIC(5,2)` | NO |  | Etapa 2: `CHECK (porcentaje > 0 AND porcentaje <= 100)`. RN-05: los porcentajes por vino deben sumar 100 mediante constraint trigger diferido. | Porcentaje de la cepa en el vino. |

---

## 15. Tabla: `maridaje`

Catálogo de maridajes sugeridos.

| Columna | Tipo | Nulo | Restricciones en 001 | Regla de negocio / Etapa 2 | Descripción |
| --- | --- | --- | --- | --- | --- |
| `codigo` | `INTEGER` | NO | PK, IDENTITY |  | Identificador del maridaje. |
| `nombre` | `VARCHAR(100)` | NO | `UNIQUE` |  | Nombre del maridaje. |
| `temperatura` | `NUMERIC(4,2)` | NO |  |  | Temperatura sugerida en °C. |

---

## 16. Tabla: `vino_maridaje`

Relación N:M entre vinos y maridajes.

| Columna | Tipo | Nulo | Restricciones en 001 | Regla de negocio / Etapa 2 | Descripción |
| --- | --- | --- | --- | --- | --- |
| `cod_vino` | `INTEGER` | NO | PK, FK → `vino(codigo)`; `ON DELETE CASCADE`, `ON UPDATE CASCADE` |  | Vino recomendado. |
| `cod_maridaje` | `INTEGER` | NO | PK, FK → `maridaje(codigo)`; `ON DELETE RESTRICT`, `ON UPDATE CASCADE` |  | Maridaje asociado. |

---

## 17. Tabla: `clientes`

Supertipo de clientes. Los datos comunes se comparten entre socios, distribuidores y exportadores.

| Columna | Tipo | Nulo | Restricciones en 001 | Regla de negocio / Etapa 2 | Descripción |
| --- | --- | --- | --- | --- | --- |
| `id` | `INTEGER` | NO | PK, IDENTITY |  | Identificador del cliente. |
| `nombre` | `VARCHAR(100)` | NO |  |  | Nombre de la persona o nombre de fantasía. |
| `apellido` | `VARCHAR(100)` | SÍ |  |  | Apellido; nulo si es empresa. |
| `razon_social` | `VARCHAR(100)` | SÍ |  |  | Razón social; nula si es persona física. |
| `tipo_documento` | `VARCHAR(10)` | NO |  | Etapa 2: `CHECK (tipo_documento IN ('DNI','CUIT','Pasaporte'))`. | Tipo de documento. |
| `num_documento` | `VARCHAR(20)` | NO | `UNIQUE (tipo_documento, num_documento)` |  | Número de documento. |
| `fecha_alta` | `DATE` | NO |  | Etapa 2: `DEFAULT CURRENT_DATE`. | Fecha de alta en el sistema. |
| `direccion` | `VARCHAR(200)` | NO |  |  | Domicilio del cliente. |
| `descuento` | `NUMERIC(5,2)` | NO |  | RN-06 / Etapa 2: `CHECK (descuento IN (10,20,30))`. | Porcentaje de descuento base. |
| `codigo_postal` | `INTEGER` | NO | FK → `localidades(codigo_postal)`; `ON DELETE RESTRICT`, `ON UPDATE CASCADE` |  | Localidad del cliente. |

---

## 18. Tabla: `socio_club`

Subtipo de cliente socio del club.

| Columna | Tipo | Nulo | Restricciones en 001 | Regla de negocio / Etapa 2 | Descripción |
| --- | --- | --- | --- | --- | --- |
| `id` | `INTEGER` | NO | PK, FK → `clientes(id)`; `ON DELETE CASCADE`, `ON UPDATE CASCADE` |  | Hereda el identificador del cliente. |

---

## 19. Tabla: `distribuidores`

Subtipo de cliente distribuidor.

| Columna | Tipo | Nulo | Restricciones en 001 | Regla de negocio / Etapa 2 | Descripción |
| --- | --- | --- | --- | --- | --- |
| `id` | `INTEGER` | NO | PK, FK → `clientes(id)`; `ON DELETE CASCADE`, `ON UPDATE CASCADE` |  | Hereda el identificador del cliente. |
| `zona_cobertura` | `VARCHAR(100)` | NO |  |  | Zona de distribución. |
| `num_habilitacion` | `VARCHAR(50)` | NO |  |  | Número de habilitación comercial. |

---

## 20. Tabla: `exportadores`

Subtipo de cliente exportador.

| Columna | Tipo | Nulo | Restricciones en 001 | Regla de negocio / Etapa 2 | Descripción |
| --- | --- | --- | --- | --- | --- |
| `id` | `INTEGER` | NO | PK, FK → `clientes(id)`; `ON DELETE CASCADE`, `ON UPDATE CASCADE` |  | Hereda el identificador del cliente. |
| `pais_destino` | `VARCHAR(100)` | NO |  |  | País principal de exportación. |

---

## 21. Tabla: `permisos`

Permisos de exportación de cada exportador.

| Columna | Tipo | Nulo | Restricciones en 001 | Regla de negocio / Etapa 2 | Descripción |
| --- | --- | --- | --- | --- | --- |
| `codigo` | `VARCHAR(50)` | NO | PK |  | Código aduanero del permiso. |
| `fecha_emision` | `DATE` | NO |  |  | Fecha de emisión. |
| `fecha_vencimiento` | `DATE` | NO |  | RN-07 / Etapa 2: `CHECK (fecha_vencimiento > fecha_emision)`. | Fecha de vencimiento. |
| `id_exportador` | `INTEGER` | NO | FK → `exportadores(id)`; `ON DELETE CASCADE`, `ON UPDATE CASCADE` |  | Exportador titular. |

---

## 22. Tabla: `deposito_central`

Stock del depósito central. Existe un solo depósito central.

| Columna | Tipo | Nulo | Restricciones en 001 | Regla de negocio / Etapa 2 | Descripción |
| --- | --- | --- | --- | --- | --- |
| `codigo_vino` | `INTEGER` | NO | PK, FK → `vino(codigo)`; `ON DELETE RESTRICT`, `ON UPDATE CASCADE` |  | Vino almacenado. |
| `cantidad` | `INTEGER` | NO |  | RN-11 / Etapa 2: `CHECK (cantidad >= 0)`. | Botellas disponibles. |

---

## 23. Tabla: `deposito_sala`

Stock de cada vino en cada sala de ventas.

| Columna | Tipo | Nulo | Restricciones en 001 | Regla de negocio / Etapa 2 | Descripción |
| --- | --- | --- | --- | --- | --- |
| `id_sala` | `INTEGER` | NO | PK, FK → `sala_de_ventas(id_sala)`; `ON DELETE RESTRICT`, `ON UPDATE CASCADE` |  | Sala que posee el stock. |
| `cod_vino` | `INTEGER` | NO | PK, FK → `vino(codigo)`; `ON DELETE RESTRICT`, `ON UPDATE CASCADE` |  | Vino almacenado. |
| `cantidad` | `INTEGER` | NO |  | RN-09 / Etapa 2: `CHECK (cantidad >= 0)`. | Botellas disponibles. |

---

## 24. Tabla: `ingresos`

Cabecera de ingresos de mercadería al depósito central.

| Columna | Tipo | Nulo | Restricciones en 001 | Regla de negocio / Etapa 2 | Descripción |
| --- | --- | --- | --- | --- | --- |
| `codigo` | `INTEGER` | NO | PK, IDENTITY |  | Número de ingreso. |
| `fecha` | `DATE` | NO |  | Etapa 2: `DEFAULT CURRENT_DATE`. | Fecha de generación. |
| `estado` | `estado_documento` | NO |  | RN-10 / Etapa 2: `DEFAULT 'en_confeccion'`; trigger de estados. | Estado del ingreso. |
| `cuit_bodega` | `cuit_dom` | NO | FK → `bodega(cuit)`; `ON DELETE RESTRICT`, `ON UPDATE CASCADE` |  | Bodega de origen. |
| `cod_transporte` | `INTEGER` | NO | FK → `empresa_transporte(cod_transporte)`; `ON DELETE RESTRICT`, `ON UPDATE CASCADE` |  | Empresa que traslada la mercadería. |

---

## 25. Tabla: `detalle_ingreso`

Renglones de un ingreso.

| Columna | Tipo | Nulo | Restricciones en 001 | Regla de negocio / Etapa 2 | Descripción |
| --- | --- | --- | --- | --- | --- |
| `num_ingreso` | `INTEGER` | NO | PK, FK → `ingresos(codigo)`; `ON DELETE CASCADE`, `ON UPDATE CASCADE` |  | Cabecera del ingreso. |
| `cod_vino` | `INTEGER` | NO | PK, FK → `vino(codigo)`; `ON DELETE RESTRICT`, `ON UPDATE CASCADE` |  | Vino ingresado. |
| `cantidad` | `INTEGER` | NO |  | Etapa 2: `CHECK (cantidad > 0)`. | Botellas ingresadas. |

---

## 26. Tabla: `transferencias`

Solicitudes de vino desde una sala al depósito central.

| Columna | Tipo | Nulo | Restricciones en 001 | Regla de negocio / Etapa 2 | Descripción |
| --- | --- | --- | --- | --- | --- |
| `num_solicitud` | `INTEGER` | NO | PK, IDENTITY |  | Número de solicitud. |
| `fecha_confeccion` | `DATE` | NO |  | RN-11 / Etapa 2: `DEFAULT CURRENT_DATE`; no modificable. | Fecha de confección. |
| `estado` | `estado_documento` | NO |  | RN-11 / Etapa 2: `DEFAULT 'en_confeccion'`; trigger de estados. | Estado de la transferencia. |
| `id_sala` | `INTEGER` | NO | FK → `sala_de_ventas(id_sala)`; `ON DELETE RESTRICT`, `ON UPDATE CASCADE` |  | Sala solicitante. |

---

## 27. Tabla: `contenido_transferencia`

Renglones de una transferencia.

| Columna | Tipo | Nulo | Restricciones en 001 | Regla de negocio / Etapa 2 | Descripción |
| --- | --- | --- | --- | --- | --- |
| `num_transferencia` | `INTEGER` | NO | PK, FK → `transferencias(num_solicitud)`; `ON DELETE CASCADE`, `ON UPDATE CASCADE` |  | Cabecera de la transferencia. |
| `cod_vino` | `INTEGER` | NO | PK, FK → `vino(codigo)`; `ON DELETE RESTRICT`, `ON UPDATE CASCADE` |  | Vino solicitado. |
| `cantidad` | `INTEGER` | NO |  | Etapa 2: `CHECK (cantidad > 0)`. | Botellas solicitadas. |

---

## 28. Tabla: `comprobante`

Cabecera de ventas realizadas en las salas.

| Columna | Tipo | Nulo | Restricciones en 001 | Regla de negocio / Etapa 2 | Descripción |
| --- | --- | --- | --- | --- | --- |
| `numero` | `INTEGER` | NO | PK, IDENTITY |  | Número de ticket o factura. |
| `fecha` | `DATE` | NO |  | Etapa 2: `DEFAULT CURRENT_DATE`. | Fecha de la venta. |
| `subtotal` | `NUMERIC(12,2)` | NO |  | RN-08 / Etapa 2: `CHECK (subtotal >= 0)`; calculado por trigger. | Suma de renglones sin descuento. |
| `descuento` | `NUMERIC(12,2)` | NO |  | RN-08 / Etapa 2: `CHECK (descuento >= 0)`; calculado por trigger. | Monto total descontado. |
| `total` | `NUMERIC(12,2)` | NO |  | RN-08 / Etapa 2: `CHECK (total >= 0)`; calculado por trigger. | Monto final a pagar. |
| `id_sala` | `INTEGER` | NO | FK → `sala_de_ventas(id_sala)`; `ON DELETE RESTRICT`, `ON UPDATE CASCADE` |  | Sala donde se vendió. |
| `id_cliente` | `INTEGER` | NO | FK → `clientes(id)`; `ON DELETE RESTRICT`, `ON UPDATE CASCADE` |  | Cliente que realizó la compra. |

**Nota de normalización:** `subtotal`, `descuento` y `total` son columnas materializadas por RN-08. Constituyen una desnormalización controlada; se recalculan con trigger para evitar inconsistencias.

---

## 29. Tabla: `detalle_comprobante`

Renglones de un comprobante.

| Columna | Tipo | Nulo | Restricciones en 001 | Regla de negocio / Etapa 2 | Descripción |
| --- | --- | --- | --- | --- | --- |
| `cod_comprobante` | `INTEGER` | NO | PK, FK → `comprobante(numero)`; `ON DELETE CASCADE`, `ON UPDATE CASCADE` |  | Cabecera del comprobante. |
| `cod_vino` | `INTEGER` | NO | PK, FK → `vino(codigo)`; `ON DELETE RESTRICT`, `ON UPDATE CASCADE` |  | Vino vendido. |
| `cantidad` | `INTEGER` | NO |  | Etapa 2: `CHECK (cantidad > 0)`. | Botellas vendidas. |
| `precio_unit` | `NUMERIC(10,2)` | NO |  | Etapa 2: `CHECK (precio_unit > 0)`. | Precio congelado al momento de la venta. |
| `descuento` | `NUMERIC(10,2)` | NO |  | Etapa 2: `CHECK (descuento >= 0)`. | Descuento del renglón. |
| `subtotal` | `NUMERIC(12,2)` | NO |  | RN-08 / Etapa 2: `CHECK (subtotal >= 0)`; calculado por trigger como `cantidad * precio_unit - descuento`. | Subtotal del renglón. |

**Nota de normalización:** `subtotal` es una columna materializada por RN-08. Es una desnormalización controlada; se recalcula con trigger.

---

## 30. Tabla: `auditoria_precio`

Historial de cambios de precio de los vinos (RN-13).

| Columna | Tipo | Nulo | Restricciones en 001 | Regla de negocio / Etapa 2 | Descripción |
| --- | --- | --- | --- | --- | --- |
| `id` | `INTEGER` | NO | PK, IDENTITY |  | Identificador del registro de auditoría. |
| `precio_anterior` | `NUMERIC(10,2)` | NO |  |  | Precio antes del cambio. |
| `precio_nuevo` | `NUMERIC(10,2)` | NO |  |  | Precio después del cambio. |
| `fecha` | `DATE` | NO |  | Etapa 2: `DEFAULT CURRENT_DATE`. | Fecha del cambio. |
| `hora` | `TIME` | NO |  | Etapa 2: `DEFAULT CURRENT_TIME`. | Hora del cambio. |
| `usuario` | `VARCHAR(50)` | NO |  | Etapa 2: `DEFAULT CURRENT_USER`. | Usuario que ejecutó el cambio. |
| `id_vino` | `INTEGER` | NO | FK → `vino(codigo)`; `ON DELETE CASCADE`, `ON UPDATE CASCADE` | RN-13: alta automática mediante trigger `AFTER UPDATE` en `vino`. | Vino modificado. |

---

## Dependencias funcionales y normalización

### Primera Forma Normal (1FN)

Todas las columnas contienen valores atómicos y no existen grupos repetitivos. Las relaciones N:M se resolvieron con tablas intermedias:

- `transportista_de_localidad`
- `elaboracion_vino`
- `vino_maridaje`
- `deposito_sala`
- `detalle_ingreso`
- `contenido_transferencia`
- `detalle_comprobante`

### Segunda Forma Normal (2FN)

En las tablas con claves primarias compuestas, todos los atributos no clave dependen de la clave completa:

- `parcelas`: `(id_finca, identificador)` determina `superficie`, `ano_plantacion` e `id_cepa`.
- `lote_uva`: `num_lote` es clave simple; además `(id_finca, id_parcela, campania)` es clave candidata.
- `detalle_ingreso`: `(num_ingreso, cod_vino)` determina `cantidad`.
- `contenido_transferencia`: `(num_transferencia, cod_vino)` determina `cantidad`.
- `detalle_comprobante`: `(cod_comprobante, cod_vino)` determina `cantidad`, `precio_unit`, `descuento` y `subtotal`.
- `deposito_sala`: `(id_sala, cod_vino)` determina `cantidad`.
- `elaboracion_vino`: `(id_cepa, id_vino)` determina `porcentaje`.
- `vino_maridaje` y `transportista_de_localidad`: todos sus atributos forman parte de la clave.

No se detectan dependencias parciales.

### Tercera Forma Normal (3FN)

Las dependencias funcionales relevantes son:

- `localidades`: `codigo_postal → nombre, provincia`.
- `encargado_regional`: `identificador → nombre, codigo_postal_localidad`; además `codigo_postal_localidad` es clave candidata por `UNIQUE`.
- `sala_de_ventas`: `id_sala → calle, numero, dia_cierre, codigo_postal`.
- `empleado`: `cuit → nombre, fecha_ingreso, salario, id_sala`.
- `bodega`: `cuit → nombre, calle, num_calle`.
- `empresa_transporte`: `cod_transporte → razon_social, cuit, email, telefono, calle, num_calle`; `cuit` es clave candidata por `UNIQUE`.
- `finca`: `id → nombre, superficie, departamento, provincia`.
- `cepa`: `identificador → tipo, nombre`; `nombre` es clave candidata por `UNIQUE`.
- `parcelas`: `(id_finca, identificador) → superficie, ano_plantacion, id_cepa`.
- `lote_uva`: `num_lote → fecha_cosecha, campania, kilo_cosechado, bodega_entrega, id_finca, id_parcela`; `(id_finca, id_parcela, campania)` es clave candidata.
- `analisis_calidad`: `identificador → fecha, brix, ph, acidez_total, num_lote`.
- `vino`: `codigo → nombre, volumen, precio, graduacion, tipo, anada, cuit_bodega`.
- `maridaje`: `codigo → nombre, temperatura`.
- `clientes`: `id → nombre, apellido, razon_social, tipo_documento, num_documento, fecha_alta, direccion, descuento, codigo_postal`; `(tipo_documento, num_documento)` es clave candidata.
- `permisos`: `codigo → fecha_emision, fecha_vencimiento, id_exportador`.
- `comprobante`: `numero → fecha, subtotal, descuento, total, id_sala, id_cliente`.
- `detalle_comprobante`: `(cod_comprobante, cod_vino) → cantidad, precio_unit, descuento, subtotal`.
- `auditoria_precio`: `id → precio_anterior, precio_nuevo, fecha, hora, usuario, id_vino`.

No hay dependencias transitivas entre atributos no clave en las relaciones base. Las excepciones son las columnas materializadas de totales, justificadas por RN-08:

- `comprobante.total` se deriva de `subtotal` y `descuento`.
- `detalle_comprobante.subtotal` se deriva de `cantidad`, `precio_unit` y `descuento`.

Estas columnas son una **desnormalización controlada** para cumplir con el cálculo por trigger exigido por RN-08. Si se exigiera 3FN pura, deberían eliminarse y calcularse en vistas o funciones.

### Observaciones sobre dependencias

- En `finca` se almacenan `departamento` y `provincia`. No se declara `departamento → provincia` porque los nombres de departamento pueden repetirse entre provincias. Si el negocio definiera que el nombre del departamento es único, habría que crear una tabla `departamento` y reemplazar ambos atributos por una FK.
- En `lote_uva`, si se interpreta `fecha_cosecha → campania` (la campaña es el año de cosecha), no se viola 3FN porque `campania` es un atributo primo que forma parte de `UNIQUE (id_finca, id_parcela, campania)`. Sería una dependencia que impide BCNF, pero no 3FN.

**Conclusión:** el esquema está en 3FN para los datos base, con la excepción documentada de los importes materializados por RN-08.

---

## Decisiones de diseño

### Jerarquía de clientes

Se usa un supertipo `clientes` y tres subtipos (`socio_club`, `distribuidores`, `exportadores`) con herencia 1:1 mediante PK/FK. Esto evita columnas nulas masivas y permite que cada subtipo tenga sus atributos propios.

### Claves naturales y sustitutas

- Se usan claves sustitutas (`IDENTITY`) en entidades con datos cambiantes o nombres no garantizados como únicos: salas, fincas, parcelas, lotes, vinos, clientes, comprobantes, ingresos y transferencias.
- Se usan claves naturales donde el código es estable y significativo: `cuit` en bodegas y empleados, `codigo_postal` en localidades, `codigo` en permisos.

### Tipos de datos

- Los importes y porcentajes usan `NUMERIC`, nunca `FLOAT`.
- Los estados usan el tipo enumerado `estado_documento`.
- Los CUIT usan el dominio `cuit_dom`, que valida exactamente 11 dígitos numéricos.
- Las fechas usan `DATE` y las horas `TIME`.

### Acciones referenciales

- `ON DELETE CASCADE` se usa en relaciones de composición o dependencia fuerte: parcelas de una finca, renglones de un comprobante, renglones de un ingreso o transferencia, subtipos de cliente, permisos de un exportador y auditoría de un vino.
- `ON DELETE RESTRICT` se usa para proteger catálogos y datos con movimientos: bodegas, cepas, vinos, salas, localidades, clientes y transportistas.
- `ON UPDATE CASCADE` se usa en claves naturales que podrían corregirse.

### Atributos derivados

Se materializan `subtotal`, `descuento` y `total` en `comprobante`, y `subtotal` en `detalle_comprobante`, para cumplir RN-08 y evitar recalcular agregados en cada consulta. La consistencia se garantiza con triggers.

---

## Reglas de negocio y mecanismos previstos

| Regla | Descripción | Mecanismo |
| --- | --- | --- |
| RN-01 | El precio del vino es único para todas las salas y mayor que cero. | Atributo `vino.precio` + `CHECK (precio > 0)`. |
| RN-02 | Una sala pertenece a una localidad y cada localidad tiene un único encargado regional. | FK `sala_de_ventas.codigo_postal` + `UNIQUE` en `encargado_regional.codigo_postal_localidad`. |
| RN-03 | Cada empleado trabaja en una sola sala. | FK `empleado.id_sala` `NOT NULL`. |
| RN-04 | Una parcela tiene una sola cepa y se cosecha como máximo una vez por campaña. | FK `parcelas.id_cepa` + `UNIQUE (id_finca, id_parcela, campania)`. |
| RN-05 | Los porcentajes de corte de un vino suman 100. | Constraint trigger diferido sobre `elaboracion_vino`. |
| RN-06 | El descuento depende del tipo de cliente: socio 10%, distribuidor 20%, exportador 30%. | Función de descuento + `CHECK (descuento IN (10,20,30))`. |
| RN-07 | Un exportador puede tener varios permisos y el vencimiento es posterior a la emisión. | Tabla `permisos` + `CHECK (fecha_vencimiento > fecha_emision)`. |
| RN-08 | El total del comprobante es la suma de sus renglones con el descuento aplicado. | Función de cálculo + trigger `AFTER INSERT/UPDATE/DELETE` en `detalle_comprobante`. |
| RN-09 | No se puede vender más de lo que hay en stock y el stock nunca es negativo. | Trigger `BEFORE INSERT` + `CHECK (cantidad >= 0)`. |
| RN-10 | Solo un ingreso terminado impacta en el depósito y pasa a procesado; no se retrocede. | Tipo ENUM + trigger de estados + procedimiento. |
| RN-11 | Igual que RN-10 para transferencias; la fecha de confección es la actual y no se modifica. | ENUM + trigger de estados/fecha + procedimiento. |
| RN-12 | Un ingreso o transferencia que no está en confección no admite agregar, modificar ni quitar renglones. | Triggers sobre renglones. |
| RN-13 | Todo cambio de precio de un vino queda auditado. | Trigger `AFTER UPDATE` en `vino` + tabla `auditoria_precio`. |
| RN-14 | No se puede borrar un transportista, una bodega ni un vino con movimientos asociados. | FKs con `ON DELETE RESTRICT`. |
| RN-15 | Cantidades, superficies, kilos y precios son positivos; la graduación está entre 5 y 20. | `CHECK` en las columnas correspondientes. |

---

## Pendientes para la Etapa 2

- Implementar los `CHECK`, `UNIQUE`, `DEFAULT` y acciones referenciales marcados como **Etapa 2**.
- Implementar las funciones `fn_total_comprobante`, `fn_stock_sala`, `fn_descuento_cliente` y `fn_antiguedad_anios`.
- Implementar los procedimientos `sp_procesar_ingreso` y `sp_procesar_transferencia`.
- Implementar los triggers de stock, totales, estados, bloqueo de renglones, fecha de transferencia, auditoría de precio y suma de porcentajes.
- Implementar las vistas de stock, ventas mensuales y documentos pendientes.
- Implementar roles y privilegios.
