//+------------------------------------------------------------------+
//|                                                BTCUSD_DMI_ADX_EA |
//|                                   Trend-following EA for BTCUSD |
//|     Uses DMI (+DI/-DI) for direction and ADX threshold for entry |
//+------------------------------------------------------------------+
#property copyright   "OpenAI"
#property version     "1.00"
#property description "EA for BTCUSD using DMI direction and ADX threshold entries"
#property description "Multiple positions per direction, TP/SL in USD, risk cap, visuals"
#property strict

#include <Trade/Trade.mqh>

// Inputs
input int               InpDMIPeriod               = 14;          // DMI period (5-50)
input ENUM_TIMEFRAMES   InpSignalTF                = PERIOD_H1;   // Signal timeframe
input double            InpADXHigh                 = 25.0;        // ADX high threshold (10-50)
input double            InpADXLow                  = 20.0;        // ADX low threshold (5-40)
input double            InpTakeProfitUSD           = 500.0;       // Take-profit amount (USD, 100-2000)
input double            InpStopLossUSD             = 300.0;       // Stop-loss amount (USD, 100-1000)
input double            InpLotSize                 = 0.01;        // Lot size (0.01-1.0)
input bool              InpAllowBuy                = true;        // Allow Buy
input bool              InpAllowSell               = true;        // Allow Sell
input int               InpMaxPositionsPerSide     = 5;           // Max positions per direction (1-10)
input double            InpRiskPercent             = 2.0;         // Max risk per trade (% of equity, 0.5-5.0)
input int               InpDailyTradeLimit         = 3;           // Max trades per day (1-10)

// Visualization (handled via ChartIndicatorAdd)

// Globals
string                  g_symbol;
int                     g_digits = 0;
double                  g_point = 0.0;
double                  g_tick_size = 0.0;
double                  g_tick_value = 0.0;
double                  g_vol_min = 0.0;
double                  g_vol_max = 0.0;
double                  g_vol_step = 0.0;

// Clamped runtime settings derived from inputs (inputs are not modified directly)
int                     g_dmi_period = 14;
ENUM_TIMEFRAMES         g_signal_tf = PERIOD_H1;
double                  g_adx_high = 25.0;
double                  g_adx_low  = 20.0;
double                  g_tp_usd   = 500.0;
double                  g_sl_usd   = 300.0;
double                  g_lot_size_inp = 0.01;
int                     g_max_positions_per_side = 5;
double                  g_risk_percent = 2.0;
int                     g_daily_limit = 3;

// Trade object and control
CTrade                  g_trade;
int                     g_magic = 251092345; // arbitrary magic number

// Indicator handle and data
int                     g_adx_handle = INVALID_HANDLE; // iADX handle
datetime                g_last_tf_bar_time = 0;        // last processed bar time for selected TF

// Direction control: -1 = bearish (sell-only), 1 = bullish (buy-only), 0 = neutral
int                     g_current_direction = 0;

// Daily trade control
int                     g_daily_trade_count = 0;
string                  g_daily_key = ""; // YYYY.MM.DD

// UI object names
string                  g_lbl_settings = "EA_Settings_Label";
string                  g_lbl_pnl      = "EA_PnL_Label";

