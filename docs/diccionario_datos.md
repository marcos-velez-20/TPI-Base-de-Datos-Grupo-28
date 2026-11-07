Trabajo Práctico Integrador: Bodegas del Atuel - Etapa 1

Integrantes: Dalma Monardi,Matias Gonzalez,Marcos Velez, Facundo Zinik

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
- Los nombres de tablas y columnas de este diccionario son los del DDL (`001_esquema.sql`). Las equivalencias con los nombres conceptuales del DER y del esquema relacional están en el Apéndice A.

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

Responsable comercial de una localidad. Es una **entidad débil** de `localidades`: no tiene identificador propio y se identifica por la localidad que tiene a cargo. Cada localidad tiene un único encargado regional (RN-02).

| Columna | Tipo | Nulo | Restricciones en 001 | Regla de negocio / Etapa 2 | Descripción |
| --- | --- | --- | --- | --- | --- |
| `codigo_postal_localidad` | `INTEGER` | NO | PK, FK → `localidades(codigo_postal)`; `ON DELETE RESTRICT`, `ON UPDATE CASCADE` | RN-02: una localidad tiene un solo encargado. | Localidad que tiene a cargo. Identifica al encargado. |
| `nombre` | `VARCHAR(100)` | NO |  |  | Nombre completo del encargado regional. |

**Notas:**

- Al ser la FK parte de la PK, la base de datos ya impide más de un encargado por localidad.
- El DDL declara además `UNIQUE (codigo_postal_localidad)`. Es redundante, porque toda PK ya es única, y puede eliminarse sin cambiar el comportamiento.
- La obligación de que toda localidad tenga encargado (cardinalidad (1,1) del DER) no se puede forzar solo con el DDL base; se controla en Etapa 2.

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
| `razon_social` | `VARCHAR(100)` | NO |  |  | Razón social de la bodega. |
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

Entidad débil de `finca`. Cada parcela pertenece a una finca y tiene una sola cepa. Su número (`identificador`) es único solo dentro de la finca; por eso la PK es compuesta.

| Columna | Tipo | Nulo | Restricciones en 001 | Regla de negocio / Etapa 2 | Descripción |
| --- | --- | --- | --- | --- | --- |
| `id_finca` | `INTEGER` | NO | PK, FK → `finca(id)`; `ON DELETE CASCADE`, `ON UPDATE CASCADE` |  | Finca a la que pertenece. |
| `identificador` | `INTEGER` | NO | PK (no es `IDENTITY`) |  | Número de parcela dentro de la finca (clave parcial). |
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
| `id` | `INTEGER` | NO | PK, IDENTITY |  | Identificador del vino. |
| `nombre` | `VARCHAR(100)` | NO |  |  | Nombre comercial. No se declara `UNIQUE` global porque puede repetirse entre bodegas. |
| `volumen` | `INTEGER` | NO |  | Etapa 2: `CHECK (volumen > 0)`. | Presentación en mililitros. |
| `precio` | `NUMERIC(10,2)` | NO |  | RN-01 / Etapa 2: `CHECK (precio > 0)`. | Precio único para todas las salas. |
| `graduacion` | `NUMERIC(4,2)` | NO |  | Etapa 2: `CHECK (graduacion BETWEEN 5 AND 20)`. | Graduación alcohólica. |
| `tipo` | `VARCHAR(20)` | NO |  | Etapa 2: `CHECK (tipo IN ('tinto','blanco','rosado','espumante'))`. | Tipo de vino. |
| `anada` | `SMALLINT` | NO |  | Etapa 2: `CHECK (anada > 0)`. | Año de cosecha. |
| `cuit_bodega` | `cuit_dom` | NO | FK → `bodega(cuit)`; `ON DELETE RESTRICT`, `ON UPDATE CASCADE` | RN-14. | Bodega que lo elabora. |

---

## 14. Tabla: `elaboracion_vino`

Composición (corte) de un vino a partir de una o más cepas. Es la relación N:M `compone` del DER (en el esquema relacional figura como `Composicion`).

| Columna | Tipo | Nulo | Restricciones en 001 | Regla de negocio / Etapa 2 | Descripción |
| --- | --- | --- | --- | --- | --- |
| `id_cepa` | `INTEGER` | NO | PK, FK → `cepa(identificador)`; `ON DELETE RESTRICT`, `ON UPDATE CASCADE` |  | Cepa que compone el vino. |
| `id_vino` | `INTEGER` | NO | PK, FK → `vino(id)`; `ON DELETE CASCADE`, `ON UPDATE CASCADE` |  | Vino elaborado. |
| `porcentaje` | `NUMERIC(5,2)` | NO |  | Etapa 2: `CHECK (porcentaje > 0 AND porcentaje <= 100)`. RN-05: los porcentajes por vino deben sumar 100 mediante constraint trigger diferido. | Porcentaje de la cepa en el vino. |

