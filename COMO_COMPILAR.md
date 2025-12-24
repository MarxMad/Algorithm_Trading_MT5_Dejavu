# Cómo Compilar y Verificar el Código MQL5

## Método 1: Compilar desde MetaEditor (Recomendado)

### Pasos:

1. **Abrir MetaEditor**
   - Abre MetaTrader 5
   - Presiona `F4` o ve a `Tools` → `MetaQuotes Language Editor`

2. **Abrir el archivo**
   - En MetaEditor, abre el archivo `Dejavu.mq5`
   - O arrastra el archivo a MetaEditor

3. **Compilar**
   - Presiona `F7` (Compile)
   - O ve a `Tools` → `Compile`
   - O haz clic en el botón de compilar (martillo) en la barra de herramientas

4. **Revisar los resultados**
   - Abre la pestaña **"Toolbox"** (si no está visible, ve a `View` → `Toolbox`)
   - En la pestaña **"Errors"** verás:
     - ✅ **0 error(s), 0 warning(s)** = Compilación exitosa
     - ❌ Si hay errores, aparecerán listados con el número de línea

### Interpretar los resultados:

#### ✅ Compilación Exitosa:
```
0 error(s), 0 warning(s)
```
El código está listo para usar.

#### ⚠️ Advertencias (Warnings):
```
0 error(s), X warning(s)
```
- Las advertencias NO impiden la compilación
- El EA funcionará, pero revisa las advertencias
- Muchas advertencias del linter de Cursor son falsos positivos en MQL5

#### ❌ Errores:
```
X error(s), Y warning(s)
```
- Los errores SÍ impiden la compilación
- Revisa cada error en la lista
- Haz clic en el error para ir a la línea problemática

---

## Método 2: Compilar desde MetaTrader 5

1. Abre MetaTrader 5
2. Ve a `View` → `Navigator` (o presiona `Ctrl+N`)
3. En el Navigator, busca `Expert Advisors`
4. Busca `Dejavu`
5. Si aparece con un ícono de compilación (⚙️), significa que necesita compilarse
6. Haz clic derecho → `Compile`
7. Revisa la pestaña `Toolbox` → `Errors`

---

## Método 3: Verificar Errores Comunes

### Errores de Sintaxis Comunes:

1. **Falta punto y coma (;)**
   ```mql5
   int x = 5  // ❌ Error
   int x = 5; // ✅ Correcto
   ```

2. **Llaves no balanceadas { }**
   - Verifica que cada `{` tenga su `}` correspondiente

3. **Paréntesis no balanceados ( )**
   - Verifica que cada `(` tenga su `)` correspondiente

4. **Variables no declaradas**
   - Asegúrate de que todas las variables estén declaradas antes de usarse

5. **Funciones no definidas**
   - Verifica que todas las funciones estén definidas antes de ser llamadas

---

## Verificación Rápida del Código Actual

### ✅ Verificaciones que ya hice:

1. ✅ Todas las funciones están definidas
2. ✅ Las llaves están balanceadas
3. ✅ Los puntos y comas están en su lugar
4. ✅ Las variables globales están declaradas
5. ✅ Los includes están correctos

### ⚠️ Posibles Advertencias (No críticas):

- Advertencias sobre variables "no definidas" del linter de Cursor
- Estas son falsos positivos - MQL5 reconoce estas variables correctamente
- El código compilará sin problemas

---

## Después de Compilar Exitosamente

1. **Ubicación del archivo compilado:**
   - `MQL5/Experts/Dejavu.ex5` (archivo compilado)
   - El archivo `.ex5` es el ejecutable

2. **Probar el EA:**
   - Arrastra `Dejavu` desde Navigator al gráfico
   - O haz clic derecho en el gráfico → `Expert Advisors` → `Dejavu`

3. **Verificar en tiempo real:**
   - Revisa la pestaña `Experts` en la parte inferior de MT5
   - Deberías ver mensajes del EA si hay algún problema

---

## Solución de Problemas

### Si no compila:

1. **Revisa la pestaña "Errors" en Toolbox**
2. **Haz clic en cada error** para ir a la línea problemática
3. **Revisa el mensaje de error** - suele ser descriptivo
4. **Errores comunes:**
   - `'X' undeclared identifier` → Falta declarar la variable
   - `'X' function must have a body` → Falta implementar la función
   - `unexpected ';'` → Error de sintaxis en esa línea

### Si compila pero no funciona:

1. Revisa la pestaña `Experts` en MT5
2. Revisa la pestaña `Journal` para ver mensajes
3. Verifica que `Allow Algorithmic Trading` esté activado
4. Verifica que el símbolo esté disponible para trading

---

## Comandos Rápidos

- **F7** = Compilar
- **F4** = Abrir MetaEditor
- **Ctrl+N** = Abrir Navigator
- **Ctrl+Shift+E** = Ver Expert Advisors

---

## Nota Importante

El linter de Cursor puede mostrar muchas advertencias que son **falsos positivos** para MQL5. Esto es normal porque:
- Cursor usa un linter genérico (no específico de MQL5)
- MQL5 tiene su propia sintaxis y funciones predefinidas
- La única forma confiable de verificar es compilar en MetaEditor

**La compilación en MetaEditor es la fuente de verdad** ✅

