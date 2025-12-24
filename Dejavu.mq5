//+------------------------------------------------------------------+
//|                                                       DejaVu.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "2.00"
#property strict
#property description "Expert Advisor con Grid Trading, Take Profit Dinámico, Trailing Stop y Panel de Control Gráfico"

//+------------------------------------------------------------------+
//| DESCRIPCIÓN GENERAL                                              |
//+------------------------------------------------------------------+
//| Este Expert Advisor implementa una estrategia de Grid Trading    |
//| con las siguientes características:                              |
//|                                                                   |
//| 1. GRID TRADING: Coloca órdenes pendientes en una cuadrícula     |
//|    alrededor del precio actual con incrementos configurables      |
//|                                                                   |
//| 2. TAKE PROFIT DINÁMICO: El TP se ajusta automáticamente según   |
//|    el incremento entre órdenes (siempre menor al incremento)     |
//|                                                                   |
//| 3. TRAILING STOP: Ajusta automáticamente el Stop Loss cuando     |
//|    el precio se mueve a favor de la posición                     |
//|                                                                   |
//| 4. PANEL DE CONTROL: Interfaz gráfica para activar/desactivar    |
//|    tipos de órdenes y ver estadísticas en tiempo real            |
//|                                                                   |
//| 5. GESTIÓN DE RIESGOS: Control de drawdown máximo, tamaño de     |
//|    lote basado en riesgo, y stop loss dinámico basado en ATR    |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| DEFINICIONES Y CONSTANTES                                        |
//+------------------------------------------------------------------+
//| Rango de Magic Numbers: Define el rango válido para identificar  |
//| las órdenes del EA. Cada sesión usa un Magic Number único.      |
//+------------------------------------------------------------------+
#define MAGICN_START 10000  // Magic Number inicial
#define MAGICN_END   60000  // Magic Number máximo

//+------------------------------------------------------------------+
//| NOTA: Usamos ENUM_BASE_CORNER predefinido de MQL5 en lugar de   |
//| crear un enum personalizado para evitar conflictos.              |
//+------------------------------------------------------------------+

// Estructura para almacenar información de lotes
struct LotSize
{
    double equity;
    double size;
};

// Incluir todas las librerías necesarias
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\HistoryOrderInfo.mqh>
#include <Trade\DealInfo.mqh>
// ATR se creará manualmente usando iATR

// Variables globales
static uint MAGICN;
static double lot;
static int tickett;

// Variables para gestión de riesgos
static double initialBalance;
static double maxDrawdown;
static double highestEquity;

// Variables para control de operaciones
static int max_allowed_orders;
static int _contRA;
static double balanceObjetivo;
static double precioAskBase;
static double precioBidBase;
static int indiceCerradas;
static int l;

// Array dinámico para los tamaños de lotes
static LotSize lotSizes[];

//+------------------------------------------------------------------+
//---       Operaciones
//---

// Objetos de trading
CPositionInfo pos_info;
CTrade trade;
COrderInfo ord_info;
CHistoryOrderInfo hist_ord_info;
CDealInfo deals_info;
CDealInfo temp_num_mag;

// Indicadores - ATR se creará manualmente
int atrHandle;

// Constantes para la interfaz gráfica
const string NOMBRE_PANEL = "DejavuPanel";
const color COLOR_FONDO = clrBlack;
const color COLOR_TEXTO = clrWhite;
const color COLOR_GANANCIA = clrLime;
const color COLOR_PERDIDA = clrRed;
const ENUM_BASE_CORNER ESQUINA_GRAFICO = CORNER_LEFT_UPPER;  // Cambiado a esquina superior izquierda para facilitar alineación
// Panel principal: posición desde la izquierda, evitando solapamiento con panel de control
// Panel de control: X=20, ancho=320, termina en 340px
// Panel de estadísticas: debe empezar después del panel de control + margen más amplio
const int X_DIST = 370;     // Panel principal: 370px desde la izquierda (después del panel de control + 30px margen)
const int Y_DIST = 20;
const int X_SIZE = 300;     // Ancho del panel
const int Y_SIZE = 400;  // Altura del panel (reducida al eliminar sección redundante)

// Variables globales para control de tipos de órdenes (se inicializarán en OnInit)
bool g_tBuyStop;
bool g_tBuyLimit;
bool g_tSellStop;
bool g_tSellLimit;

// Variables estáticas para preservar el estado del panel entre cambios de temporalidad
static bool s_tBuyStop = false;
static bool s_tBuyLimit = false;
static bool s_tSellStop = false;
static bool s_tSellLimit = false;
static bool s_reponerLimits = true;
static bool s_reponerStops = true;
static int s_ordenesPorGrupo = 15;
static int s_incrementoPorGrupo = 5;
static bool s_estadoGuardado = false;

// Variables globales para control de reposición de órdenes
bool g_reponerLimits = true;   // Activar reposición de órdenes Limit
bool g_reponerStops = true;    // Activar reposición de órdenes Stop

// Variables globales para configuración de grupos
int g_ordenesPorGrupo = 15;    // Número de órdenes antes de aumentar incremento
int g_incrementoPorGrupo = 5;  // Incremento adicional por cada grupo

// Constantes para panel de control
const string PANEL_CONTROL = "PanelControl";
const string BOTON_BUYSTOP = "BtnBuyStop";
const string BOTON_BUYLIMIT = "BtnBuyLimit";
const string BOTON_SELLSTOP = "BtnSellStop";
const string BOTON_SELLLIMIT = "BtnSellLimit";
const string BTN_APLICAR = "BtnAplicar";
const int PANEL_CONTROL_X = 20;   // Panel de control: 20px desde la izquierda (esquina superior izquierda)
const int PANEL_CONTROL_Y = 20;
const int PANEL_CONTROL_WIDTH = 320;  // Ancho aumentado para nuevos elementos
const int PANEL_CONTROL_HEIGHT = 320;  // Altura aumentada para nuevos elementos

// Constantes para panel de eliminación de órdenes
const string PANEL_QUITAORDENES = "PanelQuitaOrdenes";
const string INPUT_MAGIC = "InputMagicNumber";
const string BTN_BUSCAR = "BtnBuscar";
const string BTN_ELIMINAR_TODAS = "BtnEliminarTodas";
const string BTN_CERRAR_PANEL = "BtnCerrarPanel";
// Panel centrado: calcular posición desde la izquierda para centrarlo
// Asumiendo un ancho de gráfico típico, centramos el panel (400px de ancho)
const int PANEL_QUITA_WIDTH = 400;
const int PANEL_QUITA_HEIGHT = 400;
const int PANEL_QUITA_X = 200;  // Posición desde la izquierda para centrar aproximadamente
const int PANEL_QUITA_Y = 150;  // Posición desde arriba para centrar verticalmente
bool panelQuitaVisible = false;
//+------------------------------------------------------------------+
//|                     Variables Externas                           |
//+------------------------------------------------------------------+
// Parámetros de gestión de riesgos
input string GestionRiesgos = "Gestion de Riesgos";
input double stopLoss = 9000;           // Stop Loss en puntos
input double takeProfit = 2000;         // Take Profit en puntos
input double maxDrawdownPercent = 20;   // Máximo drawdown permitido en porcentaje
input double riskPerTrade = 2;          // Riesgo por operación en porcentaje
input double dynamicSLMultiplier = 1.5; // Multiplicador para SL dinámico (ATR)
input int atrPeriod = 14;              // Periodo para el cálculo del ATR

//+------------------------------------------------------------------+
//| PARÁMETROS DE TRADING                                            |
//+------------------------------------------------------------------+
//| Configuración principal de la estrategia de Grid Trading        |
//+------------------------------------------------------------------+
input string ConfigTrading = "Configuracion de Trading";
input double tpinverso = 2000;          // Take Profit para órdenes inversas (en puntos)
input double slinverso = 9000;          // Stop Loss para órdenes inversas (en puntos)
input int incremento = 15;              // Incremento entre órdenes en la cuadrícula (en puntos)
input int cantidadDeOperaciones = 50;   // Cantidad máxima de operaciones por dirección
input double cantidadDeGanancia = 20000;// Objetivo de ganancia total (en puntos)
input bool reiniciarPrograma = true;    // Reiniciar después de alcanzar objetivo de ganancia
input bool tBuyStop = false;            // Activar órdenes BuyStop
input bool tBuyLimit = true;            // Activar órdenes BuyLimit
input bool tSellStop = false;           // Activar órdenes SellStop
input bool tSellLimit = true;           // Activar órdenes SellLimit

//+------------------------------------------------------------------+
//| PARÁMETROS DE CONFIGURACIÓN DE REPOSICIÓN                        |
//+------------------------------------------------------------------+
//| Control de reposición automática de órdenes Limit y Stop         |
//+------------------------------------------------------------------+
input string ConfigReposicion = "Configuracion de Reposicion";
input bool reponerLimits = true;       // Reponer órdenes Limit automáticamente
input bool reponerStops = true;        // Reponer órdenes Stop automáticamente

//+------------------------------------------------------------------+
//| PARÁMETROS DE CONFIGURACIÓN DE GRUPOS                            |
//+------------------------------------------------------------------+
//| Configuración de agrupación de órdenes y incremento progresivo   |
//+------------------------------------------------------------------+
input string ConfigGrupos = "Configuracion de Grupos";
input int ordenesPorGrupo = 15;        // Número de órdenes por grupo antes de aumentar incremento
input int incrementoPorGrupo = 5;      // Incremento adicional por cada grupo (en puntos)

//+------------------------------------------------------------------+
//| PARÁMETROS DE TAKE PROFIT DINÁMICO                               |
//+------------------------------------------------------------------+
//| NUEVA FUNCIONALIDAD: Take Profit que se ajusta automáticamente  |
//| según el incremento entre órdenes. Esto permite que el TP sea    |
//| proporcional a la distancia entre órdenes, mejorando la gestión   |
//| de riesgo en la cuadrícula.                                      |
//|                                                                   |
//| Funcionamiento:                                                   |
//| - Si usarTPDinamico = true: TP = incremento * factorTPDinamico   |
//| - El TP siempre será menor al incremento (máximo 90%)            |
//| - Se aplican límites mínimo y máximo para seguridad              |
//+------------------------------------------------------------------+
input string ConfigTPDinamico = "Take Profit Dinamico";
input bool usarTPDinamico = true;       // Activar Take Profit dinámico basado en incremento
input double factorTPDinamico = 0.6;    // Factor multiplicador (0.6 = 60% del incremento)
input double minTP = 100;               // TP mínimo permitido (en puntos)
input double maxTP = 5000;              // TP máximo permitido (en puntos)

//+------------------------------------------------------------------+
//| PARÁMETROS DE TRAILING STOP                                      |
//+------------------------------------------------------------------+
//| NUEVA FUNCIONALIDAD: Ajusta automáticamente el Stop Loss cuando  |
//| el precio se mueve a favor de la posición.                        |
//|                                                                   |
//| Funcionamiento:                                                   |
//| - Para posiciones BUY: Mueve SL hacia arriba cuando precio sube  |
//| - Para posiciones SELL: Mueve SL hacia abajo cuando precio baja  |
//| - Solo se mueve si el precio ha avanzado más que trailingStep    |
//| - Mantiene una distancia fija (trailingStopPuntos) del precio    |
//+------------------------------------------------------------------+
input string ConfigTrailing = "Trailing Stop";
input bool activarTrailingStop = true;  // Activar sistema de Trailing Stop
input double trailingStopPuntos = 500;  // Distancia del SL al precio actual (en puntos)
input double trailingStep = 100;        // Paso mínimo para mover el SL (en puntos)

// Configuración de lotes por nivel de equity
input string ConfigLotes = "Configuracion de Lotes";
input double lot100 = .01;   // Lote para equity < 1000
input double lot1000 = .01;  // Lote para equity 1000-2000
input double lot2000 = .01;  // Lote para equity 2000-3000
input double lot3000 = .01;  // Lote para equity 3000-4000
input double lot4000 = .01;  // Lote para equity 4000-5000
input double lot5000 = .01;  // Lote para equity 5000-6000
input double lot6000 = .01;  // Lote para equity 6000-7000
input double lot7000 = .01;  // Lote para equity 7000-8000
input double lot8000 = 10;   // Lote para equity > 8000

//+------------------------------------------------------------------+
//| PARÁMETROS ADICIONALES (OPCIONALES)                              |
//+------------------------------------------------------------------+
//| Funcionalidades adicionales que pueden activarse si se necesitan |
//+------------------------------------------------------------------+
input string ConfigAdicional = "Funcionalidades Adicionales";
input bool activarReinicioAutomatico = false;  // Activar reinicio automático por contador
input int reinicioAutomatico = 500000;         // Número de ticks para reinicio automático
input bool activarCompararPerdida = false;     // Activar stop loss por pérdida máxima
input double cantidadDePerdida = 50000;        // Pérdida máxima permitida (en puntos)
input bool activarFueraDeRango = false;         // Activar detección de precio fuera de rango
input int ordenesPerdedoras = 0;                // Contador de órdenes perdedoras (para fueraDeRango)

//+------------------------------------------------------------------+
//| VARIABLES GLOBALES (INICIALIZACIÓN)                              |
//+------------------------------------------------------------------+
//| Variables que se inicializan en OnInit() con valores de inputs   |
//+------------------------------------------------------------------+
double stop_loss;              // Stop Loss ajustado (puede cambiar según dígitos del símbolo)
double take_profit;            // Take Profit ajustado (puede cambiar según dígitos del símbolo)
int increment;                 // Incremento ajustado (puede cambiar según dígitos del símbolo)
int _cantidadDeOperaciones;    // Cantidad de operaciones ajustada según límites del broker
datetime tiempo_ref = 0;       // Tiempo de referencia para el historial de operaciones

//+------------------------------------------------------------------+
//| DECLARACIONES FORWARD DE FUNCIONES                               |
//+------------------------------------------------------------------+
//| Declaraciones forward para que las funciones puedan ser llamadas |
//| antes de ser definidas.                                          |
//+------------------------------------------------------------------+
void InitializeLotSizes();
void AdaptarA4Digitos(double &_stop_loss, double &_take_profit, int &_incremento);
void SetParametrosIniciales();
void QuitarOrdenes(uint _MAGICN);
uint getMagicNumberAnterior();
uint RenovarMagicNumber();
void RevisarMaxOp(int _multiplicarOrdenes);
void SetBalanceObjetivoFijo(double _cantidad);
bool RevisarStops();
void ColocarOrdenesIniciales();
bool CheckMoneyForTrade(string _symb, double _lots, int _type);
bool RevisarNuevaOrden();
void ReponerOrdenes();
bool CompararGanancia();
void InicializarPreciosBase();
bool CompararPerdida();
bool FueraDeRango();

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Inicializar el array de lotes y variables de gestión de riesgos
   InitializeLotSizes();
   initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   highestEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   maxDrawdown = initialBalance * maxDrawdownPercent / 100;
   
   // Restaurar estado del panel si fue guardado (cambio de temporalidad)
   if(s_estadoGuardado)
   {
       // Restaurar desde variables estáticas
       g_tBuyStop = s_tBuyStop;
       g_tBuyLimit = s_tBuyLimit;
       g_tSellStop = s_tSellStop;
       g_tSellLimit = s_tSellLimit;
       g_reponerLimits = s_reponerLimits;
       g_reponerStops = s_reponerStops;
       g_ordenesPorGrupo = s_ordenesPorGrupo;
       g_incrementoPorGrupo = s_incrementoPorGrupo;
       Print("Estado del panel restaurado después del cambio de temporalidad");
   }
   else
   {
       // Inicializar desde parámetros de entrada (primera vez)
       g_tBuyStop = tBuyStop;
       g_tBuyLimit = tBuyLimit;
       g_tSellStop = tSellStop;
       g_tSellLimit = tSellLimit;
       g_reponerLimits = reponerLimits;
       g_reponerStops = reponerStops;
       g_ordenesPorGrupo = ordenesPorGrupo;
       g_incrementoPorGrupo = incrementoPorGrupo;
   }
   
   // Inicializar indicador ATR
   atrHandle = iATR(_Symbol, PERIOD_CURRENT, atrPeriod);
   if(atrHandle == INVALID_HANDLE)
   {
      Print("Error al crear el indicador ATR");
      return INIT_FAILED;
   }
   
   // Crear panel de información
   CrearPanel();
   
   // Crear panel de control de tipos de órdenes
   CrearPanelControl();
   
   AdaptarA4Digitos(stop_loss, take_profit, increment);
   SetParametrosIniciales();
   
   // Inicializar precios base para cálculos de rango
   InicializarPreciosBase();
   
   // NO eliminar órdenes al iniciar - mantener órdenes existentes
   // QuitarOrdenes(getMagicNumberAnterior());  // Comentado: no eliminar órdenes del magic anterior
   // QuitarOrdenes(0);  // Comentado: no eliminar todas las órdenes
   MAGICN = RenovarMagicNumber();