// Utility forward declarations
void    ClampInputs();
bool    InitSymbolProps();
bool    InitIndicators();
bool    IsNewSignalBar();
void    ProcessSignalsOnBarClose();
bool    CopyAdxData(double &adx[], double &plusDI[], double &minusDI[]);
void    UpdateDirectionOnDICross(const double plusDI1, const double plusDI2, const double minusDI1, const double minusDI2);
bool    IsAdxCrossUp(const double adx1, const double adx2, const double threshold);
bool    IsAdxCrossDown(const double adx1, const double adx2, const double threshold);
int     CountPositionsByDirection(const int dir);
int     CountPositionsTotal();
bool    HasOppositePositions(const int dir);
double  AlignLotToBroker(const double requestedLot);
double  USDToPoints(const double usd, const double lot);
bool    OpenDirectionalTrade(const int dir, const string reason, const double tpUSD, const double slUSD);
int     ClosePositionsByDirection(const int dir, const string reason);
void    DrawEntryArrow(const int dir, const double price, const string reason);
void    DrawExitArrow(const int dir, const double price, const string reason);
void    DrawExitLabel(const double price, const string text);
void    UpdatePanels();
void    ResetDailyCounterIfNeeded();
string  TFToString(ENUM_TIMEFRAMES tf);

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    g_symbol = Symbol();

    ClampInputs();

    if(!InitSymbolProps())
        return(INIT_FAILED);

    g_trade.SetExpertMagicNumber(g_magic);
    g_trade.SetDeviationInPoints(100); // allow wider deviation for BTC volatility

    if(!InitIndicators())
        return(INIT_FAILED);

    // Initialize last TF bar time for new-bar processing
    g_last_tf_bar_time = iTime(g_symbol, g_signal_tf, 0);

    // Initialize daily key
    g_daily_key = TimeToString(TimeCurrent(), TIME_DATE);
    g_daily_trade_count = 0;

    // Create UI panels
    ObjectCreate(0, g_lbl_settings, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, g_lbl_settings, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
    ObjectSetInteger(0, g_lbl_settings, OBJPROP_XDISTANCE, 10);
    ObjectSetInteger(0, g_lbl_settings, OBJPROP_YDISTANCE, 10);
    ObjectSetInteger(0, g_lbl_settings, OBJPROP_FONTSIZE, 9);

    ObjectCreate(0, g_lbl_pnl, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, g_lbl_pnl, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
    ObjectSetInteger(0, g_lbl_pnl, OBJPROP_XDISTANCE, 10);
    ObjectSetInteger(0, g_lbl_pnl, OBJPROP_YDISTANCE, 120);
    ObjectSetInteger(0, g_lbl_pnl, OBJPROP_FONTSIZE, 10);
    ObjectSetInteger(0, g_lbl_pnl, OBJPROP_COLOR, clrLime);

    UpdatePanels();

    Print("BTCUSD_DMI_ADX_EA initialized on ", g_symbol, " TF=", TFToString(g_signal_tf));
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(g_adx_handle != INVALID_HANDLE)
    {
        IndicatorRelease(g_adx_handle);
        g_adx_handle = INVALID_HANDLE;
    }

    // Remove UI objects created by the EA
    ObjectDelete(0, g_lbl_settings);
    ObjectDelete(0, g_lbl_pnl);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    ResetDailyCounterIfNeeded();

    if(IsNewSignalBar())
    {
        ProcessSignalsOnBarClose();
    }

    UpdatePanels();
}

//+------------------------------------------------------------------+
//| Trade transaction handler for marking TP/SL exits                |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
    if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
    {
        ulong deal_ticket = trans.deal;
        HistorySelect(TimeCurrent() - 86400*10, TimeCurrent() + 60);
        long magic = (long)HistoryDealGetInteger(deal_ticket, DEAL_MAGIC);
        string sym = HistoryDealGetString(deal_ticket, DEAL_SYMBOL);
        if(magic == g_magic && sym == g_symbol)
        {
            int deal_entry = (int)HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);
            int deal_reason = (int)HistoryDealGetInteger(deal_ticket, DEAL_REASON);
            if(deal_entry == DEAL_ENTRY_OUT)
            {
                double price = HistoryDealGetDouble(deal_ticket, DEAL_PRICE);
                string label = "Exit";
                if(deal_reason == DEAL_REASON_SL) label = "SL hit";
                else if(deal_reason == DEAL_REASON_TP) label = "TP hit";
                DrawExitLabel(price, label);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Clamp input parameters to required ranges                        |
//+------------------------------------------------------------------+
void ClampInputs()
{
    // Clamp to ranges and copy to runtime globals
    g_dmi_period = (int)MathMax(5, MathMin(50, InpDMIPeriod));
    g_signal_tf = InpSignalTF;
    g_adx_high = MathMax(10.0, MathMin(50.0, InpADXHigh));
    g_adx_low  = MathMax(5.0,  MathMin(40.0, InpADXLow));
    if(g_adx_low > g_adx_high)
    {
        double tmp = g_adx_low;
        g_adx_low = g_adx_high;
        g_adx_high = tmp;
    }
    g_tp_usd   = MathMax(100.0, MathMin(2000.0, InpTakeProfitUSD));
    g_sl_usd   = MathMax(100.0, MathMin(1000.0, InpStopLossUSD));
    g_lot_size_inp = MathMax(0.01,  MathMin(1.0, InpLotSize));
    g_max_positions_per_side = (int)MathMax(1, MathMin(10, InpMaxPositionsPerSide));
    g_risk_percent = MathMax(0.5, MathMin(5.0, InpRiskPercent));
    g_daily_limit = (int)MathMax(1, MathMin(10, InpDailyTradeLimit));
}

//+------------------------------------------------------------------+
//| Initialize symbol properties                                     |
//+------------------------------------------------------------------+
bool InitSymbolProps()
{
    g_digits = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);
    g_point  = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
    g_tick_size  = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_SIZE);
    g_tick_value = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_VALUE);
    g_vol_min  = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN);
    g_vol_max  = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MAX);
    g_vol_step = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_STEP);

    if(g_point <= 0.0 || g_tick_size <= 0.0 || g_tick_value <= 0.0)
    {
        Print("[ERROR] Invalid symbol props: point=", g_point, " tick_size=", g_tick_size, " tick_value=", g_tick_value);
        return(false);
    }

    return(true);
}