---

## 15. Tabla: `maridaje`

Catálogo de maridajes sugeridos.

| Columna | Tipo | Nulo | Restricciones en 001 | Regla de negocio / Etapa 2 | Descripción |
| --- | --- | --- | --- | --- | --- |
| `id` | `INTEGER` | NO | PK, IDENTITY |  | Identificador del maridaje. |
| `nombre` | `VARCHAR(100)` | NO | `UNIQUE` |  | Nombre del maridaje. |
| `temperatura` | `NUMERIC(4,2)` | NO |  |  | Temperatura sugerida en °C. |

---

## 16. Tabla: `vino_maridaje`

Relación N:M entre vinos y maridajes.

| Columna | Tipo | Nulo | Restricciones en 001 | Regla de negocio / Etapa 2 | Descripción |
| --- | --- | --- | --- | --- | --- |
| `cod_vino` | `INTEGER` | NO | PK, FK → `vino(id)`; `ON DELETE CASCADE`, `ON UPDATE CASCADE` |  | Vino recomendado. |
| `cod_maridaje` | `INTEGER` | NO | PK, FK → `maridaje(id)`; `ON DELETE RESTRICT`, `ON UPDATE CASCADE` |  | Maridaje asociado. |

---

## 17. Tabla: `clientes`

Supertipo de clientes. Contiene únicamente los datos comunes a socios, distribuidores y exportadores. Los datos propios de cada tipo (nombre y apellido, razón social, etc.) están en las tablas de los subtipos.

| Columna | Tipo | Nulo | Restricciones en 001 | Regla de negocio / Etapa 2 | Descripción |
| --- | --- | --- | --- | --- | --- |
| `id` | `INTEGER` | NO | PK, IDENTITY |  | Identificador del cliente. |
| `tipoCliente` | `VARCHAR(100)` | NO |  | Etapa 2 (sugerido): `CHECK (tipoCliente IN ('socio','distribuidor','exportador'))` y trigger que verifique que coincida con el subtipo en el que existe el `id`. | Discriminador de la jerarquía: indica a qué subtipo pertenece el cliente. |
| `tipo_documento` | `VARCHAR(10)` | NO |  | Etapa 2: `CHECK (tipo_documento IN ('DNI','CUIT','Pasaporte'))`. | Tipo de documento. |
| `num_documento` | `VARCHAR(20)` | NO | `UNIQUE (tipo_documento, num_documento)` |  | Número de documento. |
| `fecha_alta` | `DATE` | NO |  | Etapa 2: `DEFAULT CURRENT_DATE`. | Fecha de alta en el sistema. |
| `calle` | `VARCHAR(200)` | NO |  |  | Calle del domicilio. |
| `numeroCalle` | `VARCHAR(200)` | NO |  |  | Número del domicilio (texto, admite valores como "S/N" o "1250 bis"). |
| `descuento` | `NUMERIC(5,2)` | NO |  | RN-06 / Etapa 2: `CHECK (descuento IN (10,20,30))`. | Porcentaje de descuento base del cliente. |
| `codigo_postal` | `INTEGER` | NO | FK → `localidades(codigo_postal)`; `ON DELETE RESTRICT`, `ON UPDATE CASCADE` |  | Localidad del cliente. |

**Notas:**

- El domicilio se guarda atomizado en `calle` y `numeroCalle` (atributo compuesto `direccion` del DER), igual que en `bodega`, `empresa_transporte` y `sala_de_ventas`.
- `tipoCliente` y `descuento` mantienen una dependencia entre atributos no clave; ver la excepción documentada en la sección de normalización.

---

## 18. Tabla: `socio_club`

Subtipo de cliente socio del club (persona física).

| Columna | Tipo | Nulo | Restricciones en 001 | Regla de negocio / Etapa 2 | Descripción |
| --- | --- | --- | --- | --- | --- |
| `id` | `INTEGER` | NO | PK, FK → `clientes(id)`; `ON DELETE CASCADE`, `ON UPDATE CASCADE` |  | Hereda el identificador del cliente. |
| `nombre` | `VARCHAR(100)` | NO |  |  | Nombre del socio. |
| `apellido` | `VARCHAR(100)` | NO |  |  | Apellido del socio. |

---

## 19. Tabla: `distribuidores`

Subtipo de cliente distribuidor.