//--- Contar el numero de operaciones
   int contarOperaciones = 0;
   if(g_tBuyStop)
   {
      contarOperaciones ++;
   }
   if(g_tBuyLimit)
   {
      contarOperaciones ++;
   }
   if(g_tSellStop)
   {
      contarOperaciones ++;
   }
   if(g_tSellLimit)
   {
      contarOperaciones ++;
   }
//---
   RevisarMaxOp(contarOperaciones);
   SetBalanceObjetivoFijo(cantidadDeGanancia);
   bool stopSuficiente = RevisarStops();
   if(stopSuficiente)
   {
      ColocarOrdenesIniciales();
   }
   
   //+------------------------------------------------------------------+
   //| LECTURA DE INCREMENTO DESDE ARCHIVO (OPCIONAL)                   |
   //+------------------------------------------------------------------+
   //| Permite cambiar el incremento dinámicamente desde un archivo de  |
   //| texto sin necesidad de recompilar el EA.                         |
   //|                                                                   |
   //| Formato del archivo: incremento.txt con un solo número           |
   //| Ejemplo: Si el archivo contiene "20", el incremento será 20      |
   //+------------------------------------------------------------------+
   string fileName = "incremento.txt";
   if(FileIsExist(fileName))
   {
     int fileHandle = FileOpen("incremento.txt", FILE_TXT|FILE_READ|FILE_WRITE, ',');
      if(fileHandle != INVALID_HANDLE)
      {
         int incrementoLeido = (int)FileReadNumber(fileHandle);
         increment = incrementoLeido;  // Actualizar variable global (no se puede modificar input directamente)
        FileClose(fileHandle);
         Print("Incremento leído desde archivo: ", incrementoLeido);
      }
   }
   
   //+------------------------------------------------------------------+
   //| INICIALIZACIÓN DE TIEMPO DE REFERENCIA                          |
   //+------------------------------------------------------------------+
   //| Establece el tiempo de referencia para el historial. Solo se     |
   //| actualiza si el EA no se está reiniciando por cambio de inputs. |
   //+------------------------------------------------------------------+
   if(_UninitReason != 3 && _UninitReason != 5 )
   {
      tiempo_ref = TimeCurrent();
      trade.SetExpertMagicNumber(MAGICN);
   }
//---
   return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
