# 🔍 DIAGNÓSTICO: Problema de Colocación de Órdenes en XM

## 📋 Resumen del Problema

**Síntoma:** El EA funciona correctamente en Multibank (coloca órdenes y luego lanza alertas), pero en XM solo lanza alertas sin colocar órdenes.

**Comportamiento Esperado:** Debería funcionar en ambos brokers de la misma manera.

---

## 🔎 Análisis del Código Actual

### Problemas Identificados

#### 1. **❌ FALTA CONFIGURACIÓN DE TIPO DE LLENADO (FILLING)**
**Ubicación:** Línea 428 - Solo se configura el Magic Number

**Problema:**
- El código NO configura el tipo de llenado (`SetTypeFilling()`) en la clase `CTrade`
- Diferentes brokers requieren diferentes tipos de llenado:
  - **Multibank**: Probablemente acepta `FILLING_RETURN` (llenado parcial permitido)
  - **XM**: Requiere `FILLING_FOK` (Fill or Kill) o `FILLING_IOC` (Immediate or Cancel)
- Sin esta configuración, XM rechaza las órdenes silenciosamente

**Código Actual:**
```428:428:Dejavu.mq5
trade.SetExpertMagicNumber(MAGICN);
```

**Falta:**
- Detección automática del tipo de llenado soportado por el broker
- Configuración del tipo de llenado en CTrade

---

#### 2. **❌ VALIDACIÓN INSUFICIENTE DE DISTANCIAS MÍNIMAS**
**Ubicación:** Líneas 1501-1549 - Colocación de órdenes

**Problema:**
- La función `RevisarStops()` (línea 1394) valida los stops mínimos al inicio
- PERO no valida las distancias mínimas en el momento de colocar cada orden
- Los precios de SL/TP se calculan dinámicamente y pueden violar los requisitos del broker
- XM es más estricto que Multibank en validaciones de distancias

**Ejemplo del Problema:**
```1504:1504:Dejavu.mq5
if(!trade.SellStop(lot, NormalizeDouble(ultimoPrecioBid, _Digits), _Symbol, NormalizeDouble(ultimoPrecioAsk + (slinverso * Point()), _Digits), NormalizeDouble(ultimoPrecioAsk - tpValue, _Digits), 0, 0, "5"))
```

- No se valida que la distancia entre `ultimoPrecioBid` y el SL/TP cumpla con `SYMBOL_TRADE_STOPS_LEVEL`
- No se valida que la distancia entre precio de orden y precio actual cumpla con `SYMBOL_TRADE_FREEZE_LEVEL`

---

#### 3. **❌ MANEJO DE ERRORES INSUFICIENTE**
**Ubicación:** Líneas 1506, 1515, 1538, 1547

**Problema:**
- Solo imprime el código de error genérico con `GetLastError()`
- No interpreta el error específico ni proporciona información útil
- No intenta corregir errores comunes (ej: distancia mínima, tipo de llenado)

**Código Actual:**
```1506:1506:Dejavu.mq5
Print("Error placing SELLSTOP order: ", GetLastError());
```

**Falta:**
- Interpretación de códigos de error específicos
- Mensajes descriptivos que ayuden a diagnosticar
- Reintentos con correcciones automáticas

---

#### 4. **❌ FALTA VALIDACIÓN DE PRECIOS DE ÓRDENES PENDIENTES**
**Ubicación:** Líneas 1501-1549

**Problema:**
- No se valida que el precio de la orden pendiente esté dentro del rango permitido
- No se verifica `SYMBOL_TRADE_FREEZE_LEVEL` (distancia mínima del precio actual)
- XM puede rechazar órdenes que están demasiado cerca del precio actual

**Ejemplo:**
- Para `SellStop`: El precio debe estar por debajo del precio actual
- Para `BuyStop`: El precio debe estar por encima del precio actual
- La distancia mínima debe cumplir con `SYMBOL_TRADE_FREEZE_LEVEL`

---

#### 5. **❌ NO SE VALIDA EL TIPO DE LLENADO DISPONIBLE**
**Ubicación:** OnInit() - Falta completamente

**Problema:**
- No se detecta qué tipos de llenado soporta el broker
- No se configura automáticamente el mejor tipo disponible
- Esto causa que las órdenes fallen en brokers estrictos como XM

---

## 🎯 Causa Raíz Principal

**El problema principal es la falta de configuración del tipo de llenado (FILLING) en CTrade.**

XM requiere que se especifique explícitamente el tipo de llenado, mientras que Multibank puede aceptar órdenes sin esta configuración (usa un valor por defecto).

**Secundariamente**, XM es más estricto en validaciones de distancias mínimas, lo que puede causar rechazos adicionales.

---

## 📊 Comparación de Comportamiento

| Aspecto | Multibank | XM |
|---------|-----------|-----|
| Tipo de Llenado | Acepta valor por defecto | Requiere configuración explícita |
| Validación de Distancias | Más permisivo | Más estricto |
| Manejo de Errores | Más tolerante | Rechaza inmediatamente |
| Alertas | Se lanzan después de órdenes | Se lanzan antes (en RevisarMaxOp) |

---

## 🔧 Impacto en el Código

### Funciones Afectadas:
1. `OnInit()` - Falta configuración de CTrade
2. `ColocarOrdenesIniciales()` - Falta validación de distancias
3. `ReponerOrdenes()` - Mismo problema al reponer órdenes
4. Todas las llamadas a `trade.SellStop()`, `trade.BuyLimit()`, etc.

### Líneas Críticas:
- **428**: Configuración de CTrade (falta SetTypeFilling)
- **1501-1549**: Colocación de órdenes (falta validación)
- **1630-1711**: Reposición de órdenes (mismo problema)

---

## ✅ Soluciones Requeridas

1. **Configurar tipo de llenado automáticamente** según el broker
2. **Validar distancias mínimas** antes de cada orden
3. **Mejorar manejo de errores** con mensajes descriptivos
4. **Validar precios de órdenes pendientes** contra requisitos del broker
5. **Agregar logging detallado** para diagnóstico

---

## 📝 Notas Adicionales

- El código actual tiene buena estructura general
- La validación de stops mínimos existe pero es insuficiente
- El problema es específico de compatibilidad entre brokers
- La solución debe ser robusta y funcionar en múltiples brokers