| Columna | Tipo | Nulo | Restricciones en 001 | Regla de negocio / Etapa 2 | Descripción |
| --- | --- | --- | --- | --- | --- |
| `id` | `INTEGER` | NO | PK, FK → `clientes(id)`; `ON DELETE CASCADE`, `ON UPDATE CASCADE` |  | Hereda el identificador del cliente. |
| `zona_cobertura` | `VARCHAR(100)` | NO |  |  | Zona de distribución. |
| `num_habilitacion` | `VARCHAR(50)` | NO |  |  | Número de habilitación comercial. |
| `razonSocial` | `VARCHAR(100)` | NO |  |  | Razón social del distribuidor. |

---

## 20. Tabla: `exportadores`

Subtipo de cliente exportador.

| Columna | Tipo | Nulo | Restricciones en 001 | Regla de negocio / Etapa 2 | Descripción |
| --- | --- | --- | --- | --- | --- |
| `id` | `INTEGER` | NO | PK, FK → `clientes(id)`; `ON DELETE CASCADE`, `ON UPDATE CASCADE` |  | Hereda el identificador del cliente. |
| `pais_destino` | `VARCHAR(100)` | NO |  |  | País principal de exportación. |
| `razonSocial` | `VARCHAR(100)` | NO |  |  | Razón social del exportador. |

---

## 21. Tabla: `permisos`

Permisos de exportación de cada exportador.

| Columna | Tipo | Nulo | Restricciones en 001 | Regla de negocio / Etapa 2 | Descripción |
| --- | --- | --- | --- | --- | --- |
| `id` | `VARCHAR(50)` | NO | PK |  | Código aduanero del permiso. |
| `fecha_emision` | `DATE` | NO |  |  | Fecha de emisión. |
| `fecha_vencimiento` | `DATE` | NO |  | RN-07 / Etapa 2: `CHECK (fecha_vencimiento > fecha_emision)`. | Fecha de vencimiento. |
| `id_exportador` | `INTEGER` | NO | FK → `exportadores(id)`; `ON DELETE CASCADE`, `ON UPDATE CASCADE` |  | Exportador titular. |

---

## 22. Tabla: `stock_central`

Stock del depósito central. Existe un solo depósito central, por lo que no hace falta una tabla de depósitos: el stock se identifica solo por el vino. Es una entidad débil de `vino` en el DER.

| Columna | Tipo | Nulo | Restricciones en 001 | Regla de negocio / Etapa 2 | Descripción |
| --- | --- | --- | --- | --- | --- |
| `codigo_vino` | `INTEGER` | NO | PK, FK → `vino(id)`; `ON DELETE RESTRICT`, `ON UPDATE CASCADE` |  | Vino almacenado. |
| `cantidad` | `INTEGER` | NO |  | RN-09 / Etapa 2: `CHECK (cantidad >= 0)`. | Botellas disponibles. |

---

## 23. Tabla: `stock_sala`

Stock de cada vino en cada sala de ventas (relación N:M `posee` entre sala y vino).

| Columna | Tipo | Nulo | Restricciones en 001 | Regla de negocio / Etapa 2 | Descripción |
| --- | --- | --- | --- | --- | --- |
| `id_sala` | `INTEGER` | NO | PK, FK → `sala_de_ventas(id_sala)`; `ON DELETE RESTRICT`, `ON UPDATE CASCADE` |  | Sala que posee el stock. |
| `cod_vino` | `INTEGER` | NO | PK, FK → `vino(id)`; `ON DELETE RESTRICT`, `ON UPDATE CASCADE` |  | Vino almacenado. |
| `cantidad` | `INTEGER` | NO |  | RN-09 / Etapa 2: `CHECK (cantidad >= 0)`. | Botellas disponibles. |

---

## 24. Tabla: `ingresos`

Cabecera de ingresos de mercadería al depósito central.

| Columna | Tipo | Nulo | Restricciones en 001 | Regla de negocio / Etapa 2 | Descripción |
| --- | --- | --- | --- | --- | --- |
| `id` | `INTEGER` | NO | PK, IDENTITY |  | Número de ingreso. |
| `fecha` | `DATE` | NO |  | Etapa 2: `DEFAULT CURRENT_DATE`. | Fecha de generación. |
| `estado` | `estado_documento` | NO |  | RN-10 / Etapa 2: `DEFAULT 'en_confeccion'`; trigger de estados. | Estado del ingreso. |
| `cuit_bodega` | `cuit_dom` | NO | FK → `bodega(cuit)`; `ON DELETE RESTRICT`, `ON UPDATE CASCADE` |  | Bodega de origen. |
| `cod_transporte` | `INTEGER` | NO | FK → `empresa_transporte(cod_transporte)`; `ON DELETE RESTRICT`, `ON UPDATE CASCADE` |  | Empresa que traslada la mercadería. |

