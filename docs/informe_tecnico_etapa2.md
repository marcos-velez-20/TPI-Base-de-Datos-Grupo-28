**Informe Técnico – Etapa 2: Integridad Declarativa, Procedural y Concurrencia**

*TPI Base de Datos – Grupo 28 | Sistema de Gestión Vitivinícola «Bodegas del Atuel»*\
*Motor: PostgreSQL 16 (Contenerizado con Docker Compose)*

**1. Introducción y Arquitectura de Integridad en Tres Capas**

El propósito de la Etapa 2 consistió en trasladar y blindar la totalidad de las reglas de negocio y restricciones de consistencia del sistema vitivinícola directamente dentro del motor de base de datos PostgreSQL 16. La estrategia de diseño se estructuró en una jerarquía defensiva de tres niveles complementarios:

**• Capa 1 – Integridad Declarativa (Nivel Motor):** Dominios personalizados (e.g. cuit_dom validado mediante expresiones regulares), tipos de datos estructurados y restricciones CHECK y UNIQUE a nivel de tupla. Resuelven validaciones atómicas inmediatas y previenen inconsistencias de dominio en origen.

**• Capa 2 – Integridad Procedural y Auditoría (Nivel Lógica):** Procedimientos y funciones en PL/pgSQL que orquestan lógica reactiva. Comprende triggers BEFORE (para verificación de stock previo a ventas y cancelaciones), triggers AFTER (para trazabilidad y auditoría de precios) y un trigger diferido (CONSTRAINT TRIGGER DEFERRABLE INITIALLY DEFERRED) que evalúa la composición del 100% en cortes únicamente al invocar el COMMIT transaccional.

**• Capa 3 – Control Transaccional y Concurrencia (Nivel Operativo):** Procedimientos almacenados para transferencias de stock e ingresos con propiedades ACID garantizadas, complementados con bloqueos pesimistas de fila (SELECT ... FOR UPDATE) bajo el nivel de aislamiento READ COMMITTED para eliminar condiciones de carrera en ventas concurrentes de última unidad.

**2. Matriz de Trazabilidad Exhaustiva de Reglas de Negocio (RN-01 a RN-15)**

A continuación se presenta el mapeo técnico detallado que vincula cada requerimiento funcional con su implementación física en PostgreSQL y su respectivo caso de prueba validado en tests/db_tests.sql:

| **Regla** | **Descripción** | **Mecanismo en BD** | **Script / Objeto** | **Validación en db\_tests.sql** |
| --- | --- | --- | --- | --- |
| **RN-01** | Precios, montos y graduación alcohólica mayores a cero. | CHECK (precio > 0)<br>CHECK (graduacion >= 0) | 002_constraints.sql | Inserción con precio = -500.00 rechazada por check_violation. |
| **RN-02** | CUIT válido en bodegas y clientes corporativos. | Dominio cuit_dom con Regex<br>CHECK (VALUE ~ '^\[0-9]{11}$') | 001_esquema.sql<br>002_constraints.sql | Rechazo de CUIT con caracteres alfanuméricos o longitud <> 11 dígitos. |
| **RN-03** | Límite de capacidad en depósitos centrales y de salas. | Trigger BEFORE INSERT OR UPDATE sobre depósitos | fn_validar_capacidad_deposito()<br>005_triggers.sql | Excepción disparada al intentar ingresar stock superando el volumen máximo. |
| **RN-04** | Fechas de cosecha y añada coherentes temporalmente. | CHECK (anada >= 1900 AND anada <= EXTRACT(YEAR FROM CURRENT_DATE)) | 002_constraints.sql | Inserción con añada futura rechazada por restricción temporal. |
| **RN-05** | Suma de cortes de uva debe totalizar exactamente el 100%. | CONSTRAINT TRIGGER diferido<br>(DEFERRABLE INITIALLY DEFERRED) | fn_validar_corte_100()<br>005_triggers.sql | Transacción con 60% + 40% permite COMMIT; corte con 90% aborta al confirmar. |
| **RN-06** | Socio de club asociado a categoría válida con descuento asignado. | FOREIGN KEY referencial +<br>CHECK (descuento BETWEEN 0 AND 100) | 002_constraints.sql | Socio con categoría inexistente o descuento inválido (> 100%) rechazado. |
| **RN-07** | Fecha de vencimiento de permiso exportación posterior a emisión. | CHECK (fecha_vencimiento > fecha_emision) | 002_constraints.sql | Permiso con fecha de vencimiento anterior a emisión rechazado por el motor. |
| **RN-08** | Parcelas deben pertenecer a una finca registrada y activa. | FOREIGN KEY estricta<br>(ON DELETE RESTRICT) | 002_constraints.sql | Intento de asociar parcela a finca inexistente genera foreign_key_violation. |
| **RN-09** | Prohibición de emitir ventas sin stock disponible en sala. | Trigger BEFORE INSERT sobre detalle_comprobante | fn_descontar_stock_venta()<br>005_triggers.sql | Venta con cantidad mayor al disponible lanza RAISE EXCEPTION y aborta. |
| **RN-10** | Lotes de uva requieren análisis de calidad aprobado para vinificar. | Trigger BEFORE INSERT sobre elaboracion_vino | fn_validar_calidad_uva()<br>005_triggers.sql | Elaboración asociada a lote rechazado o pendiente aborta la operación. |
| **RN-11** | Descuento de stock atómico al asentar detalle del comprobante. | UPDATE transaccional dentro de fn_descontar_stock_venta() | 005_triggers.sql | Verificación de decremento inmediato de existencias tras INSERT del comprobante. |
| **RN-12** | Transferencias registradas con estado inicial y fecha de creación. | DEFAULT CURRENT_TIMESTAMP y tipo ENUM de estado | 001_esquema.sql<br>004_procedimientos.sql | sp_registrar_transferencia inicializa con estado 'pendiente' y timestamp exacto. |
| **RN-13** | Auditoría obligatoria ante cambios de precio en vinos. | Trigger AFTER UPDATE OF precio sobre tabla vino | fn_auditar_cambio_precio()<br>005_triggers.sql | Update de precio inserta registro inmutable en auditoria_precio (UPDATE 1 verificado). |
| **RN-14** | Control estricto de comprobantes y anulación no repetitiva. | Procedimiento almacenado sp_anular_comprobante() | 004_procedimientos.sql | Intento de anular comprobante ya cancelado lanza excepción; restituye stock si es válido. |
| **RN-15** | Cantidades transferidas o vendidas estrictamente enteras y positivas. | CHECK (cantidad > 0) en renglones de movimientos | 002_constraints.sql | Rechazo de registros con cantidad <= 0 en transferencias o detalles de venta. |

**3. Justificación de Mecanismos Técnicos Clave**

**3.1. Triggers Diferidos para la Regla de Cortes de Uva (RN-05)**

La regla de negocio RN-05 impone que la sumatoria de las proporciones de uvas que conforman un vino de corte debe ser idéntica a 100.00%. Si esta validación se hubiese configurado con un trigger convencional de ejecución inmediata (IMMEDIATE), la inserción del primer componente (por ejemplo, 60% de Malbec) fallaría instantáneamente debido a que la suma parcial aún no alcanza el total requerido.

**•** Decisión de diseño: Se implementó un CONSTRAINT TRIGGER definido como DEFERRABLE INITIALLY DEFERRED sobre la tabla elaboracion_vino/vino_cepa. Mediante este mecanismo, PostgreSQL permite registrar múltiples componentes dentro de un bloque transaccional (BEGIN...COMMIT), postergando la ejecución de la función fn_validar_corte_100() exactamente al momento de ejecutar el COMMIT. Si el acumulado es distinto de 100%, la transacción se rechaza de forma indivisible y ejecuta un ROLLBACK automático.

**3.2. Trazabilidad Inmutable de Precios (RN-13)**

Para cumplir con RN-13 sin depender de la confiabilidad de aplicaciones externas, se implementó un trigger AFTER UPDATE OF precio en la tabla vino. El mecanismo intercepta cualquier modificación de precios y extrae variables de contexto de sesión del motor: OLD.precio, NEW.precio, CURRENT_DATE, CURRENT_TIME y SESSION_USER. Esto asegura registros inalterables en auditoria_precio, permitiendo auditar con exactitud quién y cuándo efectuó cada alteración comercial.

**4. Demostración Experimental de Concurrencia (Anexo A.8)**

