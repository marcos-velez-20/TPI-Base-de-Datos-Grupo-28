# Bocetos de las pantallas (Etapa 7)

Borrador en texto de las 5 pantallas. Cada una muestra solo lo que devuelve la API: el front no calcula importes, descuentos ni stock. Los errores de las reglas de la base se muestran tal cual llegan, en un banner rojo.

Barra de navegación (todas las pantallas): `Catálogo | Nuevo vino | Nueva venta | Transferencias | Tablero`. Pie: estado de la API (`GET /salud`).

---

## 1. Catálogo de vinos (`/vinos`, detalle en `/vinos/:cod`)

```
+------------------------------------------------------------------+
| Tipo [v]  Cepa [v]  Bodega [v]  Añada [v]   [Buscar] [Limpiar]   |
| [+ Nuevo vino]                                                   |
+------------------------------------------------------------------+
| Nombre          Tipo    Añada  ml    Grad.  Precio  Bodega        |
| Malbec Reserva  tinto   2021   750   14.0   $ ...   Bodega X [Ver]|
| ...                                                              |
+------------------------------------------------------------------+
|  < Anterior    Página 1 de N · T resultados    Siguiente >       |
+------------------------------------------------------------------+
Detalle:  Composición: Malbec 80 % / Merlot 20 %
          Maridajes: Carnes rojas (17 °C) ...   [Editar]
```
- Datos: `GET /vinos` (filtros + paginación), `GET /vinos/{cod}`, catálogos `GET /cepas`, `/bodegas`, `/vinos/anadas`.
- Estados: cargando, sin resultados, error.

## 2. Alta y edición de vino (`/vinos/nuevo`, `/vinos/:cod/editar`)

```
+------------------------------------------------------------------+
| [ banner de error de la API, si hay ]                            |
| Nombre [______]  Tipo [v]  Añada [____]  Volumen ml [v]          |
| Graduación [__]  Precio [____]  Bodega [v]                       |
|                                                                  |
| Composición:   Cepa [v]  Porcentaje [__]  [x quitar]             |
|                Cepa [v]  Porcentaje [__]  [x quitar]             |
|                [+ Agregar cepa]        (suma actual: 100, informativa)
| Maridajes: [x] Carnes rojas  [ ] Postres ...                     |
|                                      [Guardar] [Cancelar]        |
+------------------------------------------------------------------+
```
- Datos: `POST /vinos`, `PUT /vinos/{cod}`, `GET /vinos/{cod}` (precarga), `DELETE /vinos/{cod}`.
- Si los porcentajes no suman 100 (RN-05), el front envía igual y muestra el mensaje de la base.

## 3. Nueva venta (`/ventas/nueva`)

```
+------------------------------------------------------------------+
| Cliente [buscar por nombre...] [v]     Sala [v]                  |
| Vino [buscar...] [v]   Cantidad [__]   [Agregar]                 |
|                                                                  |
| Carrito:  Vino                     Cantidad                      |
|           Malbec Reserva 750       3          [quitar]           |
|                                          [Confirmar venta]       |
+------------------------------------------------------------------+
| Comprobante N° 123 - fecha - cliente - sala                      |
| Vino      Cant  P.unit  Desc.  Subtotal      (valores de la API) |
| Subtotal / Descuento / TOTAL                 (valores de la API) |
|                                          [Nueva venta]           |
+------------------------------------------------------------------+
```
- Datos: `GET /clientes?nombre=`, `GET /salas`, `GET /vinos`, `POST /comprobantes`.
- El carrito solo guarda `{ cod_vino, cantidad }`, sin precios ni totales.
- Sin stock: banner con el mensaje de la regla RN-09 (409) y el carrito se conserva.

## 4. Transferencias (`/transferencias`, detalle en `/transferencias/:nro`)

```
+------------------------------------------------------------------+
| Estado [v]  Sala [v]            Nueva transferencia: Sala [v] [Crear]
+------------------------------------------------------------------+
| N°   Sala  Fecha confección  Estado          [Abrir]             |
| 12   3     2026-11-10        (en_confeccion)                     |
+------------------------------------------------------------------+
Detalle N° 12 - estado: en_confeccion
  Renglones:  Vino  Cantidad
  Agregar renglón: Vino [v] Cantidad [__] [Agregar]   (solo en_confeccion)
  [Terminar]  (en_confeccion)   [Procesar]  (terminado)   (ninguno si procesado)
```
- Datos: `GET /transferencias`, `GET /transferencias/{nro}` (el id es `num_solicitud`), `POST /transferencias`, `/renglones`, `/terminar`, `/procesar`.
- Tras cada acción se recarga desde la API. Stock insuficiente en el depósito: banner con el mensaje de la base.

## 5. Tablero (`/tablero`)

```
+------------------------------+-----------------------------------+
| Top 10 vinos más vendidos    | Ventas por sala (último trimestre)|
| #  Vino          Botellas    |  ▇▇▇                              |
| 1  ...           ...         |  ▇▇▇▇▇  (gráfico de barras)       |
+------------------------------+-----------------------------------+
| Vinos sin stock en la sala: Sala [v]                             |
| Vino            Stock en depósito                                |
+------------------------------------------------------------------+
```
- Datos: `GET /reportes/top-vinos`, `GET /reportes/ventas-por-sala`, `GET /reportes/vinos-sin-stock?sala=`.
- Cada bloque tiene su propio estado de carga y error.