---

## 25. Tabla: `detalle_ingreso`

Renglones de un ingreso.

| Columna | Tipo | Nulo | Restricciones en 001 | Regla de negocio / Etapa 2 | Descripción |
| --- | --- | --- | --- | --- | --- |
| `num_ingreso` | `INTEGER` | NO | PK, FK → `ingresos(id)`; `ON DELETE CASCADE`, `ON UPDATE CASCADE` |  | Cabecera del ingreso. |
| `cod_vino` | `INTEGER` | NO | PK, FK → `vino(id)`; `ON DELETE RESTRICT`, `ON UPDATE CASCADE` |  | Vino ingresado. |
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

## 27. Tabla: `detalle_transferencia`

Renglones de una transferencia (relación `contiene` del DER).

| Columna | Tipo | Nulo | Restricciones en 001 | Regla de negocio / Etapa 2 | Descripción |
| --- | --- | --- | --- | --- | --- |
| `num_transferencia` | `INTEGER` | NO | PK, FK → `transferencias(num_solicitud)`; `ON DELETE CASCADE`, `ON UPDATE CASCADE` |  | Cabecera de la transferencia. |
| `cod_vino` | `INTEGER` | NO | PK, FK → `vino(id)`; `ON DELETE RESTRICT`, `ON UPDATE CASCADE` |  | Vino solicitado. |
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

**Nota de normalización:** `subtotal`, `descuento` y `total` son atributos derivados (en el DER figuran como atributos derivados, con línea punteada, en `Comprobante`). El DDL los materializa por RN-08 como desnormalización controlada y se recalculan con trigger.

---

## 29. Tabla: `detalle_comprobante`

Renglones de un comprobante (relación `incluye` del DER).

| Columna | Tipo | Nulo | Restricciones en 001 | Regla de negocio / Etapa 2 | Descripción |
| --- | --- | --- | --- | --- | --- |
| `cod_comprobante` | `INTEGER` | NO | PK, FK → `comprobante(numero)`; `ON DELETE CASCADE`, `ON UPDATE CASCADE` |  | Cabecera del comprobante. |
| `cod_vino` | `INTEGER` | NO | PK, FK → `vino(id)`; `ON DELETE RESTRICT`, `ON UPDATE CASCADE` |  | Vino vendido. |
| `cantidad` | `INTEGER` | NO |  | Etapa 2: `CHECK (cantidad > 0)`. | Botellas vendidas. |
| `precio_unit` | `NUMERIC(10,2)` | NO |  | Etapa 2: `CHECK (precio_unit > 0)`. | Precio congelado al momento de la venta. |
| `descuento` | `NUMERIC(10,2)` | NO |  | Etapa 2: `CHECK (descuento >= 0)`. | Descuento del renglón. |
| `subtotal` | `NUMERIC(12,2)` | NO |  | RN-08 / Etapa 2: `CHECK (subtotal >= 0)`; calculado por trigger como `cantidad * precio_unit - descuento`. | Subtotal del renglón. |

**Nota de normalización:** `subtotal` es una columna materializada por RN-08 (atributo derivado en el DER). Es una desnormalización controlada; se recalcula con trigger.

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
| `id_vino` | `INTEGER` | NO | FK → `vino(id)`; `ON DELETE CASCADE`, `ON UPDATE CASCADE` | RN-13: alta automática mediante trigger `AFTER UPDATE` en `vino`. | Vino modificado. |

---

## Dependencias funcionales y normalización

### Criterio aplicado

- **1FN:** todos los atributos son atómicos, no hay grupos repetitivos y cada tabla tiene clave primaria.
- **2FN:** está en 1FN y ningún atributo no clave depende de solo una parte de una clave compuesta.
- **3FN:** está en 2FN y, para toda dependencia funcional `X → A`, se cumple que `X` es superclave o `A` es un atributo primo (forma parte de alguna clave candidata). En la práctica: ningún atributo no clave depende de otro atributo no clave.

### Primera Forma Normal (1FN)

Todas las columnas contienen valores atómicos y no existen grupos repetitivos:

- Los domicilios se dividen en calle y número (`calle`/`num_calle` o `calle`/`numero` o `calle`/`numeroCalle`), en lugar de un único texto de dirección.
- Las personas se separan en `nombre` y `apellido` (`socio_club`).
- Los atributos multivaluados se llevan a tablas propias: los permisos de un exportador (`permisos`), los análisis de un lote (`analisis_calidad`), las localidades que cubre un transportista (`transportista_de_localidad`) y las cepas de un vino (`elaboracion_vino`).