Se diseñó una experiencia de laboratorio transaccional sobre dos conexiones independientes conectadas vía SQL Shell a la base bodegas_del_atuel en el puerto 5433 del contenedor Docker. El objetivo consistió en evaluar el comportamiento ante la venta simultánea de la última botella en stock (deposito_sala.cantidad = 1) bajo el nivel de aislamiento estándar READ COMMITTED.

**4.1. Escenario A: Venta Concurrente sin Bloqueo Pesimista (Riesgo de Sobreventa)**

En una prueba sin cláusula FOR UPDATE, ambas terminales ejecutaron simultáneamente 'SELECT cantidad FROM deposito_sala WHERE id_sala=1 AND cod_vino=1' dentro de bloques BEGIN. Como READ COMMITTED no bloquea lecturas compartidas, ambas sesiones leyeron exitosamente cantidad = 1. Posteriormente, ambas emitieron la actualización 'UPDATE deposito_sala SET cantidad = cantidad - 1'. Este comportamiento deriva en un conflicto de Lost Update o sobreventa de stock, siendo detenido de manera reactiva por el constraint CHECK (cantidad >= 0), interrumpiendo el flujo operativo de una de las cajas de venta con un error no controlado.

**4.2. Escenario B: Venta Concurrente con Bloqueo Pesimista (SELECT ... FOR UPDATE)**

Para garantizar atomicidad y consistencia en el punto de venta, se ejecutó el procedimiento con bloqueo pesimista a nivel de tupla:

**1. Sesión 1 (Terminal Superior):** Inicia transacción y solicita bloqueo exclusivo de la fila: 'BEGIN; SELECT cantidad FROM deposito_sala WHERE id_sala = 1 AND cod_vino = 1 FOR UPDATE;'. El motor le otorga el bloqueo exclusivo de fila y retorna cantidad = 1.

**2. Sesión 2 (Terminal Inferior):** Ejecuta de manera concurrente exactamente la misma sentencia: 'BEGIN; SELECT cantidad ... FOR UPDATE;'. Al detectar el cerrojo activo en la tupla, el motor pone a la Sesión 2 en estado de espera activa (bloqueo transaccional), impidiendo lecturas sucias o decisiones con datos desactualizados.

**3. Sesión 1 (Confirmación):** Concreta la venta y libera los recursos: 'UPDATE deposito_sala SET cantidad = cantidad - 1 ...; COMMIT;'. Al confirmar, la cantidad en base pasa a 0 y el bloqueo se libera.

**4. Sesión 2 (Resolución Consistente):** La terminal se destraba automáticamente en el instante exacto del COMMIT de la Sesión 1. Bajo READ COMMITTED, PostgreSQL re-evalúa la tupla y devuelve cantidad = 0. Al constatar que el inventario se agotó, el flujo de negocio ejecuta limpiamente 'ROLLBACK;', evitando la sobreventa sin arrojar excepciones críticas ni dejar inconsistencias.

***Evidencia Gráfica del Experimento***

|  |
| --- |
| **Captura 1 – Demostración de Espera Activa por Bloqueo Pesimista:**
![Demostración de bloqueo concurrente con FOR UPDATE](img/concurrencia_bloqueo.png.jpeg)<br>Se observa en la ventana superior la Sesión 1 con la fila bloqueada (FOR UPDATE) retornando cantidad = 1. En la ventana inferior, la Sesión 2 ejecuta la misma consulta y queda suspendida en la consola a la espera de la liberación del candado.<br>
**Captura 2 – Resolución Transaccional y Prevención de Sobreventa:** 
![Resolución transaccional y prevención de sobreventa](img/concurrencia_resolucion.png.jpeg) La Sesión 1 descuenta la unidad y ejecuta COMMIT. En ese mismo instante la Sesión 2 se desbloquea automáticamente, lee el stock actualizado (cantidad = 0) y ejecuta ROLLBACK de forma consistente.|
|
**5. Estado del Entorno y Transición a la Etapa 3**

El entorno de desarrollo ha quedado completamente desacoplado de dependencias locales mediante Docker Compose en el puerto 5433, alojando las 30 tablas del modelo relacional con sus restricciones activas. La totalidad de los casos de prueba unitarios en tests/db_tests.sql han arrojado resultados satisfactorios tanto en flujos de éxito como en captura de excepciones esperadas.