// Función para crear el panel de información
//+------------------------------------------------------------------+
//| Crear Panel de Información                                       |
//+------------------------------------------------------------------+
//| Crea el panel principal de estadísticas con diseño mejorado.     |
//| Muestra información en tiempo real sobre el estado del EA.       |
//+------------------------------------------------------------------+
void CrearPanel()
{
    // Fondo principal del panel con borde mejorado
    ObjectCreate(0, NOMBRE_PANEL + "Fondo", OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(0, NOMBRE_PANEL + "Fondo", OBJPROP_XDISTANCE, X_DIST);
    ObjectSetInteger(0, NOMBRE_PANEL + "Fondo", OBJPROP_YDISTANCE, Y_DIST);
    ObjectSetInteger(0, NOMBRE_PANEL + "Fondo", OBJPROP_XSIZE, X_SIZE);
    ObjectSetInteger(0, NOMBRE_PANEL + "Fondo", OBJPROP_YSIZE, Y_SIZE);
    ObjectSetInteger(0, NOMBRE_PANEL + "Fondo", OBJPROP_BGCOLOR, C'20,20,30'); // Fondo oscuro mejorado
    ObjectSetInteger(0, NOMBRE_PANEL + "Fondo", OBJPROP_CORNER, CORNER_LEFT_UPPER);  // Esquina superior izquierda
    ObjectSetInteger(0, NOMBRE_PANEL + "Fondo", OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(0, NOMBRE_PANEL + "Fondo", OBJPROP_COLOR, C'60,60,80'); // Borde más visible
    ObjectSetInteger(0, NOMBRE_PANEL + "Fondo", OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, NOMBRE_PANEL + "Fondo", OBJPROP_WIDTH, 2);
    ObjectSetInteger(0, NOMBRE_PANEL + "Fondo", OBJPROP_BACK, false);
    ObjectSetInteger(0, NOMBRE_PANEL + "Fondo", OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, NOMBRE_PANEL + "Fondo", OBJPROP_SELECTED, false);
    ObjectSetInteger(0, NOMBRE_PANEL + "Fondo", OBJPROP_HIDDEN, true);
    ObjectSetInteger(0, NOMBRE_PANEL + "Fondo", OBJPROP_ZORDER, 0);
    
    // Barra de título con fondo destacado
    ObjectCreate(0, NOMBRE_PANEL + "TituloFondo", OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(0, NOMBRE_PANEL + "TituloFondo", OBJPROP_XDISTANCE, X_DIST);
    ObjectSetInteger(0, NOMBRE_PANEL + "TituloFondo", OBJPROP_YDISTANCE, Y_DIST);
    ObjectSetInteger(0, NOMBRE_PANEL + "TituloFondo", OBJPROP_XSIZE, X_SIZE);
    ObjectSetInteger(0, NOMBRE_PANEL + "TituloFondo", OBJPROP_YSIZE, 30);
    ObjectSetInteger(0, NOMBRE_PANEL + "TituloFondo", OBJPROP_BGCOLOR, C'40,60,100'); // Azul oscuro
    ObjectSetInteger(0, NOMBRE_PANEL + "TituloFondo", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, NOMBRE_PANEL + "TituloFondo", OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(0, NOMBRE_PANEL + "TituloFondo", OBJPROP_BACK, false);
    ObjectSetInteger(0, NOMBRE_PANEL + "TituloFondo", OBJPROP_SELECTABLE, false);
    
    // Título del panel - alineado con margen izquierdo
    ObjectCreate(0, NOMBRE_PANEL + "Titulo", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, NOMBRE_PANEL + "Titulo", OBJPROP_XDISTANCE, X_DIST + 15);
    ObjectSetInteger(0, NOMBRE_PANEL + "Titulo", OBJPROP_YDISTANCE, Y_DIST + 8);
    ObjectSetInteger(0, NOMBRE_PANEL + "Titulo", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetString(0, NOMBRE_PANEL + "Titulo", OBJPROP_TEXT, "Dejavu EA - Estadísticas");
    ObjectSetString(0, NOMBRE_PANEL + "Titulo", OBJPROP_FONT, "Arial Bold");
    ObjectSetInteger(0, NOMBRE_PANEL + "Titulo", OBJPROP_FONTSIZE, 11);
    ObjectSetInteger(0, NOMBRE_PANEL + "Titulo", OBJPROP_COLOR, clrWhite);
    
    // Separador visual - alineado con margen izquierdo
    ObjectCreate(0, NOMBRE_PANEL + "Separador", OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(0, NOMBRE_PANEL + "Separador", OBJPROP_XDISTANCE, X_DIST + 15);
    ObjectSetInteger(0, NOMBRE_PANEL + "Separador", OBJPROP_YDISTANCE, Y_DIST + 32);
    ObjectSetInteger(0, NOMBRE_PANEL + "Separador", OBJPROP_XSIZE, X_SIZE - 30);  // Margen de 15px a cada lado
    ObjectSetInteger(0, NOMBRE_PANEL + "Separador", OBJPROP_YSIZE, 2);
    ObjectSetInteger(0, NOMBRE_PANEL + "Separador", OBJPROP_BGCOLOR, C'60,60,80');
    ObjectSetInteger(0, NOMBRE_PANEL + "Separador", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, NOMBRE_PANEL + "Separador", OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(0, NOMBRE_PANEL + "Separador", OBJPROP_BACK, false);
    
    // Crear etiquetas para la información con mejor espaciado
    static const string etiquetas[] = {
        "", // Título (ya creado arriba)
        "Balance:",
        "Equity:",
        "Floating P/L:",
        "Drawdown:",
        "Buy Orders:",
        "Sell Orders:",
        "Pending Buy:",
        "Pending Sell:",
        "Total Profit:",
        "Win Rate:",
        "Risk Level:"
    };
    
    int yOffset = 45; // Empezar después del título
    // Con CORNER_LEFT_UPPER, X_DISTANCE se mide desde la izquierda del gráfico
    // X_DIST = 200px (borde izquierdo del panel desde la izquierda)
    // X_SIZE = 300px (ancho del panel)
    // Ahora es más intuitivo: valores X más grandes = más a la derecha
    int margenIzquierdo = 15;  // Margen desde el borde izquierdo del panel (15px)
    int anchoMaximoEtiqueta = 120;  // Ancho máximo estimado para las etiquetas más largas
    int separacionEtiquetaValor = 10;  // Espacio entre etiqueta y valor (10px)
    int margenDerecho = 15;  // Margen desde el borde derecho del panel (15px)
    
    // Posición de ETIQUETAS: a la IZQUIERDA del panel
    // X_DIST + margenIzquierdo = 200 + 15 = 215px desde la izquierda
    int etiquetaX = X_DIST + margenIzquierdo;
    
    // Posición de VALORES: a la DERECHA de las etiquetas
    // X_DIST + margenIzquierdo + ancho etiquetas + separación = 200 + 15 + 120 + 10 = 345px desde la izquierda
    int valorX = X_DIST + margenIzquierdo + anchoMaximoEtiqueta + separacionEtiquetaValor;
    
    for(int i=0; i<ArraySize(etiquetas); i++)
    {
        if(i == 0) continue; // Saltar título (ya creado)
        
        // Etiqueta - a la IZQUIERDA del panel
        ObjectCreate(0, NOMBRE_PANEL + "Label" + IntegerToString(i), OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, NOMBRE_PANEL + "Label" + IntegerToString(i), OBJPROP_XDISTANCE, etiquetaX);
        ObjectSetInteger(0, NOMBRE_PANEL + "Label" + IntegerToString(i), OBJPROP_YDISTANCE, Y_DIST + yOffset);
        ObjectSetInteger(0, NOMBRE_PANEL + "Label" + IntegerToString(i), OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, NOMBRE_PANEL + "Label" + IntegerToString(i), OBJPROP_ANCHOR, ANCHOR_LEFT);
        ObjectSetString(0, NOMBRE_PANEL + "Label" + IntegerToString(i), OBJPROP_TEXT, etiquetas[i]);
        ObjectSetString(0, NOMBRE_PANEL + "Label" + IntegerToString(i), OBJPROP_FONT, "Arial");
        ObjectSetInteger(0, NOMBRE_PANEL + "Label" + IntegerToString(i), OBJPROP_FONTSIZE, i == 12 ? 8 : 10);
        
        // Color especial para separador
        if(i == 12)
            ObjectSetInteger(0, NOMBRE_PANEL + "Label" + IntegerToString(i), OBJPROP_COLOR, C'100,100,120');
        else if(i >= 13)
            ObjectSetInteger(0, NOMBRE_PANEL + "Label" + IntegerToString(i), OBJPROP_COLOR, C'150,180,255'); // Azul claro para tipos de orden
        else
            ObjectSetInteger(0, NOMBRE_PANEL + "Label" + IntegerToString(i), OBJPROP_COLOR, C'200,200,200'); // Gris claro
        
        // Valor (solo si no es separador) - a la DERECHA de las etiquetas
        if(i != 12)
        {
        ObjectCreate(0, NOMBRE_PANEL + "Value" + IntegerToString(i), OBJ_LABEL, 0, 0, 0);
            ObjectSetInteger(0, NOMBRE_PANEL + "Value" + IntegerToString(i), OBJPROP_XDISTANCE, valorX);
            ObjectSetInteger(0, NOMBRE_PANEL + "Value" + IntegerToString(i), OBJPROP_YDISTANCE, Y_DIST + yOffset);
            ObjectSetInteger(0, NOMBRE_PANEL + "Value" + IntegerToString(i), OBJPROP_CORNER, CORNER_LEFT_UPPER);
            ObjectSetInteger(0, NOMBRE_PANEL + "Value" + IntegerToString(i), OBJPROP_ANCHOR, ANCHOR_LEFT);
            ObjectSetString(0, NOMBRE_PANEL + "Value" + IntegerToString(i), OBJPROP_FONT, "Arial Bold");
        ObjectSetInteger(0, NOMBRE_PANEL + "Value" + IntegerToString(i), OBJPROP_FONTSIZE, 10);
            ObjectSetInteger(0, NOMBRE_PANEL + "Value" + IntegerToString(i), OBJPROP_COLOR, COLOR_TEXTO);
        }
        
        yOffset += 28; // Espaciado mejorado
    }
}

// Función para actualizar el panel de información
void ActualizarPanel()
{
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double floating = equity - balance;
    double drawdown = (highestEquity - equity) / highestEquity * 100;
    
    int buyOrders = 0, sellOrders = 0, pendingBuy = 0, pendingSell = 0;
    double totalProfit = 0;  // Profit flotante de posiciones abiertas
    double realizedProfit = 0;  // Profit realizado de posiciones cerradas
    int totalTrades = 0, winTrades = 0;
    double totalMarginUsed = 0;  // Margen usado por posiciones abiertas
    
    // Contar órdenes abiertas y pendientes - filtrar por Magic Number Y Símbolo
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(pos_info.SelectByIndex(i))
        {
            // Filtrar estrictamente por Magic Number Y Símbolo
            if(pos_info.Magic() == MAGICN && pos_info.Symbol() == _Symbol)
            {
                // Contar según el tipo de posición
                if(pos_info.Type() == POSITION_TYPE_BUY)
                {
                    buyOrders++;
                }
                else if(pos_info.Type() == POSITION_TYPE_SELL)
                {
                    sellOrders++;
                }
                    
                totalProfit += pos_info.Profit();  // Profit flotante
                // Calcular margen usado usando OrderCalcMargin (método más confiable)
                double marginCalc = 0;
                ENUM_ORDER_TYPE orderType = (pos_info.Type() == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
                
                if(OrderCalcMargin(orderType, _Symbol, pos_info.Volume(), pos_info.PriceOpen(), marginCalc))
                {
                    totalMarginUsed += marginCalc;
                }
                else
                {
                    // Fallback: cálculo aproximado usando margen inicial del símbolo
                    double marginReq = SymbolInfoDouble(_Symbol, SYMBOL_MARGIN_INITIAL);
                    if(marginReq > 0)
                    {
                        totalMarginUsed += pos_info.Volume() * marginReq;
                    }
                }
            }
        }
    }
    
    // Contar órdenes pendientes - filtrar por Magic Number Y Símbolo
    for(int i = 0; i < OrdersTotal(); i++)
    {
        if(ord_info.SelectByIndex(i))
        {
            // Filtrar estrictamente por Magic Number Y Símbolo
            if(ord_info.Magic() == MAGICN && ord_info.Symbol() == _Symbol)
            {
                // Contar según el tipo de orden pendiente
                if(ord_info.Type() == ORDER_TYPE_BUY_LIMIT || ord_info.Type() == ORDER_TYPE_BUY_STOP)
                {
                    pendingBuy++;
                }
                else if(ord_info.Type() == ORDER_TYPE_SELL_LIMIT || ord_info.Type() == ORDER_TYPE_SELL_STOP)
                {
                    pendingSell++;
                }
            }
        }
    }
    
    // Calcular win rate y profit realizado desde el inicio de la sesión
    // Seleccionar historial desde el inicio de la sesión (tiempo_ref) o desde hace 30 días si no está inicializado
    datetime desde = (tiempo_ref > 0) ? tiempo_ref : (TimeCurrent() - PeriodSeconds(PERIOD_D1) * 30);
    if(HistorySelect(desde, TimeCurrent()))
    {
        for(int i = 0; i < HistoryDealsTotal(); i++)
        {
            if(deals_info.SelectByIndex(i))
            {
                // Filtrar por Magic Number Y Símbolo para obtener solo deals del bot actual
                if(deals_info.Magic() == MAGICN && 
                   deals_info.Symbol() == _Symbol &&
                   deals_info.Entry() == DEAL_ENTRY_OUT)  // Solo deals de salida (posiciones cerradas)
                {
                    totalTrades++;
                    double dealProfit = deals_info.Profit();
                    if(dealProfit > 0)
                        winTrades++;
                    realizedProfit += dealProfit;  // Sumar profit realizado
                }
            }
        }
    }
    
    double winRate = totalTrades > 0 ? (double)winTrades/totalTrades * 100 : 0;
    
    // Calcular Risk Level real basado en el margen usado vs balance
    double riskLevel = 0;
    if(balance > 0)
    {
        riskLevel = (totalMarginUsed / balance) * 100;  // Porcentaje de balance usado como margen
    }
    
    // Actualizar valores en el panel con mejor formato
    string valores[] = {
        "", // Título (índice 0, no se usa)
        DoubleToString(balance, 2),
        DoubleToString(equity, 2),
        DoubleToString(floating, 2),
        DoubleToString(drawdown, 2) + "%",
        IntegerToString(buyOrders),
        IntegerToString(sellOrders),
        IntegerToString(pendingBuy),
        IntegerToString(pendingSell),
        DoubleToString(totalProfit + realizedProfit, 2),  // Profit total = flotante + realizado
        DoubleToString(winRate, 1) + "%",
        DoubleToString(riskLevel, 2) + "%"  // Risk Level real basado en margen usado
    };
    
    for(int i=1; i<ArraySize(valores); i++)
    {
        
        color valorColor = COLOR_TEXTO;
        
        // Colores según el tipo de dato
        if(i == 3) // Floating P/L
        {
            valorColor = floating >= 0 ? C'0,200,0' : C'200,0,0'; // Verde/Rojo más vibrante
        }
        else if(i == 4) // Drawdown
        {
            valorColor = drawdown > 10 ? C'255,100,100' : (drawdown > 5 ? C'255,200,0' : C'150,200,150');
        }
        else if(i == 9) // Total Profit (flotante + realizado)
        {
            double profitTotal = totalProfit + realizedProfit;
            valorColor = profitTotal >= 0 ? C'0,200,0' : C'200,0,0';
        }
        else if(i == 10) // Win Rate
        {
            valorColor = winRate >= 50 ? C'0,200,0' : (winRate >= 30 ? C'255,200,0' : C'200,0,0');
        }
        else if(i >= 13) // Contadores de tipos de orden
        {
            valorColor = C'150,200,255'; // Azul claro para contadores
        }
        else
        {
            valorColor = C'220,220,220'; // Gris claro para valores normales
        }
            
        ObjectSetInteger(0, NOMBRE_PANEL + "Value" + IntegerToString(i), OBJPROP_COLOR, valorColor);
        ObjectSetString(0, NOMBRE_PANEL + "Value" + IntegerToString(i), OBJPROP_TEXT, valores[i]);
    }
}

void OnDeinit(const int reason)
{
    // Limpiar recursos - liberar handle del indicador
    if(atrHandle != INVALID_HANDLE)
    {
        IndicatorRelease(atrHandle);
    }
    
    // NO eliminar órdenes si solo se está cambiando de temporalidad
    // Solo eliminar órdenes si el EA se está removiendo completamente del gráfico
    if(reason != REASON_CHARTCHANGE)
    {
        // Eliminar todos los objetos del panel principal
        ObjectsDeleteAll(0, NOMBRE_PANEL);
        
        // Eliminar todos los objetos del panel de control y sus elementos
        ObjectsDeleteAll(0, PANEL_CONTROL);
        
        // Eliminar botones individuales del panel de control
        ObjectDelete(0, BOTON_BUYSTOP);
        ObjectDelete(0, BOTON_BUYLIMIT);
        ObjectDelete(0, BOTON_SELLSTOP);
        ObjectDelete(0, BOTON_SELLLIMIT);
        ObjectDelete(0, BTN_APLICAR);
        ObjectDelete(0, "BtnQuitaOrdenes");
        ObjectDelete(0, "BtnReponerLimits");
        ObjectDelete(0, "BtnReponerStops");
        ObjectDelete(0, "LabelOrdenesGrupo");
        ObjectDelete(0, "LabelIncrementoGrupo");
        ObjectDelete(0, "ValorOrdenesGrupo");
        ObjectDelete(0, "ValorIncrementoGrupo");
        ObjectDelete(0, "BtnOrdenesGrupoMenos");
        ObjectDelete(0, "BtnOrdenesGrupoMas");
        ObjectDelete(0, "BtnIncrementoGrupoMenos");
        ObjectDelete(0, "BtnIncrementoGrupoMas");
        ObjectDelete(0, PANEL_CONTROL + "Separador1");
        ObjectDelete(0, PANEL_CONTROL + "Separador2");
        
        // Eliminar etiquetas del panel de control
        string tipos[] = {"BuyStop", "BuyLimit", "SellStop", "SellLimit"};
        for(int i = 0; i < 4; i++)
        {
            ObjectDelete(0, PANEL_CONTROL + tipos[i] + "Label");
            // Los contadores ya no existen en el panel de control
        }
        
        // Eliminar todos los objetos del panel de quitar órdenes
        ObjectsDeleteAll(0, PANEL_QUITAORDENES);
        ObjectDelete(0, INPUT_MAGIC);
        ObjectDelete(0, INPUT_MAGIC + "Label");
        ObjectDelete(0, BTN_BUSCAR);
        ObjectDelete(0, BTN_ELIMINAR_TODAS);
        ObjectDelete(0, BTN_CERRAR_PANEL);
        
        // Eliminar cualquier objeto residual que pueda tener el prefijo
        int total = ObjectsTotal(0);
        for(int i = total - 1; i >= 0; i--)
        {
            string name = ObjectName(0, i);
            if(StringFind(name, NOMBRE_PANEL) == 0 || 
               StringFind(name, PANEL_CONTROL) == 0 || 
               StringFind(name, PANEL_QUITAORDENES) == 0 ||
               StringFind(name, BOTON_BUYSTOP) == 0 ||
               StringFind(name, BOTON_BUYLIMIT) == 0 ||
               StringFind(name, BOTON_SELLSTOP) == 0 ||
               StringFind(name, BOTON_SELLLIMIT) == 0 ||
               StringFind(name, BTN_APLICAR) == 0 ||
               StringFind(name, "BtnQuitaOrdenes") == 0)
            {
                ObjectDelete(0, name);
            }
        }
        
        // Forzar actualización del gráfico para eliminar cualquier objeto residual
        ChartRedraw(0);
        
        // Solo eliminar órdenes si el EA se está removiendo completamente
        QuitarOrdenes(MAGICN);
        QuitarOrdenes(0);
    }
    else
    {
        // Si solo cambió la temporalidad, guardar el estado del panel antes de limpiar objetos
        // Guardar estado actual en variables estáticas
        s_tBuyStop = g_tBuyStop;
        s_tBuyLimit = g_tBuyLimit;
        s_tSellStop = g_tSellStop;
        s_tSellLimit = g_tSellLimit;
        s_reponerLimits = g_reponerLimits;
        s_reponerStops = g_reponerStops;
        s_ordenesPorGrupo = g_ordenesPorGrupo;
        s_incrementoPorGrupo = g_incrementoPorGrupo;
        s_estadoGuardado = true;
        
        // Limpiar objetos gráficos pero mantener órdenes
        // Los objetos se recrearán en OnInit() del nuevo timeframe
        ObjectsDeleteAll(0, NOMBRE_PANEL);
        ObjectsDeleteAll(0, PANEL_CONTROL);
        ObjectsDeleteAll(0, PANEL_QUITAORDENES);
        ChartRedraw(0);
        
        Print("Estado del panel guardado para cambio de temporalidad");
    }
}
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
//| Función principal que se ejecuta en cada tick del mercado.       |
//| Aquí se realizan todas las verificaciones y actualizaciones:     |
//|                                                                   |
//| 1. Verificación de drawdown máximo                                |
//| 2. Cálculo de Stop Loss dinámico (basado en ATR)                 |
//| 3. Ajuste de tamaño de lote según riesgo                          |
//| 4. Aplicación de Trailing Stop                                    |
//| 5. Actualización de paneles gráficos                             |
//| 6. Reposición de órdenes cerradas                                 |
//| 7. Verificación de objetivo de ganancia                           |
//| 8. Verificación de pérdida máxima (opcional)                     |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Calcular Stop Loss Dinámico                                      |
//+------------------------------------------------------------------+
//| Calcula el Stop Loss basado en el indicador ATR (Average True   |
//| Range) multiplicado por un factor. Esto adapta el SL a la       |
//| volatilidad actual del mercado.                                  |
//|                                                                   |
//| Parámetros:                                                       |
//| - dynamicSLMultiplier: Factor multiplicador del ATR               |
//| - stopLoss: Stop Loss mínimo (fallback si ATR falla)             |
//|                                                                   |
//| Retorna: Stop Loss en precio (no en puntos)                      |
//+------------------------------------------------------------------+
double CalcularStopLossDinamico()
{
    double atrBuffer[];
    ArraySetAsSeries(atrBuffer, true);
    if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) <= 0)
    {
        return stopLoss * Point(); // Si falla, usar stop loss fijo
    }
    double atrValue = atrBuffer[0] * dynamicSLMultiplier;
    double minStop = stopLoss * Point();
    return MathMax(atrValue, minStop);
}

//+------------------------------------------------------------------+
//| Calcular Take Profit Dinámico                                    |
//+------------------------------------------------------------------+
//| NUEVA FUNCIONALIDAD: Calcula el Take Profit basado en el         |
//| incremento actual entre órdenes. Esto asegura que el TP sea      |
//| proporcional a la distancia entre órdenes en la cuadrícula.      |
//|                                                                   |
//| Ventajas:                                                         |
//| - TP se ajusta automáticamente cuando el incremento cambia       |
//| - Siempre menor al incremento (máximo 90%)                        |
//| - Mejora la gestión de riesgo en grid trading                    |
//|                                                                   |
//| Parámetros:                                                       |
//| - incrementoActual: Incremento actual (puede variar cada 15 ord.)|
//|                                                                   |
//| Fórmula: TP = incremento * factorTPDinamico                      |
//|                                                                   |
//| Retorna: Take Profit en precio (no en puntos)                     |
//+------------------------------------------------------------------+
double CalcularTakeProfitDinamico(int incrementoActual)
{
    if(!usarTPDinamico)
        return take_profit * Point();
    
    double tpCalculado = incrementoActual * factorTPDinamico;
    
    // Asegurar que sea menor al incremento
    if(tpCalculado >= incrementoActual)
        tpCalculado = incrementoActual * 0.9;  // 90% como máximo
    
    // Aplicar límites mínimo y máximo
    tpCalculado = MathMax(tpCalculado, minTP);
    tpCalculado = MathMin(tpCalculado, maxTP);
    
    return tpCalculado * Point();
}

// Función para verificar el drawdown
bool VerificarDrawdown()
{
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    highestEquity = MathMax(highestEquity, equity);
    double currentDrawdown = highestEquity - equity;
    
    if(currentDrawdown > maxDrawdown)
    {
        Print("Máximo drawdown alcanzado: ", currentDrawdown);
        return false;
    }
    return true;
}

//+------------------------------------------------------------------+
//| Aplicar Trailing Stop                                            |
//+------------------------------------------------------------------+
//| NUEVA FUNCIONALIDAD: Ajusta automáticamente el Stop Loss de las  |
//| posiciones abiertas cuando el precio se mueve a favor.            |
//|                                                                   |
//| Funcionamiento detallado:                                         |
//|                                                                   |
//| Para posiciones BUY:                                              |
//| - Verifica si Ask >= precioApertura + trailingStep               |
//| - Calcula nuevo SL = Ask - trailingStopPuntos                     |
//| - Solo mueve si nuevo SL > SL actual + trailingStep              |
//|                                                                   |
//| Para posiciones SELL:                                             |
//| - Verifica si Bid <= precioApertura - trailingStep              |
//| - Calcula nuevo SL = Bid + trailingStopPuntos                    |
//| - Solo mueve si nuevo SL < SL actual - trailingStep               |
//|                                                                   |
//| Ventajas:                                                         |
//| - Protege ganancias mientras permite que crezcan                 |
//| - Se ajusta automáticamente sin intervención manual               |
//| - Respeta el trailingStep para evitar movimientos excesivos      |
//+------------------------------------------------------------------+
void AplicarTrailingStop()
{
    if(!activarTrailingStop)
        return;
    
    double trailingStop = trailingStopPuntos * Point();
    double step = trailingStep * Point();
    
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(!pos_info.SelectByIndex(i))
            continue;
            
        if(pos_info.Magic() != MAGICN)
            continue;
        
        double currentSL = pos_info.StopLoss();
        double newSL = 0;
        bool modificar = false;
        
        if(pos_info.Type() == POSITION_TYPE_BUY)
        {
            double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double precioApertura = pos_info.PriceOpen();
            
            // Solo mover SL si el precio ha subido más que el step
            if(ask >= precioApertura + step)
            {
                newSL = ask - trailingStop;
                // Solo mover si el nuevo SL es mayor que el actual
                if(newSL > currentSL + step)
                {
                    modificar = true;
                }
            }
        }
        else if(pos_info.Type() == POSITION_TYPE_SELL)
        {
            double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            double precioApertura = pos_info.PriceOpen();
            
            // Solo mover SL si el precio ha bajado más que el step
            if(bid <= precioApertura - step)
            {
                newSL = bid + trailingStop;
                // Solo mover si el nuevo SL es menor que el actual (o no hay SL)
                if(currentSL == 0 || newSL < currentSL - step)
                {
                    modificar = true;
                }
            }
        }
        
        if(modificar)
        {
            newSL = NormalizeDouble(newSL, _Digits);
            if(!trade.PositionModify(pos_info.Ticket(), newSL, pos_info.TakeProfit()))
            {
                Print("Error modificando trailing stop: ", GetLastError());
            }
        }
    }
}

// Función para calcular el tamaño del lote basado en el riesgo
double CalcularLotesPorRiesgo(double stopLossPoints)
{
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double riskAmount = balance * riskPerTrade / 100;
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    double calculatedLot = NormalizeDouble(riskAmount / (stopLossPoints * tickValue), 2);
    calculatedLot = MathFloor(calculatedLot / lotStep) * lotStep;
    
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    
    return MathMin(MathMax(calculatedLot, minLot), maxLot);
}

void OnTick()
{
    // Verificar drawdown
    if(!VerificarDrawdown())
    {
        Print("Cerrando operaciones por drawdown máximo");
        QuitarOrdenes(MAGICN);
        QuitarOrdenes(0);
        return;
    }
    
    // Calcular stop loss dinámico
    double stopLossDinamico = CalcularStopLossDinamico();
    
    // Ajustar tamaño del lote según el riesgo
    double nuevoLote = CalcularLotesPorRiesgo(stopLossDinamico);
    if(MathAbs(nuevoLote - lot) > SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP))
    {
        lot = nuevoLote;
    }
    
    // Aplicar trailing stop si está activado
    if(activarTrailingStop)
    {
        AplicarTrailingStop();
    }
    
    // Actualizar panel de información
    ActualizarPanel();
    
    // Actualizar panel de control
    ActualizarPanelControl();
    
    //+------------------------------------------------------------------+
    //| REPOSICIÓN DE ÓRDENES                                           |
    //+------------------------------------------------------------------+
    //| Cuando una orden se cierra, se repone automáticamente en el      |
    //| mismo precio. Si la orden cerró con ganancia, puede cambiar     |
    //| de tipo (ej: SellStop ganador -> SellLimit).                    |
    //+------------------------------------------------------------------+
    ReponerOrdenes();
    
    //+------------------------------------------------------------------+
    //| VERIFICACIÓN DE OBJETIVO DE GANANCIA                            |
    //+------------------------------------------------------------------+
    //| Compara el equity actual con el balance objetivo. Si se alcanza, |
    //| reinicia el sistema con un nuevo Magic Number.                   |
    //+------------------------------------------------------------------+
    bool gananciaConseguida = CompararGanancia();
    if(gananciaConseguida)
    {
        SendNotification("Se ha llegado a la meta de ganancia");
        SetParametrosIniciales();
        SetBalanceObjetivoFijo(cantidadDeGanancia);
        QuitarOrdenes(MAGICN);
        QuitarOrdenes(0);
        MAGICN = RenovarMagicNumber();
        if(reiniciarPrograma)
        {
            ColocarOrdenesIniciales();
        }
        _contRA = 0;
        
        // Resetear variables de gestión de riesgos
        initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        highestEquity = AccountInfoDouble(ACCOUNT_EQUITY);
        maxDrawdown = initialBalance * maxDrawdownPercent / 100;
    }
    
    //+------------------------------------------------------------------+
    //| VERIFICACIÓN DE PÉRDIDA MÁXIMA (OPCIONAL)                       |
    //+------------------------------------------------------------------+
    //| Si está activado, verifica si se ha alcanzado la pérdida máxima |
    //| permitida. Si es así, cierra todas las operaciones.            |
    //+------------------------------------------------------------------+
    if(activarCompararPerdida)
    {
        bool perdidaAlcanzada = CompararPerdida();
        if(perdidaAlcanzada)
        {
            Print("Pérdida máxima alcanzada. Cerrando todas las operaciones.");
            SendNotification("Se ha alcanzado la pérdida máxima permitida");
            QuitarOrdenes(MAGICN);
            QuitarOrdenes(0);
            return;
        }
    }
    
    //+------------------------------------------------------------------+
    //| VERIFICACIÓN DE PRECIO FUERA DE RANGO (OPCIONAL)                |
    //+------------------------------------------------------------------+
    //| Verifica si el precio actual está fuera del rango permitido    |
    //| basado en el stop loss y las órdenes perdedoras. Si el precio   |
    //| se aleja demasiado, puede detener el trading.                   |
    //+------------------------------------------------------------------+
    if(activarFueraDeRango)
    {
        bool precioFueraRango = FueraDeRango();
        if(precioFueraRango)
        {
            Print("Precio fuera de rango permitido. Considerar detener trading.");
            // Aquí puedes agregar lógica adicional si es necesario
        }
    }
    
    //+------------------------------------------------------------------+
    //| REINICIO AUTOMÁTICO POR CONTADOR (OPCIONAL)                      |
    //+------------------------------------------------------------------+
    //| Reinicia el EA automáticamente después de un número determinado |
    //| de ticks. Útil para prevenir problemas de memoria o resetear    |
    //| el estado del EA periódicamente.                                |
    //|                                                                   |
    //| Funcionamiento:                                                  |
    //| - Cuenta los ticks desde el inicio (_contRA)                    |
    //| - Cuando alcanza reinicioAutomatico, reinicia todo el sistema   |
    //| - Útil en estrategias de larga duración                         |
    //+------------------------------------------------------------------+
    _contRA++;
    if(activarReinicioAutomatico && _contRA >= reinicioAutomatico)
    {
        Print("Reinicio automático activado después de ", reinicioAutomatico, " ticks");
        SetBalanceObjetivoFijo(cantidadDeGanancia);
        QuitarOrdenes(MAGICN);
        QuitarOrdenes(0);
        MAGICN = RenovarMagicNumber();
        ColocarOrdenesIniciales();
                 _contRA = 0;
    }
}
//+------------------------------------------------------------------+
//|                        FUNCIONES                                 |
//+------------------------------------------------------------------+

// Función para inicializar los tamaños de lotes
void InitializeLotSizes() {
    ArrayResize(lotSizes, 64);
    for(int i=0; i<64; i++) {
        lotSizes[i].equity = (i+1) * 1000;
        lotSizes[i].size = i < 8 ? 0.01 : 10;  // Primeros 8 niveles con 0.01, resto con 10
    }
}

//+------------------------------------------------------------------+
void AdaptarA4Digitos(double &_stop_loss, double &_take_profit, int &_incremento)
{
   int vdigits = (int) SymbolInfoInteger("EURUSD", SYMBOL_DIGITS);
   if(vdigits == 4)
   {
      _stop_loss = stopLoss / 10;
      _take_profit = takeProfit / 10;
      _incremento = incremento / 10;
   }
}
//+------------------------------------------------------------------+
void SetParametrosIniciales()
{
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    
    // Buscar el tamaño de lote apropiado basado en el equity actual
    for(int i=0; i<ArraySize(lotSizes); i++) {
        if(equity < lotSizes[i].equity) {
            lot = lotSizes[i].size;
            break;
        }
    }
    
    // Si el equity es mayor que el último nivel, usar el último tamaño de lote
    if(equity >= lotSizes[ArraySize(lotSizes)-1].equity) {
        lot = lotSizes[ArraySize(lotSizes)-1].size;
    }
    
      Comment(StringFormat("El tamaño actual del lote es: %G", lot));
}
//+------------------------------------------------------------------+
void QuitarOrdenes (uint _MAGICN)
{
   int x = 0;
   int desliz = 8;
   if(_Digits == 3 || _Digits == 5)
   {
      desliz = desliz * 10;
   }
   if(_MAGICN == 0)
   {
      do
      {
         int numeroDePosiciones = PositionsTotal();
         int numeroDeOrdenes = OrdersTotal();
         bool seleccionado = false;
         bool j = 0;
         Print(numeroDePosiciones + numeroDeOrdenes, " total orders");
         //---
         for(int i = numeroDePosiciones - 1; i >= 0; i--)
         {
            seleccionado = pos_info.SelectByIndex(i);
            //if(pos_info.Type() < 2)
            //{
            //double ClosePrice = 0;
            //if(pos_info.Type() == POSITION_TYPE_BUY)
            //{
            //   ClosePrice = NormalizeDouble(SymbolInfoDouble(pos_info.Symbol(), SYMBOL_BID), _Digits);
            //}
            //if(pos_info.Type() == POSITION_TYPE_SELL)
            //{
            //   ClosePrice = NormalizeDouble(SymbolInfoDouble(pos_info.Symbol(), SYMBOL_ASK), _Digits);
            //}
            //---
            j = trade.PositionClose(pos_info.Ticket());
            //}
         }
         for(int i = numeroDeOrdenes - 1; i >= 0; i--)
         {
            if(ord_info.SelectByIndex(i))
            {
               j = trade.OrderDelete(ord_info.Ticket());
            }
         }
         x++;
         Sleep(1000);
      }
      while(x < 10);
   }
   else
   {
      do
      {
         int numeroDePosiciones = PositionsTotal();
         int numeroDeOrdenes = OrdersTotal();
         bool seleccionado = false;
         bool j = 0;
         Print(numeroDePosiciones + numeroDeOrdenes, " total orders");
         //---
         // Cerrar posiciones con el magic number Y del símbolo actual
         for(int i = numeroDePosiciones - 1; i >= 0; i--)
         {
            seleccionado = pos_info.SelectByIndex(i);
            // Filtrar por magic number Y símbolo (activo) para evitar afectar otros bots
            if(pos_info.Magic() == _MAGICN && pos_info.Symbol() == _Symbol)
            {
               j = trade.PositionClose(pos_info.Ticket());
            }
         }
         // Eliminar órdenes pendientes con el magic number Y del símbolo actual
         for(int i = numeroDeOrdenes - 1; i >= 0; i--)
         {
            if(ord_info.SelectByIndex(i) && 
               ord_info.Magic() == _MAGICN && 
               ord_info.Symbol() == _Symbol)  // Solo del activo actual
            {
               j = trade.OrderDelete(ord_info.Ticket());
            }
         }
         x++;
         Sleep(1000);
      }
      while(x < 10);
   }
}
//+------------------------------------------------------------------+
uint getMagicNumberAnterior ()
{
   int _handle = 0;
   uint _magicNumberAnterior = 0;
   if(FileIsExist("doNotModifyKoboldFX1875.txt"))
   {
      _handle = FileOpen("doNotModifyKoboldFX1875.txt", FILE_TXT | FILE_READ | FILE_WRITE, ',');
      _magicNumberAnterior = (uint) StringToInteger(FileReadString(_handle));
   }
   else
   {
      Alert("Hubo un error al leer el magic number del archivo txt");
      _magicNumberAnterior = 10000;
   }
   FileClose(_handle);
   return (_magicNumberAnterior);
}
//+------------------------------------------------------------------+
uint RenovarMagicNumber ()
{
   uint magicNumberNuevo = 10000;
   int _handle;
   if(FileIsExist("doNotModifyKoboldFX1875.txt"))
   {
      _handle = FileOpen("doNotModifyKoboldFX1875.txt", FILE_TXT | FILE_READ | FILE_WRITE, ',');
      magicNumberNuevo = (uint) StringToInteger(FileReadString(_handle));
      magicNumberNuevo++;
      // Veo si ya existen ordenes en el historial con ese magic number
      // Busco un magic number que nunca haya sido usado antes
      // El problema será cuando se hayan acabado todos los magic numbers y haya que crear una cuenta nueva
      HistorySelect(tiempo_ref, TimeCurrent());
      int _ordenesCerradas = HistoryDealsTotal();
      bool mnNuncaUsado = true;
      do
      {
         mnNuncaUsado = true;
         for(int _l = 0; _l < _ordenesCerradas; _l++)
         {
            deals_info.SelectByIndex(_l);
            if(deals_info.Entry() == DEAL_ENTRY_OUT)
            {
               if(deals_info.Magic() == magicNumberNuevo)
               {
                  magicNumberNuevo ++;
                  mnNuncaUsado = false;
               }
            }
         }
      }
      while(mnNuncaUsado == false);
      if(magicNumberNuevo >= 60000)
      {
         Alert("Se acabaron los magic numbers, hay que crear una cuenta nueva");
         Comment("Se acabaron los magic numbers, hay que crear una cuenta nueva");
         magicNumberNuevo = 10000;
         FileSeek(_handle, 0, SEEK_SET);
         FileWrite(_handle, magicNumberNuevo);
      }
      else
      {
         FileSeek(_handle, 0, SEEK_SET);
         FileWrite(_handle, magicNumberNuevo);
      }
   }
   else
   {
      _handle = FileOpen("doNotModifyKoboldFX1875.txt", FILE_CSV | FILE_WRITE, ',');
      if(_handle > 0)
      {
         FileWrite(_handle, magicNumberNuevo);
      }
   }
   FileClose(_handle);
   return (magicNumberNuevo);
}
//+------------------------------------------------------------------+
void  RevisarMaxOp(int _multiplicarOrdenes)
{
   max_allowed_orders = (int) AccountInfoInteger(ACCOUNT_LIMIT_ORDERS);
   if(max_allowed_orders < (_cantidadDeOperaciones * _multiplicarOrdenes))
   {
      Alert("your broker only allows " + (string)max_allowed_orders + " pending orders and we recommend " + (string)(cantidadDeOperaciones * _multiplicarOrdenes) + " pending orders, the results may not be optimal." );
      _cantidadDeOperaciones = (max_allowed_orders / _multiplicarOrdenes) - 1;
   }
}
//+------------------------------------------------------------------+
void SetBalanceObjetivoFijo (double _cantidad)
{
   balanceObjetivo = AccountInfoDouble(ACCOUNT_EQUITY) + _cantidad;
}
//+------------------------------------------------------------------+
//| Revisar Stops                                                    |
//+------------------------------------------------------------------+
//| Verifica que los valores de Stop Loss y Take Profit cumplan con  |
//| los requisitos mínimos del broker.                               |
//|                                                                   |
//| Funcionamiento:                                                   |
//| - Obtiene el nivel mínimo de stops del broker                    |
//| - Compara stop_loss y take_profit (en puntos) con el mínimo     |
//| - Si no cumple, muestra un mensaje informativo                   |
//|                                                                   |
//| Retorna: true si los stops son válidos, false en caso contrario  |
//+------------------------------------------------------------------+
bool RevisarStops()
{
   bool _ret = false;
   long minstoplevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   
   // Convertir stop_loss y take_profit de puntos a distancia en precio
   double stopLossDistance = stop_loss * Point();
   double takeProfitDistance = take_profit * Point();
   double minStopDistance = minstoplevel * Point();
   
   // Verificar que ambos cumplan con el mínimo del broker
   if((stopLossDistance >= minStopDistance) && (takeProfitDistance >= minStopDistance))
   {
      _ret = true;
   }
   else
   {
      _ret = false;
      // Ajustar automáticamente si es posible
      if(stopLossDistance < minStopDistance)
      {
         stop_loss = (double)minstoplevel;
         Print("Stop Loss ajustado automáticamente a: ", stop_loss, " puntos (mínimo del broker)");
      }
      if(takeProfitDistance < minStopDistance)
      {
         take_profit = (double)minstoplevel;
         Print("Take Profit ajustado automáticamente a: ", take_profit, " puntos (mínimo del broker)");
      }
      
      // Mensaje informativo (no bloqueante)
      string mensaje = "Ajuste de stops: Broker requiere mínimo " + IntegerToString(minstoplevel) + 
                       " puntos. SL: " + DoubleToString(stop_loss, 0) + 
                       " TP: " + DoubleToString(take_profit, 0);
      Print(mensaje);
   }
   return (_ret);
}
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Colocar Órdenes Iniciales                                        |
//+------------------------------------------------------------------+
//| Coloca la cuadrícula inicial de órdenes pendientes alrededor del |
//| precio actual.                                                    |
//|                                                                   |
//| Funcionamiento:                                                   |
//| - Coloca órdenes hacia abajo (SellStop y BuyLimit)               |
//| - Coloca órdenes hacia arriba (SellLimit y BuyStop)              |
//| - El incremento aumenta cada 15 órdenes (+5 puntos)               |
//| - Usa Take Profit dinámico si está activado                      |
//|                                                                   |
//| Tipos de órdenes colocadas:                                      |
//| - BuyStop: Se activa cuando precio sube                          |
//| - BuyLimit: Se activa cuando precio baja                         |
//| - SellStop: Se activa cuando precio baja                         |
//| - SellLimit: Se activa cuando precio sube                        |
//+------------------------------------------------------------------+
void ColocarOrdenesIniciales ()
{
   // Verificar si ya existen órdenes pendientes con este Magic Number
   // Si existen, no colocar nuevas órdenes (evita duplicar al cambiar temporalidad)
   int ordenesPendientesExistentes = 0;
   for(int check = 0; check < OrdersTotal(); check++)
   {
       if(ord_info.SelectByIndex(check) && 
          ord_info.Magic() == MAGICN && 
          ord_info.Symbol() == _Symbol)
       {
           ordenesPendientesExistentes++;
       }
   }
   
   // Si ya hay órdenes pendientes, no colocar nuevas (probablemente se cambió de temporalidad)
   if(ordenesPendientesExistentes > 0)
   {
       Print("Ya existen ", ordenesPendientesExistentes, " órdenes pendientes. No se colocarán nuevas órdenes.");
       return;
   }
   
   double precioBid = 0,
          precioAsk = 0,
          precioBidOriginal = 0,
          precioAskOriginal = 0,
          precioBidInter = 0,
          precioAskInter = 0;
   int incremento_temp = increment; // Variable temporal para guardar el valor del incremento inicial
   precioBidOriginal = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   precioAskOriginal = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   // Actualizar precios base para cálculos de rango
   precioAskBase = precioAskOriginal;
   precioBidBase = precioBidOriginal;
// Conservo el precio original para resetearlo cuando vaya hacia arriba
   precioAsk = precioAskOriginal;
   precioBid = precioBidOriginal;
   double ultimoPrecioBid = precioBid,
          ultimoPrecioAsk = precioAsk;
   for(int j = 0; j < cantidadDeOperaciones; j++)
   {
      //Calcula el nuevo precio de la orden
      if(j % g_ordenesPorGrupo == 0 && j != 0)
      {
         incremento_temp += g_incrementoPorGrupo;
      }
      ultimoPrecioBid -= incremento_temp * Point();
      ultimoPrecioAsk -= incremento_temp * Point();
      // Coloco ordenes de SELLSTOP
      if(CheckMoneyForTrade(_Symbol, lot, POSITION_TYPE_SELL) && RevisarNuevaOrden() && g_tSellStop)
      {
         double tpValue = usarTPDinamico ? CalcularTakeProfitDinamico(incremento_temp) : (tpinverso * Point());
         if(!trade.SellStop(lot, NormalizeDouble(ultimoPrecioBid, _Digits), _Symbol, NormalizeDouble(ultimoPrecioAsk + (slinverso * Point()), _Digits), NormalizeDouble(ultimoPrecioAsk - tpValue, _Digits), 0, 0, "5"))
         {
            Print("Error placing SELLSTOP order: ", GetLastError());
         }
      }
      // Coloco ordenes de BUYLIMIT
      if(CheckMoneyForTrade(_Symbol, lot, POSITION_TYPE_BUY) && RevisarNuevaOrden() && g_tBuyLimit)
      {
         double tpValue = usarTPDinamico ? CalcularTakeProfitDinamico(incremento_temp) : (takeProfit * Point());
         if(!trade.BuyLimit(lot, NormalizeDouble(ultimoPrecioAsk, _Digits), _Symbol, NormalizeDouble(ultimoPrecioBid - (stopLoss * Point()), _Digits), NormalizeDouble(ultimoPrecioBid + tpValue, _Digits), 0, 0, "2"))
         {
            Print("Error placing BUYLIMIT order: ", GetLastError());
         }
      }
   }
// Resetea incremento_temp
   incremento_temp = increment;
   ultimoPrecioBid = precioBid;
   ultimoPrecioAsk = precioAsk;
   for(int i = 0; i < cantidadDeOperaciones; i++)
   {
      // Calcula el nuevo precio de la orden
      if(i % g_ordenesPorGrupo == 0 && i != 0)
      {
         incremento_temp += g_incrementoPorGrupo;
      }
      ultimoPrecioBid += incremento_temp * Point();
      ultimoPrecioAsk += incremento_temp * Point();
      // Coloco orden de SELLIMIT
      if(CheckMoneyForTrade(_Symbol, lot, POSITION_TYPE_SELL) && RevisarNuevaOrden() && g_tSellLimit)
      {
         double tpValue = usarTPDinamico ? CalcularTakeProfitDinamico(incremento_temp) : (takeProfit * Point());
         if(!trade.SellLimit(lot, NormalizeDouble(ultimoPrecioBid, _Digits), _Symbol, NormalizeDouble(ultimoPrecioAsk + (stopLoss * Point()), _Digits), NormalizeDouble(ultimoPrecioAsk - tpValue, _Digits), 0, 0, "3"))
         {
            Print("Error placing SELLLIMIT order: ", GetLastError());
         }
      }
      // Coloco orden de BUYSTOP (separado del SELLLIMIT)
      if(CheckMoneyForTrade(_Symbol, lot, POSITION_TYPE_BUY) && RevisarNuevaOrden() && g_tBuyStop)
         {
         double tpValueBS = usarTPDinamico ? CalcularTakeProfitDinamico(incremento_temp) : (tpinverso * Point());
         if(!trade.BuyStop(lot, NormalizeDouble(ultimoPrecioAsk, _Digits), _Symbol, NormalizeDouble(ultimoPrecioBid - (slinverso * Point()), _Digits), NormalizeDouble(ultimoPrecioBid + tpValueBS, _Digits), 0, 0, "4"))
            {
               Print("Error placing BUYSTOP order: ", GetLastError());
         }
      }
   }
}
//+------------------------------------------------------------------+
bool CheckMoneyForTrade (string _symb, double _lots, int _type)
{
   double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
//-- if there is not enough money
   if(free_margin < 0)
   {
      string oper = (_type == POSITION_TYPE_BUY) ? "Buy" : "Sell";
      Print("Not enough money for ", oper, " ", _lots, " ", _symb, " Error code=", GetLastError());
      return(false);
   }
//--- checking successful
   return(true);
}
//+------------------------------------------------------------------+
bool RevisarNuevaOrden ()
{
   bool _ret = false;
   int _ordenes = OrdersTotal() + PositionsTotal();
   if(_ordenes < max_allowed_orders)
   {
      _ret = true;
   }
   return (_ret);
}
//+------------------------------------------------------------------+
void ReponerOrdenes()
{
    // Obtener precios actuales
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double diferenciaBidAsk = ask - bid;
    
    // Seleccionar historial desde la última referencia
    if(!HistorySelect(tiempo_ref, TimeCurrent()))
        return;
        
    int ordenesCerradas = HistoryDealsTotal();
    if(ordenesCerradas <= indiceCerradas)
        return;
        
    // Estructura para almacenar información de la orden
    struct OrderInfo {
        string comment;
        double price;
        double sl;
        double tp;
        long positionId;
        bool isProfit;
    };
    
    // Procesar nuevas órdenes cerradas
      for(int k = indiceCerradas; k < ordenesCerradas; k++)
      {
        if(!deals_info.SelectByIndex(k) || deals_info.Entry() != DEAL_ENTRY_OUT || deals_info.Magic() != MAGICN)
               continue;
            
        OrderInfo order;
        order.comment = deals_info.Comment();
        order.positionId = deals_info.PositionId();
        order.isProfit = (deals_info.Profit() > 0);
        
        // Obtener precio de entrada
                     for(int i = ordenesCerradas - 1; i >= 0; i--)
                     {
            if(!deals_info.SelectByIndex(i))
                           continue;
                
            if(deals_info.PositionId() == order.positionId && deals_info.Entry() == DEAL_ENTRY_OUT)
            {
                order.price = deals_info.Price();
                order.sl = HistoryDealGetDouble(deals_info.Ticket(), DEAL_SL);
                order.tp = HistoryDealGetDouble(deals_info.Ticket(), DEAL_TP);
                        break;
                     }
                  }
        
        // Reponer órdenes según el tipo
                  if(RevisarNuevaOrden())
                  {
            // SELLSTOP - Verificar si reposición de Stops está activada
            if(StringFind(order.comment, "5") == 0)
            {
                if(g_reponerStops)  // Solo reponer si está activado
            {
                if(order.isProfit)
                    {
                        // Si ganó, convertir a SellLimit (pero solo si reposición de Limits está activada)
                        if(g_reponerLimits)
                {
                    trade.SellLimit(lot, 
                        NormalizeDouble(order.price, _Digits),
                        _Symbol,
                        NormalizeDouble(order.price + diferenciaBidAsk + (stopLoss * Point()), _Digits),
                        NormalizeDouble(order.price + diferenciaBidAsk - (takeProfit * Point()), _Digits),
                        0, 0, "3");
                        }
                }
                else if(CheckMoneyForTrade(_Symbol, lot, POSITION_TYPE_SELL))
                {
                    trade.SellStop(lot,
                        NormalizeDouble(order.price, _Digits),
                        _Symbol,
                        NormalizeDouble(order.sl, _Digits),
                        NormalizeDouble(order.tp, _Digits),
                        0, 0, "5");
                }
            }
            }
            // BUYLIMIT - Verificar si reposición de Limits está activada
            else if(StringFind(order.comment, "2") == 0 && CheckMoneyForTrade(_Symbol, lot, POSITION_TYPE_BUY))
            {
                if(g_reponerLimits)  // Solo reponer si está activado
            {
                trade.BuyLimit(lot,
                    NormalizeDouble(order.price, _Digits),
                    _Symbol,
                    NormalizeDouble(order.sl, _Digits),
                    NormalizeDouble(order.tp, _Digits),
                    0, 0, "2");
            }
            }
            // SELLLIMIT - Verificar si reposición de Limits está activada
            else if(StringFind(order.comment, "3") == 0 && CheckMoneyForTrade(_Symbol, lot, POSITION_TYPE_SELL))
            {
                if(g_reponerLimits)  // Solo reponer si está activado
            {
                trade.SellLimit(lot,
                    NormalizeDouble(order.price, _Digits),
                    _Symbol,
                    NormalizeDouble(order.sl, _Digits),
                    NormalizeDouble(order.tp, _Digits),
                    0, 0, "3");
            }
            }
            // BUYSTOP - Verificar si reposición de Stops está activada
            else if(StringFind(order.comment, "4") == 0)
            {
                if(g_reponerStops)  // Solo reponer si está activado
            {
                if(order.isProfit)
                    {
                        // Si ganó, convertir a BuyLimit (pero solo si reposición de Limits está activada)
                        if(g_reponerLimits)
                {
                    trade.BuyLimit(lot,
                        NormalizeDouble(order.price, _Digits),
                        _Symbol,
                        NormalizeDouble(order.price - diferenciaBidAsk - (stop_loss * Point()), _Digits),
                        NormalizeDouble(order.price - diferenciaBidAsk + (take_profit * Point()), _Digits),
                        0, 0, "2");
                        }
                }
                else if(CheckMoneyForTrade(_Symbol, lot, POSITION_TYPE_BUY))
                {
                    trade.BuyStop(lot,
                        NormalizeDouble(order.price, _Digits),
                        _Symbol,
                        NormalizeDouble(order.sl, _Digits),
                        NormalizeDouble(order.tp, _Digits),
                        0, 0, "4");
                    }
                }
            }
        }
        l++;
    }
   indiceCerradas = l;
}
//+------------------------------------------------------------------+
bool CompararGanancia ()
{
   bool ret = false;
   double equidad = AccountInfoDouble(ACCOUNT_EQUITY);
// Print("equity = "+ equidad + "balance objetivo: "+ balanceObjetivo);
   if(balanceObjetivo <= equidad)
   {
      ret = true;
   }
   return ret;
}
//+------------------------------------------------------------------+
//| FUNCIONES PARA PANEL DE CONTROL DE TIPOS DE ÓRDENES              |
//+------------------------------------------------------------------+
//| NUEVA FUNCIONALIDAD: Sistema de control gráfico que permite       |
//| activar/desactivar tipos de órdenes en tiempo real y ver          |
//| estadísticas detalladas.                                          |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Contar Órdenes por Tipo                                          |
//+------------------------------------------------------------------+
//| Cuenta las órdenes activas y pendientes de cada tipo para        |
//| mostrarlas en el panel de control.                                |
//|                                                                   |
//| Parámetros de salida:                                             |
//| - buyStopActivas/Pendientes: Contadores para BuyStop             |
//| - buyLimitActivas/Pendientes: Contadores para BuyLimit            |
//| - sellStopActivas/Pendientes: Contadores para SellStop           |
//| - sellLimitActivas/Pendientes: Contadores para SellLimit          |
//+------------------------------------------------------------------+
void ContarOrdenesPorTipo(int &buyStopActivas, int &buyStopPendientes,
                          int &buyLimitActivas, int &buyLimitPendientes,
                          int &sellStopActivas, int &sellStopPendientes,
                          int &sellLimitActivas, int &sellLimitPendientes)
{
    buyStopActivas = 0; buyStopPendientes = 0;
    buyLimitActivas = 0; buyLimitPendientes = 0;
    sellStopActivas = 0; sellStopPendientes = 0;
    sellLimitActivas = 0; sellLimitPendientes = 0;
    
    // Seleccionar historial de deals para identificar el tipo original por comentario
    datetime desde = TimeCurrent() - PeriodSeconds(PERIOD_D1) * 30; // Últimos 30 días para mayor cobertura
    HistorySelect(desde, TimeCurrent());
    
    // Contar posiciones abiertas - filtrar por Magic Number Y Símbolo
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(pos_info.SelectByIndex(i) && 
           pos_info.Magic() == MAGICN && 
           pos_info.Symbol() == _Symbol)  // Solo del activo actual
        {
            ulong positionId = pos_info.Identifier();
            string comentarioTipo = "";
            
            // Buscar el deal de entrada (DEAL_ENTRY_IN) para esta posición
            // Buscar desde el más reciente hacia atrás
            for(int j = HistoryDealsTotal() - 1; j >= 0; j--)
            {
                ulong dealTicket = HistoryDealGetTicket(j);
                if(dealTicket == 0) continue;
                
                if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) == MAGICN &&
                   HistoryDealGetString(dealTicket, DEAL_SYMBOL) == _Symbol &&
                   HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID) == positionId &&
                   HistoryDealGetInteger(dealTicket, DEAL_ENTRY) == DEAL_ENTRY_IN)
                {
                    comentarioTipo = HistoryDealGetString(dealTicket, DEAL_COMMENT);
                    break; // Encontrado, salir del bucle
                }
            }
            
            // Identificar tipo según comentario: "2"=BuyLimit, "3"=SellLimit, "4"=BuyStop, "5"=SellStop
            // Buscar el número en cualquier parte del comentario (más flexible)
            if(pos_info.Type() == POSITION_TYPE_BUY)
            {
                // Buscar "4" o "2" en el comentario
                if(StringFind(comentarioTipo, "4") >= 0)  // Contiene "4" (BuyStop)
                    buyStopActivas++;
                else if(StringFind(comentarioTipo, "2") >= 0)  // Contiene "2" (BuyLimit)
                    buyLimitActivas++;
                // Si no encontramos comentario, no contar para evitar errores
            }
            else if(pos_info.Type() == POSITION_TYPE_SELL)
            {
                // Buscar "5" o "3" en el comentario
                if(StringFind(comentarioTipo, "5") >= 0)  // Contiene "5" (SellStop)
                    sellStopActivas++;
                else if(StringFind(comentarioTipo, "3") >= 0)  // Contiene "3" (SellLimit)
                    sellLimitActivas++;
                // Si no encontramos comentario, no contar para evitar errores
            }
        }
    }
    
    // Contar órdenes pendientes - filtrar por Magic Number Y Símbolo
    for(int i = 0; i < OrdersTotal(); i++)
    {
        if(ord_info.SelectByIndex(i) && 
           ord_info.Magic() == MAGICN && 
           ord_info.Symbol() == _Symbol)  // Solo del activo actual
        {
            if(ord_info.Type() == ORDER_TYPE_BUY_STOP)
                buyStopPendientes++;
            else if(ord_info.Type() == ORDER_TYPE_BUY_LIMIT)
                buyLimitPendientes++;
            else if(ord_info.Type() == ORDER_TYPE_SELL_STOP)
                sellStopPendientes++;
            else if(ord_info.Type() == ORDER_TYPE_SELL_LIMIT)
                sellLimitPendientes++;
        }
    }
}