Las relaciones N:M se resolvieron con tablas intermedias:

- `transportista_de_localidad`
- `elaboracion_vino`
- `vino_maridaje`
- `stock_sala`
- `detalle_ingreso`
- `detalle_transferencia`
- `detalle_comprobante`

### Segunda Forma Normal (2FN)

Las tablas con clave simple cumplen 2FN de forma automática, porque una dependencia parcial requiere una clave compuesta. En las tablas con clave primaria compuesta, todos los atributos no clave dependen de la clave completa:

- `parcelas`: `(id_finca, identificador)` determina `superficie`, `ano_plantacion` e `id_cepa`. El número de parcela no identifica nada por sí solo (se repite entre fincas), por lo que ningún atributo depende solo de `identificador` ni solo de `id_finca`.
- `detalle_ingreso`: `(num_ingreso, cod_vino)` determina `cantidad`.
- `detalle_transferencia`: `(num_transferencia, cod_vino)` determina `cantidad`.
- `detalle_comprobante`: `(cod_comprobante, cod_vino)` determina `cantidad`, `precio_unit`, `descuento` y `subtotal`.
- `stock_sala`: `(id_sala, cod_vino)` determina `cantidad`.
- `elaboracion_vino`: `(id_cepa, id_vino)` determina `porcentaje`.
- `vino_maridaje` y `transportista_de_localidad`: todos sus atributos forman parte de la clave.
- `lote_uva`: tiene clave simple `num_lote`; `(id_finca, id_parcela, campania)` es clave candidata y los demás atributos dependen de ella completa.
- `encargado_regional` y `stock_central`: su clave es simple (la FK identificadora), aunque se trate de entidades débiles.

No se detectan dependencias parciales.

### Tercera Forma Normal (3FN)

Dependencias funcionales relevantes de cada relación:

- `localidades`: `codigo_postal → nombre, provincia`.
- `encargado_regional`: `codigo_postal_localidad → nombre`.
- `sala_de_ventas`: `id_sala → calle, numero, dia_cierre, codigo_postal`.
- `empleado`: `cuit → nombre, fecha_ingreso, salario, id_sala`.
- `bodega`: `cuit → razon_social, calle, num_calle`.
- `empresa_transporte`: `cod_transporte → razon_social, cuit, email, telefono, calle, num_calle`; `cuit` es clave candidata por `UNIQUE`.
- `finca`: `id → nombre, superficie, departamento, provincia`.
- `cepa`: `identificador → tipo, nombre`; `nombre` es clave candidata por `UNIQUE`.
- `parcelas`: `(id_finca, identificador) → superficie, ano_plantacion, id_cepa`.
- `lote_uva`: `num_lote → fecha_cosecha, campania, kilo_cosechado, bodega_entrega, id_finca, id_parcela`; `(id_finca, id_parcela, campania)` es clave candidata.
- `analisis_calidad`: `identificador → fecha, brix, ph, acidez_total, num_lote`.
- `vino`: `id → nombre, volumen, precio, graduacion, tipo, anada, cuit_bodega`.
- `elaboracion_vino`: `(id_cepa, id_vino) → porcentaje`.
- `maridaje`: `id → nombre, temperatura`; `nombre` es clave candidata por `UNIQUE`.
- `clientes`: `id → tipoCliente, tipo_documento, num_documento, fecha_alta, calle, numeroCalle, descuento, codigo_postal`; `(tipo_documento, num_documento)` es clave candidata.
- `socio_club`: `id → nombre, apellido`.
- `distribuidores`: `id → zona_cobertura, num_habilitacion, razonSocial`.
- `exportadores`: `id → pais_destino, razonSocial`.
- `permisos`: `id → fecha_emision, fecha_vencimiento, id_exportador`.
- `stock_central`: `codigo_vino → cantidad`.
- `stock_sala`: `(id_sala, cod_vino) → cantidad`.
- `ingresos`: `id → fecha, estado, cuit_bodega, cod_transporte`.
- `detalle_ingreso`: `(num_ingreso, cod_vino) → cantidad`.
- `transferencias`: `num_solicitud → fecha_confeccion, estado, id_sala`.
- `detalle_transferencia`: `(num_transferencia, cod_vino) → cantidad`.
- `comprobante`: `numero → fecha, subtotal, descuento, total, id_sala, id_cliente`.
- `detalle_comprobante`: `(cod_comprobante, cod_vino) → cantidad, precio_unit, descuento, subtotal`.
- `auditoria_precio`: `id → precio_anterior, precio_nuevo, fecha, hora, usuario, id_vino`.