//+------------------------------------------------------------------+
//| Initialize indicators                                            |
//+------------------------------------------------------------------+
bool InitIndicators()
{
    if(g_adx_handle != INVALID_HANDLE)
    {
        IndicatorRelease(g_adx_handle);
        g_adx_handle = INVALID_HANDLE;
    }

    g_adx_handle = iADX(g_symbol, g_signal_tf, g_dmi_period);
    if(g_adx_handle == INVALID_HANDLE)
    {
        Print("[ERROR] Failed to create iADX handle. Error=", GetLastError());
        return(false);
    }

    // Add indicator to chart subwindow for visualization
    if(!ChartIndicatorAdd(0, 1, g_adx_handle))
    {
        Print("[WARN] Failed to add ADX indicator to chart. Error=", GetLastError());
    }

    return(true);
}

//+------------------------------------------------------------------+
//| Detects if new bar formed for selected timeframe                 |
//+------------------------------------------------------------------+
bool IsNewSignalBar()
{
    datetime t0 = iTime(g_symbol, g_signal_tf, 0);
    if(t0 == 0)
        return(false);

    if(g_last_tf_bar_time == 0)
    {
        g_last_tf_bar_time = t0;
        return(false);
    }

    if(t0 != g_last_tf_bar_time)
    {
        g_last_tf_bar_time = t0;
        return(true);
    }
    return(false);
}