//+------------------------------------------------------------------+
//| Crear Panel de Control                                           |
//+------------------------------------------------------------------+
//| Crea la interfaz gráfica con botones para activar/desactivar     |
//| cada tipo de orden y mostrar contadores en tiempo real.           |
//|                                                                   |
//| Componentes del panel:                                            |
//| - 4 botones toggle (ON/OFF) para cada tipo de orden              |
//| - Contadores mostrando órdenes activas y pendientes               |
//| - Botón "Aplicar" para confirmar cambios                         |
//| - Botón "Quitar Ordenes" para abrir panel de eliminación         |
//+------------------------------------------------------------------+
void CrearPanelControl()
{
    // Fondo del panel - diseño minimalista
    ObjectCreate(0, PANEL_CONTROL + "Fondo", OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(0, PANEL_CONTROL + "Fondo", OBJPROP_XDISTANCE, PANEL_CONTROL_X);
    ObjectSetInteger(0, PANEL_CONTROL + "Fondo", OBJPROP_YDISTANCE, PANEL_CONTROL_Y);
    ObjectSetInteger(0, PANEL_CONTROL + "Fondo", OBJPROP_XSIZE, PANEL_CONTROL_WIDTH);
    ObjectSetInteger(0, PANEL_CONTROL + "Fondo", OBJPROP_YSIZE, PANEL_CONTROL_HEIGHT);
    ObjectSetInteger(0, PANEL_CONTROL + "Fondo", OBJPROP_BGCOLOR, C'30,30,35'); // Fondo oscuro simple
    ObjectSetInteger(0, PANEL_CONTROL + "Fondo", OBJPROP_CORNER, CORNER_LEFT_UPPER); // Esquina superior izquierda
    ObjectSetInteger(0, PANEL_CONTROL + "Fondo", OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(0, PANEL_CONTROL + "Fondo", OBJPROP_COLOR, C'60,60,70'); // Borde sutil
    ObjectSetInteger(0, PANEL_CONTROL + "Fondo", OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, PANEL_CONTROL + "Fondo", OBJPROP_WIDTH, 1);
    ObjectSetInteger(0, PANEL_CONTROL + "Fondo", OBJPROP_BACK, false);
    ObjectSetInteger(0, PANEL_CONTROL + "Fondo", OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, PANEL_CONTROL + "Fondo", OBJPROP_ZORDER, 0);  // Fondo en capa inferior
    
    // Título simple - sin barra de fondo
    ObjectCreate(0, PANEL_CONTROL + "Titulo", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, PANEL_CONTROL + "Titulo", OBJPROP_XDISTANCE, PANEL_CONTROL_X + 10);
    ObjectSetInteger(0, PANEL_CONTROL + "Titulo", OBJPROP_YDISTANCE, PANEL_CONTROL_Y + 8);
    ObjectSetInteger(0, PANEL_CONTROL + "Titulo", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetString(0, PANEL_CONTROL + "Titulo", OBJPROP_TEXT, "Control de Ordenes");
    ObjectSetString(0, PANEL_CONTROL + "Titulo", OBJPROP_FONT, "Arial");
    ObjectSetInteger(0, PANEL_CONTROL + "Titulo", OBJPROP_FONTSIZE, 11);
    ObjectSetInteger(0, PANEL_CONTROL + "Titulo", OBJPROP_COLOR, C'200,200,200');
    
    // Diseño minimalista - sin fondos de fila, sin LEDs, solo lo esencial
    int yPos = 32;
    string tipos[] = {"BuyStop", "BuyLimit", "SellStop", "SellLimit"};
    string nombresDisplay[] = {"BuyStop", "BuyLimit", "SellStop", "SellLimit"};
    string botones[] = {BOTON_BUYSTOP, BOTON_BUYLIMIT, BOTON_SELLSTOP, BOTON_SELLLIMIT};
    bool estados[] = {g_tBuyStop, g_tBuyLimit, g_tSellStop, g_tSellLimit};
    
    // Posiciones fijas y simples
    int labelX = 10;
    int buttonX = 100;
    int countX = 180;
    
    for(int i = 0; i < 4; i++)
    {
        // Etiqueta simple
        ObjectCreate(0, PANEL_CONTROL + tipos[i] + "Label", OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, PANEL_CONTROL + tipos[i] + "Label", OBJPROP_XDISTANCE, PANEL_CONTROL_X + labelX);
        ObjectSetInteger(0, PANEL_CONTROL + tipos[i] + "Label", OBJPROP_YDISTANCE, PANEL_CONTROL_Y + yPos);
        ObjectSetInteger(0, PANEL_CONTROL + tipos[i] + "Label", OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetString(0, PANEL_CONTROL + tipos[i] + "Label", OBJPROP_TEXT, nombresDisplay[i] + ":");
        ObjectSetString(0, PANEL_CONTROL + tipos[i] + "Label", OBJPROP_FONT, "Arial");
        ObjectSetInteger(0, PANEL_CONTROL + tipos[i] + "Label", OBJPROP_FONTSIZE, 9);
        ObjectSetInteger(0, PANEL_CONTROL + tipos[i] + "Label", OBJPROP_COLOR, C'180,180,180');
        
        // Botón toggle simple
        ObjectCreate(0, botones[i], OBJ_BUTTON, 0, 0, 0);
        ObjectSetInteger(0, botones[i], OBJPROP_XDISTANCE, PANEL_CONTROL_X + buttonX);
        ObjectSetInteger(0, botones[i], OBJPROP_YDISTANCE, PANEL_CONTROL_Y + yPos - 2);
        ObjectSetInteger(0, botones[i], OBJPROP_XSIZE, 50);
        ObjectSetInteger(0, botones[i], OBJPROP_YSIZE, 20);
        ObjectSetInteger(0, botones[i], OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetString(0, botones[i], OBJPROP_TEXT, estados[i] ? "ON" : "OFF");
        ObjectSetInteger(0, botones[i], OBJPROP_BGCOLOR, estados[i] ? C'0,120,0' : C'80,80,80');
        ObjectSetInteger(0, botones[i], OBJPROP_COLOR, clrWhite);
        ObjectSetString(0, botones[i], OBJPROP_FONT, "Arial");
        ObjectSetInteger(0, botones[i], OBJPROP_FONTSIZE, 8);
        ObjectSetInteger(0, botones[i], OBJPROP_SELECTABLE, true);
        
        // Los contadores A:P solo se muestran en el panel de estadísticas, no aquí
        
        yPos += 28; // Espaciado compacto
    }
    
    yPos += 8;
    
    // Separador visual
    ObjectCreate(0, PANEL_CONTROL + "Separador1", OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(0, PANEL_CONTROL + "Separador1", OBJPROP_XDISTANCE, PANEL_CONTROL_X + 5);
    ObjectSetInteger(0, PANEL_CONTROL + "Separador1", OBJPROP_YDISTANCE, PANEL_CONTROL_Y + yPos);
    ObjectSetInteger(0, PANEL_CONTROL + "Separador1", OBJPROP_XSIZE, PANEL_CONTROL_WIDTH - 10);
    ObjectSetInteger(0, PANEL_CONTROL + "Separador1", OBJPROP_YSIZE, 1);
    ObjectSetInteger(0, PANEL_CONTROL + "Separador1", OBJPROP_BGCOLOR, C'60,60,70');
    ObjectSetInteger(0, PANEL_CONTROL + "Separador1", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, PANEL_CONTROL + "Separador1", OBJPROP_BACK, false);
    
    yPos += 12;
    
    // Toggle Reponer Limits
    ObjectCreate(0, "BtnReponerLimits", OBJ_BUTTON, 0, 0, 0);
    ObjectSetInteger(0, "BtnReponerLimits", OBJPROP_XDISTANCE, PANEL_CONTROL_X + 10);
    ObjectSetInteger(0, "BtnReponerLimits", OBJPROP_YDISTANCE, PANEL_CONTROL_Y + yPos);
    ObjectSetInteger(0, "BtnReponerLimits", OBJPROP_XSIZE, 140);
    ObjectSetInteger(0, "BtnReponerLimits", OBJPROP_YSIZE, 22);
    ObjectSetInteger(0, "BtnReponerLimits", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetString(0, "BtnReponerLimits", OBJPROP_TEXT, g_reponerLimits ? "Reponer Limits: ON" : "Reponer Limits: OFF");
    ObjectSetInteger(0, "BtnReponerLimits", OBJPROP_BGCOLOR, g_reponerLimits ? C'0,120,0' : C'80,80,80');
    ObjectSetInteger(0, "BtnReponerLimits", OBJPROP_COLOR, clrWhite);
    ObjectSetString(0, "BtnReponerLimits", OBJPROP_FONT, "Arial");
    ObjectSetInteger(0, "BtnReponerLimits", OBJPROP_FONTSIZE, 8);
    ObjectSetInteger(0, "BtnReponerLimits", OBJPROP_SELECTABLE, true);
    
    yPos += 26;
    
    // Toggle Reponer Stops
    ObjectCreate(0, "BtnReponerStops", OBJ_BUTTON, 0, 0, 0);
    ObjectSetInteger(0, "BtnReponerStops", OBJPROP_XDISTANCE, PANEL_CONTROL_X + 10);
    ObjectSetInteger(0, "BtnReponerStops", OBJPROP_YDISTANCE, PANEL_CONTROL_Y + yPos);
    ObjectSetInteger(0, "BtnReponerStops", OBJPROP_XSIZE, 140);
    ObjectSetInteger(0, "BtnReponerStops", OBJPROP_YSIZE, 22);
    ObjectSetInteger(0, "BtnReponerStops", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetString(0, "BtnReponerStops", OBJPROP_TEXT, g_reponerStops ? "Reponer Stops: ON" : "Reponer Stops: OFF");
    ObjectSetInteger(0, "BtnReponerStops", OBJPROP_BGCOLOR, g_reponerStops ? C'0,120,0' : C'80,80,80');
    ObjectSetInteger(0, "BtnReponerStops", OBJPROP_COLOR, clrWhite);
    ObjectSetString(0, "BtnReponerStops", OBJPROP_FONT, "Arial");
    ObjectSetInteger(0, "BtnReponerStops", OBJPROP_FONTSIZE, 8);
    ObjectSetInteger(0, "BtnReponerStops", OBJPROP_SELECTABLE, true);
    
    yPos += 30;
    
    // Separador visual 2
    ObjectCreate(0, PANEL_CONTROL + "Separador2", OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(0, PANEL_CONTROL + "Separador2", OBJPROP_XDISTANCE, PANEL_CONTROL_X + 5);
    ObjectSetInteger(0, PANEL_CONTROL + "Separador2", OBJPROP_YDISTANCE, PANEL_CONTROL_Y + yPos);
    ObjectSetInteger(0, PANEL_CONTROL + "Separador2", OBJPROP_XSIZE, PANEL_CONTROL_WIDTH - 10);
    ObjectSetInteger(0, PANEL_CONTROL + "Separador2", OBJPROP_YSIZE, 1);
    ObjectSetInteger(0, PANEL_CONTROL + "Separador2", OBJPROP_BGCOLOR, C'60,60,70');
    ObjectSetInteger(0, PANEL_CONTROL + "Separador2", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, PANEL_CONTROL + "Separador2", OBJPROP_BACK, false);
    
    yPos += 12;
    
    // Campo Órdenes por Grupo - con botones +/- para modificar
    ObjectCreate(0, "LabelOrdenesGrupo", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, "LabelOrdenesGrupo", OBJPROP_XDISTANCE, PANEL_CONTROL_X + 10);
    ObjectSetInteger(0, "LabelOrdenesGrupo", OBJPROP_YDISTANCE, PANEL_CONTROL_Y + yPos);
    ObjectSetInteger(0, "LabelOrdenesGrupo", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetString(0, "LabelOrdenesGrupo", OBJPROP_TEXT, "Órdenes por Grupo:");
    ObjectSetString(0, "LabelOrdenesGrupo", OBJPROP_FONT, "Arial");
    ObjectSetInteger(0, "LabelOrdenesGrupo", OBJPROP_FONTSIZE, 8);
    ObjectSetInteger(0, "LabelOrdenesGrupo", OBJPROP_COLOR, C'180,180,180');
    
    // Botón menos
    ObjectCreate(0, "BtnOrdenesGrupoMenos", OBJ_BUTTON, 0, 0, 0);
    ObjectSetInteger(0, "BtnOrdenesGrupoMenos", OBJPROP_XDISTANCE, PANEL_CONTROL_X + 130);
    ObjectSetInteger(0, "BtnOrdenesGrupoMenos", OBJPROP_YDISTANCE, PANEL_CONTROL_Y + yPos - 2);
    ObjectSetInteger(0, "BtnOrdenesGrupoMenos", OBJPROP_XSIZE, 25);
    ObjectSetInteger(0, "BtnOrdenesGrupoMenos", OBJPROP_YSIZE, 20);
    ObjectSetInteger(0, "BtnOrdenesGrupoMenos", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetString(0, "BtnOrdenesGrupoMenos", OBJPROP_TEXT, "-");
    ObjectSetInteger(0, "BtnOrdenesGrupoMenos", OBJPROP_BGCOLOR, C'100,100,100');
    ObjectSetInteger(0, "BtnOrdenesGrupoMenos", OBJPROP_COLOR, clrWhite);
    ObjectSetString(0, "BtnOrdenesGrupoMenos", OBJPROP_FONT, "Arial Bold");
    ObjectSetInteger(0, "BtnOrdenesGrupoMenos", OBJPROP_FONTSIZE, 10);
    ObjectSetInteger(0, "BtnOrdenesGrupoMenos", OBJPROP_SELECTABLE, true);
    
    // Valor mostrado - centrado entre los botones
    // Botón - termina en: 130 + 25 = 155
    // Botón + empieza en: 185
    // Centro: (155 + 185) / 2 = 170
    ObjectCreate(0, "ValorOrdenesGrupo", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, "ValorOrdenesGrupo", OBJPROP_XDISTANCE, PANEL_CONTROL_X + 170);
    ObjectSetInteger(0, "ValorOrdenesGrupo", OBJPROP_YDISTANCE, PANEL_CONTROL_Y + yPos);
    ObjectSetInteger(0, "ValorOrdenesGrupo", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetString(0, "ValorOrdenesGrupo", OBJPROP_TEXT, IntegerToString(g_ordenesPorGrupo));
    ObjectSetString(0, "ValorOrdenesGrupo", OBJPROP_FONT, "Arial Bold");
    ObjectSetInteger(0, "ValorOrdenesGrupo", OBJPROP_FONTSIZE, 9);
    ObjectSetInteger(0, "ValorOrdenesGrupo", OBJPROP_COLOR, clrWhite);
    ObjectSetInteger(0, "ValorOrdenesGrupo", OBJPROP_ANCHOR, ANCHOR_CENTER);
    
    // Botón más
    ObjectCreate(0, "BtnOrdenesGrupoMas", OBJ_BUTTON, 0, 0, 0);
    ObjectSetInteger(0, "BtnOrdenesGrupoMas", OBJPROP_XDISTANCE, PANEL_CONTROL_X + 185);
    ObjectSetInteger(0, "BtnOrdenesGrupoMas", OBJPROP_YDISTANCE, PANEL_CONTROL_Y + yPos - 2);
    ObjectSetInteger(0, "BtnOrdenesGrupoMas", OBJPROP_XSIZE, 25);
    ObjectSetInteger(0, "BtnOrdenesGrupoMas", OBJPROP_YSIZE, 20);
    ObjectSetInteger(0, "BtnOrdenesGrupoMas", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetString(0, "BtnOrdenesGrupoMas", OBJPROP_TEXT, "+");
    ObjectSetInteger(0, "BtnOrdenesGrupoMas", OBJPROP_BGCOLOR, C'100,100,100');
    ObjectSetInteger(0, "BtnOrdenesGrupoMas", OBJPROP_COLOR, clrWhite);
    ObjectSetString(0, "BtnOrdenesGrupoMas", OBJPROP_FONT, "Arial Bold");
    ObjectSetInteger(0, "BtnOrdenesGrupoMas", OBJPROP_FONTSIZE, 10);
    ObjectSetInteger(0, "BtnOrdenesGrupoMas", OBJPROP_SELECTABLE, true);
    
    yPos += 25;
    
    // Campo Incremento por Grupo - con botones +/- para modificar
    ObjectCreate(0, "LabelIncrementoGrupo", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, "LabelIncrementoGrupo", OBJPROP_XDISTANCE, PANEL_CONTROL_X + 10);
    ObjectSetInteger(0, "LabelIncrementoGrupo", OBJPROP_YDISTANCE, PANEL_CONTROL_Y + yPos);
    ObjectSetInteger(0, "LabelIncrementoGrupo", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetString(0, "LabelIncrementoGrupo", OBJPROP_TEXT, "Incremento por Grupo:");
    ObjectSetString(0, "LabelIncrementoGrupo", OBJPROP_FONT, "Arial");
    ObjectSetInteger(0, "LabelIncrementoGrupo", OBJPROP_FONTSIZE, 8);
    ObjectSetInteger(0, "LabelIncrementoGrupo", OBJPROP_COLOR, C'180,180,180');
    
    // Botón menos
    ObjectCreate(0, "BtnIncrementoGrupoMenos", OBJ_BUTTON, 0, 0, 0);
    ObjectSetInteger(0, "BtnIncrementoGrupoMenos", OBJPROP_XDISTANCE, PANEL_CONTROL_X + 130);
    ObjectSetInteger(0, "BtnIncrementoGrupoMenos", OBJPROP_YDISTANCE, PANEL_CONTROL_Y + yPos - 2);
    ObjectSetInteger(0, "BtnIncrementoGrupoMenos", OBJPROP_XSIZE, 25);
    ObjectSetInteger(0, "BtnIncrementoGrupoMenos", OBJPROP_YSIZE, 20);
    ObjectSetInteger(0, "BtnIncrementoGrupoMenos", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetString(0, "BtnIncrementoGrupoMenos", OBJPROP_TEXT, "-");
    ObjectSetInteger(0, "BtnIncrementoGrupoMenos", OBJPROP_BGCOLOR, C'100,100,100');
    ObjectSetInteger(0, "BtnIncrementoGrupoMenos", OBJPROP_COLOR, clrWhite);
    ObjectSetString(0, "BtnIncrementoGrupoMenos", OBJPROP_FONT, "Arial Bold");
    ObjectSetInteger(0, "BtnIncrementoGrupoMenos", OBJPROP_FONTSIZE, 10);
    ObjectSetInteger(0, "BtnIncrementoGrupoMenos", OBJPROP_SELECTABLE, true);
    
    // Valor mostrado - centrado entre los botones
    // Botón - termina en: 130 + 25 = 155
    // Botón + empieza en: 185
    // Centro: (155 + 185) / 2 = 170
    ObjectCreate(0, "ValorIncrementoGrupo", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, "ValorIncrementoGrupo", OBJPROP_XDISTANCE, PANEL_CONTROL_X + 170);
    ObjectSetInteger(0, "ValorIncrementoGrupo", OBJPROP_YDISTANCE, PANEL_CONTROL_Y + yPos);
    ObjectSetInteger(0, "ValorIncrementoGrupo", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetString(0, "ValorIncrementoGrupo", OBJPROP_TEXT, IntegerToString(g_incrementoPorGrupo));
    ObjectSetString(0, "ValorIncrementoGrupo", OBJPROP_FONT, "Arial Bold");
    ObjectSetInteger(0, "ValorIncrementoGrupo", OBJPROP_FONTSIZE, 9);
    ObjectSetInteger(0, "ValorIncrementoGrupo", OBJPROP_COLOR, clrWhite);
    ObjectSetInteger(0, "ValorIncrementoGrupo", OBJPROP_ANCHOR, ANCHOR_CENTER);
    
    // Botón más
    ObjectCreate(0, "BtnIncrementoGrupoMas", OBJ_BUTTON, 0, 0, 0);
    ObjectSetInteger(0, "BtnIncrementoGrupoMas", OBJPROP_XDISTANCE, PANEL_CONTROL_X + 185);
    ObjectSetInteger(0, "BtnIncrementoGrupoMas", OBJPROP_YDISTANCE, PANEL_CONTROL_Y + yPos - 2);
    ObjectSetInteger(0, "BtnIncrementoGrupoMas", OBJPROP_XSIZE, 25);
    ObjectSetInteger(0, "BtnIncrementoGrupoMas", OBJPROP_YSIZE, 20);
    ObjectSetInteger(0, "BtnIncrementoGrupoMas", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetString(0, "BtnIncrementoGrupoMas", OBJPROP_TEXT, "+");
    ObjectSetInteger(0, "BtnIncrementoGrupoMas", OBJPROP_BGCOLOR, C'100,100,100');
    ObjectSetInteger(0, "BtnIncrementoGrupoMas", OBJPROP_COLOR, clrWhite);
    ObjectSetString(0, "BtnIncrementoGrupoMas", OBJPROP_FONT, "Arial Bold");
    ObjectSetInteger(0, "BtnIncrementoGrupoMas", OBJPROP_FONTSIZE, 10);
    ObjectSetInteger(0, "BtnIncrementoGrupoMas", OBJPROP_SELECTABLE, true);
    
    yPos += 30;
    
    // Botones simples y minimalistas
    ObjectCreate(0, BTN_APLICAR, OBJ_BUTTON, 0, 0, 0);
    ObjectSetInteger(0, BTN_APLICAR, OBJPROP_XDISTANCE, PANEL_CONTROL_X + 10);
    ObjectSetInteger(0, BTN_APLICAR, OBJPROP_YDISTANCE, PANEL_CONTROL_Y + yPos);
    ObjectSetInteger(0, BTN_APLICAR, OBJPROP_XSIZE, 130);
    ObjectSetInteger(0, BTN_APLICAR, OBJPROP_YSIZE, 24);
    ObjectSetInteger(0, BTN_APLICAR, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetString(0, BTN_APLICAR, OBJPROP_TEXT, "Aplicar");
    ObjectSetInteger(0, BTN_APLICAR, OBJPROP_BGCOLOR, C'60,100,150');
    ObjectSetInteger(0, BTN_APLICAR, OBJPROP_COLOR, clrWhite);
    ObjectSetString(0, BTN_APLICAR, OBJPROP_FONT, "Arial");
    ObjectSetInteger(0, BTN_APLICAR, OBJPROP_FONTSIZE, 9);
    ObjectSetInteger(0, BTN_APLICAR, OBJPROP_SELECTABLE, true);
    
    ObjectCreate(0, "BtnQuitaOrdenes", OBJ_BUTTON, 0, 0, 0);
    ObjectSetInteger(0, "BtnQuitaOrdenes", OBJPROP_XDISTANCE, PANEL_CONTROL_X + 150);
    ObjectSetInteger(0, "BtnQuitaOrdenes", OBJPROP_YDISTANCE, PANEL_CONTROL_Y + yPos);
    ObjectSetInteger(0, "BtnQuitaOrdenes", OBJPROP_XSIZE, 130);
    ObjectSetInteger(0, "BtnQuitaOrdenes", OBJPROP_YSIZE, 24);
    ObjectSetInteger(0, "BtnQuitaOrdenes", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetString(0, "BtnQuitaOrdenes", OBJPROP_TEXT, "Eliminar");
    ObjectSetInteger(0, "BtnQuitaOrdenes", OBJPROP_BGCOLOR, C'150,60,60');
    ObjectSetInteger(0, "BtnQuitaOrdenes", OBJPROP_COLOR, clrWhite);
    ObjectSetString(0, "BtnQuitaOrdenes", OBJPROP_FONT, "Arial");
    ObjectSetInteger(0, "BtnQuitaOrdenes", OBJPROP_FONTSIZE, 9);
    ObjectSetInteger(0, "BtnQuitaOrdenes", OBJPROP_SELECTABLE, true);
}

// Función para actualizar el panel de control
void ActualizarPanelControl()
{
    // Actualizar botones - los contadores A:P solo se muestran en el panel de estadísticas
    string botones[] = {BOTON_BUYSTOP, BOTON_BUYLIMIT, BOTON_SELLSTOP, BOTON_SELLLIMIT};
    bool estados[] = {g_tBuyStop, g_tBuyLimit, g_tSellStop, g_tSellLimit};
    
    for(int i = 0; i < 4; i++)
    {
        // Actualizar botón - diseño minimalista
        ObjectSetString(0, botones[i], OBJPROP_TEXT, estados[i] ? "ON" : "OFF");
        ObjectSetInteger(0, botones[i], OBJPROP_BGCOLOR, estados[i] ? C'0,120,0' : C'80,80,80');
    }
    
    // Actualizar valores de órdenes por grupo e incremento por grupo
    ObjectSetString(0, "ValorOrdenesGrupo", OBJPROP_TEXT, IntegerToString(g_ordenesPorGrupo));
    ObjectSetString(0, "ValorIncrementoGrupo", OBJPROP_TEXT, IntegerToString(g_incrementoPorGrupo));
}

//+------------------------------------------------------------------+
//| Crear Panel de Eliminación de Órdenes                            |
//+------------------------------------------------------------------+
//| NUEVA FUNCIONALIDAD: Panel gráfico para buscar y eliminar        |
//| órdenes filtradas por Magic Number.                              |
//|                                                                   |
//| Funcionalidades:                                                  |
//| - Buscar órdenes por Magic Number                                |
//| - Listar todas las órdenes encontradas (activas y pendientes)    |
//| - Eliminar todas las órdenes de un Magic Number                  |
//| - Cerrar el panel                                                 |
//+------------------------------------------------------------------+
void CrearPanelQuitaOrdenes()
{
    if(panelQuitaVisible)
    {
        OcultarPanelQuitaOrdenes();
        return;
    }
    
    panelQuitaVisible = true;
    
    // Calcular márgenes para centrar elementos dentro del panel
    const int margenIzquierdo = 15;
    const int margenSuperior = 15;
    const int espacioEntreBotones = 10;
    const int anchoBoton = 110;
    
    // Fondo - centrado en el gráfico
    ObjectCreate(0, PANEL_QUITAORDENES + "Fondo", OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(0, PANEL_QUITAORDENES + "Fondo", OBJPROP_XDISTANCE, PANEL_QUITA_X);
    ObjectSetInteger(0, PANEL_QUITAORDENES + "Fondo", OBJPROP_YDISTANCE, PANEL_QUITA_Y);
    ObjectSetInteger(0, PANEL_QUITAORDENES + "Fondo", OBJPROP_XSIZE, PANEL_QUITA_WIDTH);
    ObjectSetInteger(0, PANEL_QUITAORDENES + "Fondo", OBJPROP_YSIZE, PANEL_QUITA_HEIGHT);
    ObjectSetInteger(0, PANEL_QUITAORDENES + "Fondo", OBJPROP_BGCOLOR, COLOR_FONDO);
    ObjectSetInteger(0, PANEL_QUITAORDENES + "Fondo", OBJPROP_CORNER, CORNER_LEFT_UPPER);  // Esquina superior izquierda para facilitar centrado
    ObjectSetInteger(0, PANEL_QUITAORDENES + "Fondo", OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(0, PANEL_QUITAORDENES + "Fondo", OBJPROP_COLOR, clrWhite);
    ObjectSetInteger(0, PANEL_QUITAORDENES + "Fondo", OBJPROP_BACK, false);
    ObjectSetInteger(0, PANEL_QUITAORDENES + "Fondo", OBJPROP_SELECTABLE, false);
    
    // Título - centrado horizontalmente
    ObjectCreate(0, PANEL_QUITAORDENES + "Titulo", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, PANEL_QUITAORDENES + "Titulo", OBJPROP_XDISTANCE, PANEL_QUITA_X + margenIzquierdo);
    ObjectSetInteger(0, PANEL_QUITAORDENES + "Titulo", OBJPROP_YDISTANCE, PANEL_QUITA_Y + margenSuperior);
    ObjectSetInteger(0, PANEL_QUITAORDENES + "Titulo", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetString(0, PANEL_QUITAORDENES + "Titulo", OBJPROP_TEXT, "Eliminar Ordenes por Magic Number");
    ObjectSetInteger(0, PANEL_QUITAORDENES + "Titulo", OBJPROP_COLOR, COLOR_TEXTO);
    ObjectSetString(0, PANEL_QUITAORDENES + "Titulo", OBJPROP_FONT, "Arial Bold");
    ObjectSetInteger(0, PANEL_QUITAORDENES + "Titulo", OBJPROP_FONTSIZE, 12);
    
    // Campo de entrada (simulado con label)
    ObjectCreate(0, INPUT_MAGIC + "Label", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, INPUT_MAGIC + "Label", OBJPROP_XDISTANCE, PANEL_QUITA_X + margenIzquierdo);
    ObjectSetInteger(0, INPUT_MAGIC + "Label", OBJPROP_YDISTANCE, PANEL_QUITA_Y + margenSuperior + 35);
    ObjectSetInteger(0, INPUT_MAGIC + "Label", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetString(0, INPUT_MAGIC + "Label", OBJPROP_TEXT, "Magic Number: " + IntegerToString(MAGICN));
    ObjectSetInteger(0, INPUT_MAGIC + "Label", OBJPROP_COLOR, COLOR_TEXTO);
    ObjectSetString(0, INPUT_MAGIC + "Label", OBJPROP_FONT, "Arial");
    ObjectSetInteger(0, INPUT_MAGIC + "Label", OBJPROP_FONTSIZE, 10);
    
    // Botones - centrados horizontalmente y alineados
    int yBotones = PANEL_QUITA_Y + margenSuperior + 65;
    int xInicioBotones = PANEL_QUITA_X + (PANEL_QUITA_WIDTH - (3 * anchoBoton + 2 * espacioEntreBotones)) / 2;  // Centrar los 3 botones
    
    // Botón Buscar
    ObjectCreate(0, BTN_BUSCAR, OBJ_BUTTON, 0, 0, 0);
    ObjectSetInteger(0, BTN_BUSCAR, OBJPROP_XDISTANCE, xInicioBotones);
    ObjectSetInteger(0, BTN_BUSCAR, OBJPROP_YDISTANCE, yBotones);
    ObjectSetInteger(0, BTN_BUSCAR, OBJPROP_XSIZE, anchoBoton);
    ObjectSetInteger(0, BTN_BUSCAR, OBJPROP_YSIZE, 30);
    ObjectSetInteger(0, BTN_BUSCAR, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetString(0, BTN_BUSCAR, OBJPROP_TEXT, "Buscar");
    ObjectSetInteger(0, BTN_BUSCAR, OBJPROP_BGCOLOR, clrBlue);
    ObjectSetInteger(0, BTN_BUSCAR, OBJPROP_COLOR, clrWhite);
    
    // Botón Eliminar Todas
    ObjectCreate(0, BTN_ELIMINAR_TODAS, OBJ_BUTTON, 0, 0, 0);
    ObjectSetInteger(0, BTN_ELIMINAR_TODAS, OBJPROP_XDISTANCE, xInicioBotones + anchoBoton + espacioEntreBotones);
    ObjectSetInteger(0, BTN_ELIMINAR_TODAS, OBJPROP_YDISTANCE, yBotones);
    ObjectSetInteger(0, BTN_ELIMINAR_TODAS, OBJPROP_XSIZE, anchoBoton);
    ObjectSetInteger(0, BTN_ELIMINAR_TODAS, OBJPROP_YSIZE, 30);
    ObjectSetInteger(0, BTN_ELIMINAR_TODAS, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetString(0, BTN_ELIMINAR_TODAS, OBJPROP_TEXT, "Eliminar Todas");
    ObjectSetInteger(0, BTN_ELIMINAR_TODAS, OBJPROP_BGCOLOR, clrRed);
    ObjectSetInteger(0, BTN_ELIMINAR_TODAS, OBJPROP_COLOR, clrWhite);
    
    // Botón Cerrar
    ObjectCreate(0, BTN_CERRAR_PANEL, OBJ_BUTTON, 0, 0, 0);
    ObjectSetInteger(0, BTN_CERRAR_PANEL, OBJPROP_XDISTANCE, xInicioBotones + 2 * (anchoBoton + espacioEntreBotones));
    ObjectSetInteger(0, BTN_CERRAR_PANEL, OBJPROP_YDISTANCE, yBotones);
    ObjectSetInteger(0, BTN_CERRAR_PANEL, OBJPROP_XSIZE, anchoBoton);
    ObjectSetInteger(0, BTN_CERRAR_PANEL, OBJPROP_YSIZE, 30);
    ObjectSetInteger(0, BTN_CERRAR_PANEL, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetString(0, BTN_CERRAR_PANEL, OBJPROP_TEXT, "Cerrar");
    ObjectSetInteger(0, BTN_CERRAR_PANEL, OBJPROP_BGCOLOR, clrGray);
    ObjectSetInteger(0, BTN_CERRAR_PANEL, OBJPROP_COLOR, clrWhite);
    
    // Área de lista (simulada con label) - centrada horizontalmente
    ObjectCreate(0, PANEL_QUITAORDENES + "Lista", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, PANEL_QUITAORDENES + "Lista", OBJPROP_XDISTANCE, PANEL_QUITA_X + margenIzquierdo);
    ObjectSetInteger(0, PANEL_QUITAORDENES + "Lista", OBJPROP_YDISTANCE, PANEL_QUITA_Y + margenSuperior + 110);
    ObjectSetInteger(0, PANEL_QUITAORDENES + "Lista", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetString(0, PANEL_QUITAORDENES + "Lista", OBJPROP_TEXT, "Haga clic en 'Buscar' para listar ordenes");
    ObjectSetInteger(0, PANEL_QUITAORDENES + "Lista", OBJPROP_COLOR, COLOR_TEXTO);
    ObjectSetString(0, PANEL_QUITAORDENES + "Lista", OBJPROP_FONT, "Arial");
    ObjectSetInteger(0, PANEL_QUITAORDENES + "Lista", OBJPROP_FONTSIZE, 9);
}

void OcultarPanelQuitaOrdenes()
{
    panelQuitaVisible = false;
    
    // Eliminar todos los objetos del panel usando el prefijo
    ObjectsDeleteAll(0, PANEL_QUITAORDENES);
    
    // Eliminar explícitamente todos los elementos individuales del panel
    ObjectDelete(0, PANEL_QUITAORDENES + "Fondo");
    ObjectDelete(0, PANEL_QUITAORDENES + "Titulo");
    ObjectDelete(0, PANEL_QUITAORDENES + "TituloFondo");
    ObjectDelete(0, PANEL_QUITAORDENES + "Lista");
    
    // Eliminar campo de entrada
    ObjectDelete(0, INPUT_MAGIC);
    ObjectDelete(0, INPUT_MAGIC + "Label");
    
    // Eliminar todos los botones
    ObjectDelete(0, BTN_BUSCAR);
    ObjectDelete(0, BTN_ELIMINAR_TODAS);
    ObjectDelete(0, BTN_CERRAR_PANEL);
    
    // Eliminar cualquier objeto residual que pueda tener nombres relacionados
    int total = ObjectsTotal(0);
    for(int i = total - 1; i >= 0; i--)
    {
        string name = ObjectName(0, i);
        if(StringFind(name, PANEL_QUITAORDENES) == 0 ||
           StringFind(name, INPUT_MAGIC) == 0 ||
           name == BTN_BUSCAR ||
           name == BTN_ELIMINAR_TODAS ||
           name == BTN_CERRAR_PANEL)
        {
            ObjectDelete(0, name);
        }
    }
    
    // Actualizar el gráfico para reflejar los cambios
    ChartRedraw(0);
}

void BuscarOrdenesPorMagic(uint magicNum)
{
    string lista = "Ordenes encontradas (" + _Symbol + "):\n\n";
    int contador = 0;
    
    // Buscar posiciones - filtrar por magic number Y símbolo (activo)
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(pos_info.SelectByIndex(i) && 
           pos_info.Magic() == magicNum && 
           pos_info.Symbol() == _Symbol)  // Solo del activo actual
        {
            contador++;
            string tipo = pos_info.Type() == POSITION_TYPE_BUY ? "BUY" : "SELL";
            lista += IntegerToString(contador) + ". " + tipo + " Activa - Ticket: " + 
                     IntegerToString(pos_info.Ticket()) + " (" + pos_info.Symbol() + ")\n";
        }
    }
    
    // Buscar órdenes pendientes - filtrar por magic number Y símbolo (activo)
    for(int i = 0; i < OrdersTotal(); i++)
    {
        if(ord_info.SelectByIndex(i) && 
           ord_info.Magic() == magicNum && 
           ord_info.Symbol() == _Symbol)  // Solo del activo actual
        {
            contador++;
            string tipo = "";
            if(ord_info.Type() == ORDER_TYPE_BUY_STOP) tipo = "BUYSTOP";
            else if(ord_info.Type() == ORDER_TYPE_BUY_LIMIT) tipo = "BUYLIMIT";
            else if(ord_info.Type() == ORDER_TYPE_SELL_STOP) tipo = "SELLSTOP";
            else if(ord_info.Type() == ORDER_TYPE_SELL_LIMIT) tipo = "SELLLIMIT";
            
            lista += IntegerToString(contador) + ". " + tipo + " Pendiente - Ticket: " + 
                     IntegerToString(ord_info.Ticket()) + " (" + ord_info.Symbol() + ")\n";
        }
    }
    
    if(contador == 0)
        lista = "No se encontraron ordenes con Magic Number " + IntegerToString(magicNum) + 
                " en " + _Symbol;
    
    ObjectSetString(0, PANEL_QUITAORDENES + "Lista", OBJPROP_TEXT, lista);
}

//+------------------------------------------------------------------+
//| Manejar Eventos del Gráfico                                      |
//+------------------------------------------------------------------+
//| NUEVA FUNCIONALIDAD: Procesa los clics en los botones del panel  |
//| de control y ejecuta las acciones correspondientes.              |
//|                                                                   |
//| Eventos manejados:                                                |
//| - Clic en botones toggle: Cambia estado ON/OFF                   |
//| - Clic en "Aplicar": Elimina órdenes de tipos desactivados       |
//| - Clic en "Quitar Ordenes": Abre/cierra panel de eliminación     |
//| - Clic en "Buscar": Lista órdenes del Magic Number actual        |
//| - Clic en "Eliminar Todas": Elimina todas con confirmación        |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
    if(id == CHARTEVENT_OBJECT_CLICK)
    {
        // Toggle BuyStop
        if(sparam == BOTON_BUYSTOP)
        {
            g_tBuyStop = !g_tBuyStop;
            ObjectSetString(0, BOTON_BUYSTOP, OBJPROP_TEXT, g_tBuyStop ? "ON" : "OFF");
            ObjectSetInteger(0, BOTON_BUYSTOP, OBJPROP_BGCOLOR, g_tBuyStop ? clrGreen : clrRed);
            ChartRedraw();
        }
        // Toggle BuyLimit
        else if(sparam == BOTON_BUYLIMIT)
        {
            g_tBuyLimit = !g_tBuyLimit;
            ObjectSetString(0, BOTON_BUYLIMIT, OBJPROP_TEXT, g_tBuyLimit ? "ON" : "OFF");
            ObjectSetInteger(0, BOTON_BUYLIMIT, OBJPROP_BGCOLOR, g_tBuyLimit ? clrGreen : clrRed);
            ChartRedraw();
        }
        // Toggle SellStop
        else if(sparam == BOTON_SELLSTOP)
        {
            g_tSellStop = !g_tSellStop;
            ObjectSetString(0, BOTON_SELLSTOP, OBJPROP_TEXT, g_tSellStop ? "ON" : "OFF");
            ObjectSetInteger(0, BOTON_SELLSTOP, OBJPROP_BGCOLOR, g_tSellStop ? clrGreen : clrRed);
            ChartRedraw();
        }
        // Toggle SellLimit
        else if(sparam == BOTON_SELLLIMIT)
        {
            g_tSellLimit = !g_tSellLimit;
            ObjectSetString(0, BOTON_SELLLIMIT, OBJPROP_TEXT, g_tSellLimit ? "ON" : "OFF");
            ObjectSetInteger(0, BOTON_SELLLIMIT, OBJPROP_BGCOLOR, g_tSellLimit ? clrGreen : clrRed);
            ChartRedraw();
        }
        // Toggle Reponer Limits
        else if(sparam == "BtnReponerLimits")
        {
            g_reponerLimits = !g_reponerLimits;
            ObjectSetString(0, "BtnReponerLimits", OBJPROP_TEXT, g_reponerLimits ? "Reponer Limits: ON" : "Reponer Limits: OFF");
            ObjectSetInteger(0, "BtnReponerLimits", OBJPROP_BGCOLOR, g_reponerLimits ? C'0,120,0' : C'80,80,80');
            ChartRedraw();
        }
        // Toggle Reponer Stops
        else if(sparam == "BtnReponerStops")
        {
            g_reponerStops = !g_reponerStops;
            ObjectSetString(0, "BtnReponerStops", OBJPROP_TEXT, g_reponerStops ? "Reponer Stops: ON" : "Reponer Stops: OFF");
            ObjectSetInteger(0, "BtnReponerStops", OBJPROP_BGCOLOR, g_reponerStops ? C'0,120,0' : C'80,80,80');
            ChartRedraw();
        }
        // Botón Aplicar
        else if(sparam == BTN_APLICAR)
        {
            // Eliminar órdenes pendientes de tipos desactivados
            if(!g_tBuyStop) QuitarOrdenesPorTipo(ORDER_TYPE_BUY_STOP);
            if(!g_tBuyLimit) QuitarOrdenesPorTipo(ORDER_TYPE_BUY_LIMIT);
            if(!g_tSellStop) QuitarOrdenesPorTipo(ORDER_TYPE_SELL_STOP);
            if(!g_tSellLimit) QuitarOrdenesPorTipo(ORDER_TYPE_SELL_LIMIT);
            
            // Verificar si hay tipos activados sin órdenes pendientes y colocarlas
            bool necesitaColocarOrdenes = false;
            
            // Contar órdenes pendientes por tipo
            int bsP = 0, blP = 0, ssP = 0, slP = 0;
            for(int i = 0; i < OrdersTotal(); i++)
            {
                if(ord_info.SelectByIndex(i) && ord_info.Magic() == MAGICN)
                {
                    if(ord_info.Type() == ORDER_TYPE_BUY_STOP) bsP++;
                    else if(ord_info.Type() == ORDER_TYPE_BUY_LIMIT) blP++;
                    else if(ord_info.Type() == ORDER_TYPE_SELL_STOP) ssP++;
                    else if(ord_info.Type() == ORDER_TYPE_SELL_LIMIT) slP++;
                }
            }
            
            // Si un tipo está activado pero no tiene órdenes pendientes, marcar para colocar
            if(g_tBuyStop && bsP == 0) necesitaColocarOrdenes = true;
            if(g_tBuyLimit && blP == 0) necesitaColocarOrdenes = true;
            if(g_tSellStop && ssP == 0) necesitaColocarOrdenes = true;
            if(g_tSellLimit && slP == 0) necesitaColocarOrdenes = true;
            
            // Colocar órdenes si es necesario
            if(necesitaColocarOrdenes)
            {
                bool stopSuficiente = RevisarStops();
                if(stopSuficiente)
                {
                    ColocarOrdenesIniciales();
                    Print("Órdenes pendientes colocadas después de activar tipos.");
                }
            }
            
            Alert("Cambios aplicados. Los tipos desactivados no generaran nuevas ordenes.");
        }
        // Botón Quitar Ordenes
        else if(sparam == "BtnQuitaOrdenes")
        {
            CrearPanelQuitaOrdenes();
            ChartRedraw();
        }
        // Botón Buscar
        else if(sparam == BTN_BUSCAR)
        {
            BuscarOrdenesPorMagic(MAGICN);
            ChartRedraw();
        }
        // Botón Eliminar Todas
        else if(sparam == BTN_ELIMINAR_TODAS)
        {
            if(MessageBox("¿Esta seguro de eliminar todas las ordenes con Magic Number " + 
                         IntegerToString(MAGICN) + " en " + _Symbol + "?", 
                         "Confirmar", MB_YESNO | MB_ICONQUESTION) == IDYES)
            {
                QuitarOrdenes(MAGICN);
                BuscarOrdenesPorMagic(MAGICN);
            }
        }
        // Botón Cerrar Panel
        else if(sparam == BTN_CERRAR_PANEL)
        {
            OcultarPanelQuitaOrdenes();
            ChartRedraw();
        }
        // Botones para modificar Órdenes por Grupo
        else if(sparam == "BtnOrdenesGrupoMenos")
        {
            if(g_ordenesPorGrupo > 1)
            {
                g_ordenesPorGrupo--;
                ObjectSetString(0, "ValorOrdenesGrupo", OBJPROP_TEXT, IntegerToString(g_ordenesPorGrupo));
                Print("Órdenes por grupo: ", g_ordenesPorGrupo);
                ChartRedraw();
            }
        }
        else if(sparam == "BtnOrdenesGrupoMas")
        {
            if(g_ordenesPorGrupo < 100)
            {
                g_ordenesPorGrupo++;
                ObjectSetString(0, "ValorOrdenesGrupo", OBJPROP_TEXT, IntegerToString(g_ordenesPorGrupo));
                Print("Órdenes por grupo: ", g_ordenesPorGrupo);
                ChartRedraw();
            }
        }
        // Botones para modificar Incremento por Grupo
        else if(sparam == "BtnIncrementoGrupoMenos")
        {
            if(g_incrementoPorGrupo > 1)
            {
                g_incrementoPorGrupo--;
                ObjectSetString(0, "ValorIncrementoGrupo", OBJPROP_TEXT, IntegerToString(g_incrementoPorGrupo));
                Print("Incremento por grupo: ", g_incrementoPorGrupo);
                ChartRedraw();
            }
        }
        else if(sparam == "BtnIncrementoGrupoMas")
        {
            if(g_incrementoPorGrupo < 50)
            {
                g_incrementoPorGrupo++;
                ObjectSetString(0, "ValorIncrementoGrupo", OBJPROP_TEXT, IntegerToString(g_incrementoPorGrupo));
                Print("Incremento por grupo: ", g_incrementoPorGrupo);
                ChartRedraw();
            }
        }
    }
}

// Función auxiliar para eliminar órdenes por tipo
// Filtra por magic number, símbolo (activo) y tipo de orden
void QuitarOrdenesPorTipo(ENUM_ORDER_TYPE tipoOrden)
{
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        if(ord_info.SelectByIndex(i) && 
           ord_info.Magic() == MAGICN && 
           ord_info.Symbol() == _Symbol &&  // Solo del activo actual
           ord_info.Type() == tipoOrden)
        {
            trade.OrderDelete(ord_info.Ticket());
        }
    }
}

//+------------------------------------------------------------------+
//| Comparar Pérdida                                                  |
//+------------------------------------------------------------------+
//| Verifica si el equity actual ha caído por debajo del umbral de   |
//| pérdida máxima permitida.                                        |
//|                                                                   |
//| Funcionamiento:                                                   |
//| - Compara equity actual con (equity inicial - cantidadDePerdida) |
//| - Retorna true si se alcanzó la pérdida máxima                   |
//|                                                                   |
//| Uso: Activar con activarCompararPerdida = true                    |
//|                                                                   |
//| Retorna: true si pérdida máxima alcanzada, false en caso contrario|
//+------------------------------------------------------------------+
bool CompararPerdida()
{
   bool ret = false;
   double equidad = AccountInfoDouble(ACCOUNT_EQUITY);
   double umbralPerdida = initialBalance - cantidadDePerdida;
   
   if(equidad <= umbralPerdida)
   {
      ret = true;
      Print("Pérdida máxima alcanzada. Equity: ", equidad, " Umbral: ", umbralPerdida);
   }
   return ret;
}

//+------------------------------------------------------------------+
//| Verificar Precio Fuera de Rango                                  |
//+------------------------------------------------------------------+
//| Verifica si el precio actual está fuera del rango permitido      |
//| basado en el stop loss y el número de órdenes perdedoras.        |
//|                                                                   |
//| Funcionamiento:                                                   |
//| - Calcula rango máximo = precioBase ± (stopLoss + ordenesPerdedoras * incremento) |
//| - Verifica si Ask está fuera de este rango                       |
//| - Útil para detectar movimientos extremos del mercado            |
//|                                                                   |
//| Uso: Activar con activarFueraDeRango = true                      |
//|                                                                   |
//| Retorna: true si precio fuera de rango, false en caso contrario  |
//+------------------------------------------------------------------+
bool FueraDeRango()
{
   double Ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double Bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double rangoMaximo = precioAskBase + ((stop_loss + (ordenesPerdedoras * increment)) * Point());
   bool ret = false;
   
   // Verificar rango superior
   if(Ask >= rangoMaximo)
   {
      ret = true;
      Print("Precio fuera de rango superior. Ask: ", Ask, " Rango máximo: ", rangoMaximo);
   }
   
   // Verificar rango inferior
   rangoMaximo = precioAskBase - ((stop_loss + (ordenesPerdedoras * increment)) * Point());
   if(Ask <= rangoMaximo)
   {
      ret = true;
      Print("Precio fuera de rango inferior. Ask: ", Ask, " Rango mínimo: ", rangoMaximo);
   }
   
   return ret;
}

//+------------------------------------------------------------------+
//| Inicializar Precios Base                                         |
//+------------------------------------------------------------------+
//| Almacena los precios iniciales (Ask y Bid) para cálculos de      |
//| rango y otras funcionalidades que requieren referencia de precio.|
//|                                                                   |
//| Se llama al inicio y cuando se colocan órdenes iniciales.        |
//+------------------------------------------------------------------+
void InicializarPreciosBase()
{
   precioAskBase = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   precioBidBase = SymbolInfoDouble(_Symbol, SYMBOL_BID);
}

//+------------------------------------------------------------------+