#### Por qué el diseño evita dependencias transitivas

La 3FN se logra porque los datos descriptivos de una entidad se guardan **una sola vez**, en su propia tabla, y las demás tablas la referencian solo con su clave. Si se copiaran, aparecería una dependencia transitiva (`id → clave_ajena → dato_copiado`).

| Dato descriptivo | Se guarda solo en | Las demás tablas guardan únicamente |
| --- | --- | --- |
| Nombre y provincia de la localidad | `localidades` | `codigo_postal` (en `sala_de_ventas`, `clientes`, `encargado_regional`, `transportista_de_localidad`) |
| Razón social y domicilio de la bodega | `bodega` | `cuit` (en `vino`, `lote_uva`, `ingresos`) |
| Razón social, contacto y domicilio del transportista | `empresa_transporte` | `cod_transporte` (en `ingresos`, `transportista_de_localidad`) |
| Nombre, tipo, precio vigente, graduación y añada del vino | `vino` | `id` (en `stock_*`, `detalle_*`, `elaboracion_vino`, `vino_maridaje`, `auditoria_precio`) |
| Tipo y nombre de la cepa | `cepa` | `identificador` (en `parcelas`, `elaboracion_vino`) |
| Nombre, superficie y ubicación de la finca | `finca` | `id_finca` (en `parcelas`) |
| Nombre y temperatura del maridaje | `maridaje` | `id` (en `vino_maridaje`) |
| Datos de la sala (dirección, día de cierre) | `sala_de_ventas` | `id_sala` (en `empleado`, `stock_sala`, `transferencias`, `comprobante`) |
| Datos del cliente | `clientes` y su subtipo | `id` (en `comprobante`) |

Otras decisiones que sostienen la 3FN:

- **La cepa de un lote no se guarda en `lote_uva`.** Se obtiene a través de la parcela (`lote_uva → parcela → id_cepa`). Guardarla en el lote crearía una dependencia transitiva.
- **La jerarquía de clientes está dividida.** Nombre y apellido solo existen para socios (`socio_club`), y razón social solo para distribuidores y exportadores. Si estuvieran todos en `clientes` habría columnas nulas según el tipo y dependencias que solo valen para algunas filas.
- **`precio_unit` en `detalle_comprobante` no es una dependencia transitiva.** `vino.precio` es el precio *vigente* y cambia con el tiempo (RN-13). En cambio, `precio_unit` es el precio *al momento de la venta* y depende de la clave completa `(cod_comprobante, cod_vino)`. Son dos hechos distintos, no una copia.
- **`auditoria_precio` guarda datos históricos propios** (`precio_anterior`, `precio_nuevo`). Son hechos del evento de cambio, identificados por `id`, no una repetición del precio actual del vino.
- **Los estados usan un tipo enumerado** (`estado_documento`) en lugar de una tabla de estados con atributos propios, porque el estado no tiene atributos descriptivos adicionales.

#### Excepciones documentadas (desnormalización controlada)

Estas dependencias entre atributos no clave existen a propósito. Si se exigiera 3FN pura, deberían eliminarse y calcularse en vistas o funciones.

1. **`comprobante.total`** se deriva de `subtotal` y `descuento` (`{subtotal, descuento} → total`). Además, `subtotal` y `descuento` resumen los renglones de `detalle_comprobante`.
2. **`detalle_comprobante.subtotal`** se deriva de `cantidad`, `precio_unit` y `descuento` (`{cantidad, precio_unit, descuento} → subtotal`).
3. **`clientes.descuento`** depende de `tipoCliente` por RN-06 (socio 10%, distribuidor 20%, exportador 30%). Como `id → tipoCliente`, resulta `id → descuento` de forma transitiva (`id → tipoCliente → descuento`).

Las tres son el atributo derivado o redundante que muestran el DER y el esquema relacional, y se mantienen consistentes por trigger/`CHECK` (RN-06 y RN-08). Para el caso 3, la alternativa en 3FN pura sería una tabla `tipo_cliente(tipo PK, descuento)` referenciada desde `clientes`, o calcular el descuento con una función a partir de `tipoCliente`.

### Observaciones sobre dependencias