//+------------------------------------------------------------------+
//| Process trading logic on bar close                               |
//+------------------------------------------------------------------+
void ProcessSignalsOnBarClose()
{
    if(g_adx_handle == INVALID_HANDLE)
        return;

    double adx[];
    double plusDI[];
    double minusDI[];
    ArraySetAsSeries(adx, true);
    ArraySetAsSeries(plusDI, true);
    ArraySetAsSeries(minusDI, true);

    if(!CopyAdxData(adx, plusDI, minusDI))
        return;

    // Use indices: 1 = last closed bar, 2 = previous closed bar
    double adx1 = adx[1], adx2 = adx[2];
    double pdi1 = plusDI[1], pdi2 = plusDI[2];
    double mdi1 = minusDI[1], mdi2 = minusDI[2];

    // 1) Direction update on DI cross
    int prev_direction = g_current_direction;
    UpdateDirectionOnDICross(pdi1, pdi2, mdi1, mdi2);
    if(g_current_direction != prev_direction && prev_direction != 0)
    {
        // Reverse signal: close all positions that were in previous direction
        string reason = (g_current_direction == 1 ? "DI Bullish Cross" : "DI Bearish Cross");
        ClosePositionsByDirection(prev_direction, reason);
    }

    // 2) Exit on ADX weakening (cross below low threshold)
    if(IsAdxCrossDown(adx1, adx2, g_adx_low) && g_current_direction != 0)
    {
        ClosePositionsByDirection(g_current_direction, "ADX fell below low");
    }

    // 3) Entry on ADX cross above high threshold in current direction
    if(IsAdxCrossUp(adx1, adx2, g_adx_high))
    {
        if(g_current_direction == 1 && InpAllowBuy && pdi1 > mdi1)
        {
            OpenDirectionalTrade(1, "ADX cross up", g_tp_usd, g_sl_usd);
        }
        else if(g_current_direction == -1 && InpAllowSell && mdi1 > pdi1)
        {
            OpenDirectionalTrade(-1, "ADX cross up", g_tp_usd, g_sl_usd);
        }
    }
}

//+------------------------------------------------------------------+
//| Copy indicator buffers for ADX and DIs                           |
//+------------------------------------------------------------------+
bool CopyAdxData(double &adx[], double &plusDI[], double &minusDI[])
{
    if(CopyBuffer(g_adx_handle, 0, 0, 3, adx) < 3)
    {
        Print("[WARN] Not enough ADX data");
        return(false);
    }
    if(CopyBuffer(g_adx_handle, 1, 0, 3, plusDI) < 3)
    {
        Print("[WARN] Not enough +DI data");
        return(false);
    }
    if(CopyBuffer(g_adx_handle, 2, 0, 3, minusDI) < 3)
    {
        Print("[WARN] Not enough -DI data");
        return(false);
    }
    return(true);
}

//+------------------------------------------------------------------+
//| Update direction on DI cross                                     |
//+------------------------------------------------------------------+
void UpdateDirectionOnDICross(const double plusDI1, const double plusDI2, const double minusDI1, const double minusDI2)
{
    bool bull_cross = (plusDI2 <= minusDI2 && plusDI1 > minusDI1);
    bool bear_cross = (minusDI2 <= plusDI2 && minusDI1 > plusDI1);

    if(bull_cross)
        g_current_direction = 1;
    else if(bear_cross)
        g_current_direction = -1;
}

//+------------------------------------------------------------------+
//| ADX cross helpers                                                |
//+------------------------------------------------------------------+
bool IsAdxCrossUp(const double adx1, const double adx2, const double threshold)
{
    return(adx2 <= threshold && adx1 > threshold);
}

bool IsAdxCrossDown(const double adx1, const double adx2, const double threshold)
{
    return(adx2 >= threshold && adx1 < threshold);
}

//+------------------------------------------------------------------+
//| Count positions helpers                                          |
//+------------------------------------------------------------------+
int CountPositionsTotal()
{
    int total = 0;
    for(int i=0; i<PositionsTotal(); ++i)
    {
        if(!PositionSelectByIndex(i))
            continue;
        if(PositionGetString(POSITION_SYMBOL) != g_symbol)
            continue;
        long magic = (long)PositionGetInteger(POSITION_MAGIC);
        if(magic != g_magic)
            continue;
        total++;
    }
    return(total);
}

int CountPositionsByDirection(const int dir)
{
    int count = 0;
    for(int i=0; i<PositionsTotal(); ++i)
    {
        if(!PositionSelectByIndex(i))
            continue;
        if(PositionGetString(POSITION_SYMBOL) != g_symbol)
            continue;
        long magic = (long)PositionGetInteger(POSITION_MAGIC);
        if(magic != g_magic)
            continue;
        long type = (long)PositionGetInteger(POSITION_TYPE);
        if(dir == 1 && type == POSITION_TYPE_BUY)
            count++;
        if(dir == -1 && type == POSITION_TYPE_SELL)
            count++;
    }
    return(count);
}