- En `finca` se almacenan `departamento` y `provincia`. No se declara `departamento → provincia` porque los nombres de departamento pueden repetirse entre provincias. Si el negocio definiera que el nombre del departamento es único, habría que crear una tabla `departamento` y reemplazar ambos atributos por una FK.
- En `lote_uva`, si se interpreta `fecha_cosecha → campania` (la campaña es el año de cosecha), no se viola 3FN porque `campania` es un atributo primo que forma parte de `UNIQUE (id_finca, id_parcela, campania)`. Sería una dependencia que impide BCNF, pero no 3FN.
- En `clientes`, `tipoCliente` es redundante con la pertenencia a un subtipo (un `id` aparece en `socio_club`, `distribuidores` o `exportadores`). Se conserva como discriminador para poder validar la jerarquía con `CHECK`/trigger y para consultar el tipo sin hacer `JOIN`.
- La clave `(tipo_documento, num_documento)` de `clientes` es candidata; todos los demás atributos dependen de ella y de `id`, por lo que no hay violación de BCNF.

**Conclusión:** el esquema está en 3FN para los datos base. Las excepciones son los importes materializados por RN-08 (`comprobante.total`, `detalle_comprobante.subtotal`) y el descuento por tipo de cliente de RN-06 (`clientes.descuento`), documentadas arriba como desnormalización controlada.

---

## Decisiones de diseño

### Jerarquía de clientes

Se usa un supertipo `clientes` y tres subtipos (`socio_club`, `distribuidores`, `exportadores`) con herencia 1:1 mediante PK/FK. El supertipo guarda lo común (documento, alta, domicilio, descuento, localidad) y el discriminador `tipoCliente`. Cada subtipo guarda sus atributos propios: `nombre` y `apellido` en socios; `zona_cobertura`, `num_habilitacion` y `razonSocial` en distribuidores; `pais_destino` y `razonSocial` en exportadores. Esto evita columnas nulas masivas y mantiene cada dato en la tabla a la que pertenece.

### Entidades débiles

- `parcelas` depende de `finca`: su clave es `(id_finca, identificador)` y el número de parcela se numera dentro de cada finca (no es `IDENTITY`).
- `encargado_regional` depende de `localidades`: su clave es la FK a la localidad.
- `stock_central` depende de `vino`: su clave es la FK al vino.

### Claves naturales y sustitutas

- Se usan claves sustitutas (`IDENTITY`) en entidades con datos cambiantes o nombres no garantizados como únicos: salas, fincas, lotes, vinos, clientes, comprobantes, ingresos y transferencias.
- Se usan claves naturales donde el código es estable y significativo: `cuit` en bodegas y empleados, `codigo_postal` en localidades, `id` (código aduanero) en permisos.
- En las entidades débiles la clave se forma con la clave de la entidad fuerte (`parcelas`, `encargado_regional`, `stock_central`).

### Domicilios atómicos

Todos los domicilios se guardan en dos columnas (calle y número). Así se cumple 1FN y se permite buscar o filtrar por calle sin procesar texto.

### Tipos de datos

- Los importes y porcentajes usan `NUMERIC`, nunca `FLOAT`.
- Los estados usan el tipo enumerado `estado_documento`.
- Los CUIT usan el dominio `cuit_dom`, que valida exactamente 11 dígitos numéricos.
- Las fechas usan `DATE` y las horas `TIME`.

### Acciones referenciales

- `ON UPDATE CASCADE` se aplica en todas las claves foráneas, de modo que una corrección de clave se propague.
- `ON DELETE CASCADE` se usa en relaciones de composición o dependencia fuerte: parcelas de una finca, análisis de un lote, renglones de un comprobante, ingreso o transferencia, subtipos de cliente, permisos de un exportador, composición y maridajes de un vino, cobertura de localidades de un transportista y auditoría de un vino.
- `ON DELETE RESTRICT` se usa para proteger catálogos y datos con movimientos: bodegas, cepas, vinos en renglones y stock, salas, localidades, encargados regionales, clientes y transportistas en ingresos.

### Atributos derivados

Se materializan `subtotal`, `descuento` y `total` en `comprobante`, y `subtotal` en `detalle_comprobante`, para cumplir RN-08 y evitar recalcular agregados en cada consulta. La consistencia se garantiza con triggers.

### Observaciones de coherencia del DDL

- Algunas columnas del DDL usan camelCase (`tipoCliente`, `numeroCalle`, `razonSocial`) mientras el resto usa snake_case. Como se crearon sin comillas, PostgreSQL las guarda en minúsculas (`tipocliente`, `numerocalle`, `razonsocial`). Se recomienda unificarlas a `tipo_cliente`, `numero_calle` y `razon_social`.
- `clientes.numeroCalle` es `VARCHAR(200)`, mientras que el número de domicilio en las demás tablas es `INTEGER`.
- `encargado_regional` declara `UNIQUE` sobre su propia PK (redundante).

---

## Reglas de negocio y mecanismos previstos

| Regla | Descripción | Mecanismo |
| --- | --- | --- |
| RN-01 | El precio del vino es único para todas las salas y mayor que cero. | Atributo `vino.precio` + `CHECK (precio > 0)`. |
| RN-02 | Una sala pertenece a una localidad y cada localidad tiene un único encargado regional. | FK `sala_de_ventas.codigo_postal` + PK de `encargado_regional` sobre `codigo_postal_localidad`. |
| RN-03 | Cada empleado trabaja en una sola sala. | FK `empleado.id_sala` `NOT NULL`. |
| RN-04 | Una parcela tiene una sola cepa y se cosecha como máximo una vez por campaña. | FK `parcelas.id_cepa` + `UNIQUE (id_finca, id_parcela, campania)`. |
| RN-05 | Los porcentajes de corte de un vino suman 100. | Constraint trigger diferido sobre `elaboracion_vino`. |
| RN-06 | El descuento depende del tipo de cliente: socio 10%, distribuidor 20%, exportador 30%. | Función de descuento + `CHECK (descuento IN (10,20,30))` + control de coherencia con `tipoCliente`. |
| RN-07 | Un exportador puede tener varios permisos y el vencimiento es posterior a la emisión. | Tabla `permisos` + `CHECK (fecha_vencimiento > fecha_emision)`. |
| RN-08 | El total del comprobante es la suma de sus renglones con el descuento aplicado. | Función de cálculo + trigger `AFTER INSERT/UPDATE/DELETE` en `detalle_comprobante`. |
| RN-09 | No se puede vender más de lo que hay en stock y el stock nunca es negativo. | Trigger `BEFORE INSERT` + `CHECK (cantidad >= 0)` en `stock_sala` y `stock_central`. |
| RN-10 | Solo un ingreso terminado impacta en el depósito y pasa a procesado; no se retrocede. | Tipo ENUM + trigger de estados + procedimiento. |
| RN-11 | Igual que RN-10 para transferencias; la fecha de confección es la actual y no se modifica. | ENUM + trigger de estados/fecha + procedimiento. |
| RN-12 | Un ingreso o transferencia que no está en confección no admite agregar, modificar ni quitar renglones. | Triggers sobre `detalle_ingreso` y `detalle_transferencia`. |
| RN-13 | Todo cambio de precio de un vino queda auditado. | Trigger `AFTER UPDATE` en `vino` + tabla `auditoria_precio`. |
| RN-14 | No se puede borrar un transportista, una bodega ni un vino con movimientos asociados. | FKs con `ON DELETE RESTRICT`. |
| RN-15 | Cantidades, superficies, kilos y precios son positivos; la graduación está entre 5 y 20. | `CHECK` en las columnas correspondientes. |

---

## Apéndice A. Equivalencias entre DER / esquema relacional y DDL

El DER y el esquema relacional usan nombres conceptuales. Este diccionario sigue los nombres del DDL.

| DER / esquema relacional | DDL (`001_esquema.sql`) |
| --- | --- |
| `Localidad` (`codigoPostal`) | `localidades` (`codigo_postal`) |
| `Sala de Ventas` (`id`) | `sala_de_ventas` (`id_sala`) |
| `Cepa.id` | `cepa.identificador` |
| `Parcela` (`idFinca`, `numero`) | `parcelas` (`id_finca`, `identificador`) |
| `Lote Uva.numero` | `lote_uva.num_lote` |
| `Analisis Calidad` (`id`, `acidez`, `numeroLote`) | `analisis_calidad` (`identificador`, `acidez_total`, `num_lote`) |
| `Vino.codigo` | `vino.id` |
| `Composicion` (`idCepa`, `codigoVino`) | `elaboracion_vino` (`id_cepa`, `id_vino`) |
| `Maridaje` / `Vino Maridaje` | `maridaje` / `vino_maridaje` (`cod_maridaje`) |
| `Empresa Transporte.codigo` | `empresa_transporte.cod_transporte` |
| `Ingreso.codigo` / `Detalle Ingreso.codigoIngreso` | `ingresos.id` / `detalle_ingreso.num_ingreso` |
| `Stock Central` / `Stock Sala` | `stock_central` / `stock_sala` |
| `Transferencia` / `Detalle Transferencia` | `transferencias` / `detalle_transferencia` |
| `Permiso.codigo` | `permisos.id` |
| `Detalle Comprobante.precio` | `detalle_comprobante.precio_unit` |
| `Cliente.direccion` (`calle`, `numero`) | `clientes.calle`, `clientes.numeroCalle` |
| `Socio`, `Distribuidor`, `Exportador` | `socio_club`, `distribuidores`, `exportadores` |