bool HasOppositePositions(const int dir)
{
    int count = CountPositionsByDirection(-dir);
    return(count > 0);
}

//+------------------------------------------------------------------+
//| Risk and conversion helpers                                      |
//+------------------------------------------------------------------+
double AdjustLotByRisk(double requestedLot, const double stopLossUSD)
{
    double lot = requestedLot;
    if(g_vol_step > 0.0)
        lot = MathFloor(lot / g_vol_step) * g_vol_step;
    lot = MathMax(g_vol_min, MathMin(g_vol_max, lot));
    if(lot < g_vol_min - 1e-12)
        return(0.0);
    return(lot);
}

// Convert USD amount to price distance in points for the given lot
double USDToPoints(const double usd, const double lot)
{
    if(usd <= 0.0 || lot <= 0.0 || g_tick_value <= 0.0 || g_tick_size <= 0.0 || g_point <= 0.0)
        return(0.0);

    // price_delta = USD / (tick_value_per_lot * lot) * tick_size
    double price_delta = (usd / (g_tick_value * lot)) * g_tick_size;
    double points = price_delta / g_point;
    return(points);
}

//+------------------------------------------------------------------+
//| Open trade in the current direction                              |
//+------------------------------------------------------------------+
bool OpenDirectionalTrade(const int dir, const string reason, const double tpUSD, const double slUSD)
{
    if(dir != 1 && dir != -1)
        return(false);

    if(HasOppositePositions(dir))
    {
        Print("[INFO] Opposite positions exist; no new trades opened.");
        return(false);
    }

    if(CountPositionsByDirection(dir) >= g_max_positions_per_side)
    {
        Print("[INFO] Reached max positions per side: ", g_max_positions_per_side);
        return(false);
    }

    if(g_daily_trade_count >= g_daily_limit)
    {
        Print("[INFO] Daily trade limit reached: ", g_daily_limit);
        return(false);
    }

    if(!TerminalInfoInteger(TERMINAL_CONNECTED))
    {
        Print("[WARN] Terminal not connected. Abort trading.");
        return(false);
    }

    // Risk cap in USD
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double maxRiskUSD = equity * g_risk_percent / 100.0;
    double allowedRiskUSD = MathMin(slUSD, maxRiskUSD);
    if(allowedRiskUSD <= 0.0)
    {
        Print("[WARN] Allowed risk USD is non-positive.");
        return(false);
    }

    // Compute lot respecting broker volume constraints
    double lot = AdjustLotByRisk(g_lot_size_inp, allowedRiskUSD);
    if(lot <= 0.0)
    {
        Print("[WARN] Computed lot too small or zero after risk adjustment.");
        return(false);
    }

    // Compute SL/TP distances
    double sl_points = USDToPoints(allowedRiskUSD, lot);
    double tp_points = USDToPoints(tpUSD, lot);
    if(sl_points <= 0.0 || tp_points <= 0.0)
    {
        Print("[ERROR] Invalid SL/TP points conversion. sl_points=", sl_points, " tp_points=", tp_points);
        return(false);
    }

    // Respect broker stops/freeze levels
    int stops_level_points = (int)SymbolInfoInteger(g_symbol, SYMBOL_TRADE_STOPS_LEVEL);
    int freeze_level_points = (int)SymbolInfoInteger(g_symbol, SYMBOL_TRADE_FREEZE_LEVEL);
    int min_distance_points = MathMax(stops_level_points, freeze_level_points);
    if(min_distance_points > 0)
    {
        if(sl_points < (double)min_distance_points)
            sl_points = (double)min_distance_points;
        if(tp_points < (double)min_distance_points)
            tp_points = (double)min_distance_points;
    }

    double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
    double sl_price = 0.0, tp_price = 0.0;

    if(dir == 1) // Buy
    {
        sl_price = NormalizeDouble(ask - sl_points * g_point, g_digits);
        tp_price = NormalizeDouble(ask + tp_points * g_point, g_digits);
    }
    else // Sell
    {
        sl_price = NormalizeDouble(bid + sl_points * g_point, g_digits);
        tp_price = NormalizeDouble(bid - tp_points * g_point, g_digits);
    }

    bool res = false;
    string cmt = StringFormat("DMI_ADX_%s | %.2flots | %s", (dir==1?"BUY":"SELL"), lot, reason);
    if(dir == 1)
        res = g_trade.Buy(lot, g_symbol, 0.0, sl_price, tp_price, cmt);
    else
        res = g_trade.Sell(lot, g_symbol, 0.0, sl_price, tp_price, cmt);

    if(!res)
    {
        Print("[ERROR] Trade open failed. RetCode=", g_trade.ResultRetcode(), " Err=", GetLastError());
        return(false);
    }

    g_daily_trade_count++;

    double price_marker = (dir==1 ? ask : bid);
    DrawEntryArrow(dir, price_marker, reason);
    Print("[TRADE] Opened ", (dir==1?"BUY":"SELL"), " lot=", DoubleToString(lot, 2), " SL(", slUSD, "USD) TP(", tpUSD, "USD) Reason:", reason);
    return(true);
}

//+------------------------------------------------------------------+
//| Close all positions in given direction                           |
//+------------------------------------------------------------------+
int ClosePositionsByDirection(const int dir, const string reason)
{
    int closed = 0;
    double price_marker = 0.0;
    double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
    price_marker = (dir==1 ? bid : ask);

    for(int i=PositionsTotal()-1; i>=0; --i)
    {
        if(!PositionSelectByIndex(i))
            continue;
        if(PositionGetString(POSITION_SYMBOL) != g_symbol)
            continue;
        long magic = (long)PositionGetInteger(POSITION_MAGIC);
        if(magic != g_magic)
            continue;
        long type = (long)PositionGetInteger(POSITION_TYPE);
        if((dir==1 && type==POSITION_TYPE_BUY) || (dir==-1 && type==POSITION_TYPE_SELL))
        {
            ulong ticket = (ulong)PositionGetInteger(POSITION_TICKET);
            if(g_trade.PositionClose(ticket))
            {
                closed++;
                DrawExitArrow(dir, price_marker, reason);
            }
            else
            {
                Print("[ERROR] Failed to close position ", ticket, " RetCode=", g_trade.ResultRetcode(), " Err=", GetLastError());
            }
        }
    }

    if(closed > 0)
        Print("[TRADE] Closed ", closed, " positions due to ", reason);
    return(closed);
}

//+------------------------------------------------------------------+
//| Drawing helpers                                                  |
//+------------------------------------------------------------------+
void DrawEntryArrow(const int dir, const double price, const string reason)
{
    string name = "DMIADX_ENTRY_" + string(dir==1?"BUY":"SELL") + "_" + IntegerToString((int)GetTickCount());
    ENUM_OBJECT arrowType = (dir==1 ? OBJ_ARROW_BUY : OBJ_ARROW_SELL);
    if(ObjectCreate(0, name, arrowType, 0, TimeCurrent(), price))
    {
        ObjectSetInteger(0, name, OBJPROP_COLOR, (dir==1?clrLime:clrRed));
        ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
        ObjectSetString(0, name, OBJPROP_TEXT, StringFormat("%s %s", (dir==1?"BUY":"SELL"), reason));
    }
}

void DrawExitArrow(const int dir, const double price, const string reason)
{
    string name = "DMIADX_EXIT_" + string(dir==1?"BUY":"SELL") + "_" + IntegerToString((int)GetTickCount());
    ENUM_OBJECT arrowType = (dir==1 ? OBJ_ARROW_SELL : OBJ_ARROW_BUY);
    if(ObjectCreate(0, name, arrowType, 0, TimeCurrent(), price))
    {
        ObjectSetInteger(0, name, OBJPROP_COLOR, clrYellow);
        ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
        ObjectSetString(0, name, OBJPROP_TEXT, StringFormat("EXIT %s", reason));
    }
}

void DrawExitLabel(const double price, const string text)
{
    string name = "DMIADX_EXITLBL_" + IntegerToString((int)GetTickCount());
    if(ObjectCreate(0, name, OBJ_TEXT, 0, TimeCurrent(), price))
    {
        ObjectSetInteger(0, name, OBJPROP_COLOR, clrYellow);
        ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
        ObjectSetString(0, name, OBJPROP_TEXT, text);
    }
}

//+------------------------------------------------------------------+
//| Panels update                                                    |
//+------------------------------------------------------------------+
void UpdatePanels()
{
    // Settings panel
    string s = "";
    s += "EA: BTCUSD DMI/ADX\n";
    s += StringFormat("TF: %s  DMI: %d\n", TFToString(g_signal_tf), g_dmi_period);
    s += StringFormat("ADX High: %.1f  Low: %.1f\n", g_adx_high, g_adx_low);
    s += StringFormat("TP: $%.0f  SL: $%.0f\n", g_tp_usd, g_sl_usd);
    s += StringFormat("Lot: %.2f  Risk: %.1f%%\n", g_lot_size_inp, g_risk_percent);
    s += StringFormat("Allow Buy: %s  Allow Sell: %s\n", (InpAllowBuy?"Yes":"No"), (InpAllowSell?"Yes":"No"));
    s += StringFormat("Max Pos/Side: %d  Daily Limit: %d\n", g_max_positions_per_side, g_daily_limit);
    s += StringFormat("Direction: %s\n", (g_current_direction==1?"Bullish":(g_current_direction==-1?"Bearish":"Neutral")));
    s += StringFormat("Today Trades: %d/%d", g_daily_trade_count, g_daily_limit);
    ObjectSetString(0, g_lbl_settings, OBJPROP_TEXT, s);

    // PnL panel
    double totalUSD = 0.0;
    double totalPoints = 0.0;
    for(int i=0; i<PositionsTotal(); ++i)
    {
        if(!PositionSelectByIndex(i))
            continue;
        if(PositionGetString(POSITION_SYMBOL) != g_symbol)
            continue;
        totalUSD += PositionGetDouble(POSITION_PROFIT);
        double op = PositionGetDouble(POSITION_PRICE_OPEN);
        long type = (long)PositionGetInteger(POSITION_TYPE);
        double cur_price = (type==POSITION_TYPE_BUY ? SymbolInfoDouble(g_symbol, SYMBOL_BID) : SymbolInfoDouble(g_symbol, SYMBOL_ASK));
        double pts = (type==POSITION_TYPE_BUY ? (cur_price - op) : (op - cur_price)) / g_point;
        totalPoints += pts;
    }
    string pnlText = StringFormat("Open PnL: $%.2f  (%.0f pts)", totalUSD, totalPoints);
    ObjectSetString(0, g_lbl_pnl, OBJPROP_TEXT, pnlText);
}

//+------------------------------------------------------------------+
//| Reset daily counter at new day                                   |
//+------------------------------------------------------------------+
void ResetDailyCounterIfNeeded()
{
    string key = TimeToString(TimeCurrent(), TIME_DATE);
    if(key != g_daily_key)
    {
        g_daily_key = key;
        g_daily_trade_count = 0;
        Print("[INFO] New trading day. Daily counter reset.");
    }
}

//+------------------------------------------------------------------+
//| Timeframe to string helper                                        |
//+------------------------------------------------------------------+
string TFToString(ENUM_TIMEFRAMES tf)
{
    switch(tf)
    {
        case PERIOD_M15: return "M15";
        case PERIOD_M30: return "M30";
        case PERIOD_H1:  return "H1";
        case PERIOD_H4:  return "H4";
        case PERIOD_D1:  return "D1";
        default: return IntegerToString((int)tf);
    }
}

