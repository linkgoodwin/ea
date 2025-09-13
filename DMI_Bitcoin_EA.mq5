//+------------------------------------------------------------------+
//|                                                DMI_Bitcoin_EA.mq5 |
//|                                  Copyright 2025, Trading Systems |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Trading Systems"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property description "Bitcoin DMI Trading EA with ADX-based lot sizing"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>

//--- Input parameters
input group "=== DMI Settings ==="
input int                DMI_Period = 14;                    // DMI Period (5-50)
input ENUM_TIMEFRAMES    Trading_Timeframe = PERIOD_M15;     // Trading Timeframe
input double             Lot_Multiplier = 1.0;              // Lot Size Multiplier (0.1-10.0)

input group "=== Risk Management ==="
input double             Risk_Percent = 2.0;                // Risk per trade (0.5-5.0%)
input int                StopLoss_Intervals = 2;            // Stop-loss interval count (1-5)
input int                Daily_StopLoss_Limit = 3;          // Daily stop-loss limit (1-10)
input int                Trading_Pause_Hours = 12;          // Trading pause duration (1-24 hours)

input group "=== Trading Direction ==="
input bool               Allow_Buy = true;                  // Allow Buy trades
input bool               Allow_Sell = true;                 // Allow Sell trades

input group "=== Display Settings ==="
input bool               Show_Info_Panel = true;            // Show information panel
input bool               Show_Chart_Labels = true;          // Show entry/exit labels
input color              Panel_Color = clrDarkBlue;         // Panel background color
input color              Text_Color = clrWhite;             // Panel text color

//--- Global variables
CTrade trade;
CPositionInfo position;
CAccountInfo account;

// DMI handles and buffers
int dmi_handle;
double plus_di_buffer[];
double minus_di_buffer[];
double adx_buffer[];

// Trading variables
struct TradeInfo {
    double entry_adx;
    int entry_interval;
    double entry_lot_size;
    datetime entry_time;
    int position_type; // 0=none, 1=buy, -1=sell
    double total_profit;
    int daily_trades;
    int daily_stoplosses;
    datetime last_trade_date;
    datetime pause_until;
    bool is_paused;
};

TradeInfo trade_info;

// ADX intervals (0-10, 10-20, ..., 90-100)
double adx_intervals[10][2] = {
    {0, 10}, {10, 20}, {20, 30}, {30, 40}, {40, 50},
    {50, 60}, {60, 70}, {70, 80}, {80, 90}, {90, 100}
};

// Lot sizes for each interval (highest ADX = smallest lot)
double base_lot_sizes[10] = {0.10, 0.09, 0.08, 0.07, 0.06, 0.05, 0.04, 0.03, 0.02, 0.01};

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Validate input parameters
    if(!ValidateInputs()) {
        return INIT_PARAMETERS_INCORRECT;
    }
    
    // Initialize DMI indicator
    dmi_handle = iADX(Symbol(), Trading_Timeframe, DMI_Period);
    if(dmi_handle == INVALID_HANDLE) {
        Print("Failed to create DMI indicator handle");
        return INIT_FAILED;
    }
    
    // Set array as series
    ArraySetAsSeries(plus_di_buffer, true);
    ArraySetAsSeries(minus_di_buffer, true);
    ArraySetAsSeries(adx_buffer, true);
    
    // Initialize trade info
    InitializeTradeInfo();
    
    // Create info panel
    if(Show_Info_Panel) {
        CreateInfoPanel();
    }
    
    Print("DMI Bitcoin EA initialized successfully");
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Release indicator handle
    if(dmi_handle != INVALID_HANDLE) {
        IndicatorRelease(dmi_handle);
    }
    
    // Remove chart objects
    ObjectsDeleteAll(0, "DMI_EA_");
    
    Print("DMI Bitcoin EA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Check if trading is paused
    if(trade_info.is_paused && TimeCurrent() < trade_info.pause_until) {
        UpdateInfoPanel();
        return;
    }
    
    // Reset pause if time has passed
    if(trade_info.is_paused && TimeCurrent() >= trade_info.pause_until) {
        trade_info.is_paused = false;
        Print("Trading pause ended, resuming operations");
    }
    
    // Reset daily counters at start of new day
    ResetDailyCounters();
    
    // Update DMI values
    if(!UpdateDMIValues()) {
        return;
    }
    
    // Check for trading signals
    CheckTradingSignals();
    
    // Manage existing positions
    ManagePositions();
    
    // Update display
    if(Show_Info_Panel) {
        UpdateInfoPanel();
    }
}

//+------------------------------------------------------------------+
//| Validate input parameters                                        |
//+------------------------------------------------------------------+
bool ValidateInputs()
{
    if(DMI_Period < 5 || DMI_Period > 50) {
        Print("Invalid DMI Period: ", DMI_Period, ". Must be between 5 and 50.");
        return false;
    }
    
    if(Lot_Multiplier < 0.1 || Lot_Multiplier > 10.0) {
        Print("Invalid Lot Multiplier: ", Lot_Multiplier, ". Must be between 0.1 and 10.0.");
        return false;
    }
    
    if(Risk_Percent < 0.5 || Risk_Percent > 5.0) {
        Print("Invalid Risk Percent: ", Risk_Percent, ". Must be between 0.5 and 5.0.");
        return false;
    }
    
    if(StopLoss_Intervals < 1 || StopLoss_Intervals > 5) {
        Print("Invalid Stop-loss Intervals: ", StopLoss_Intervals, ". Must be between 1 and 5.");
        return false;
    }
    
    if(Daily_StopLoss_Limit < 1 || Daily_StopLoss_Limit > 10) {
        Print("Invalid Daily Stop-loss Limit: ", Daily_StopLoss_Limit, ". Must be between 1 and 10.");
        return false;
    }
    
    if(Trading_Pause_Hours < 1 || Trading_Pause_Hours > 24) {
        Print("Invalid Trading Pause Hours: ", Trading_Pause_Hours, ". Must be between 1 and 24.");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Initialize trade information structure                           |
//+------------------------------------------------------------------+
void InitializeTradeInfo()
{
    trade_info.entry_adx = 0;
    trade_info.entry_interval = -1;
    trade_info.entry_lot_size = 0;
    trade_info.entry_time = 0;
    trade_info.position_type = 0;
    trade_info.total_profit = 0;
    trade_info.daily_trades = 0;
    trade_info.daily_stoplosses = 0;
    trade_info.last_trade_date = 0;
    trade_info.pause_until = 0;
    trade_info.is_paused = false;
}

//+------------------------------------------------------------------+
//| Update DMI indicator values                                      |
//+------------------------------------------------------------------+
bool UpdateDMIValues()
{
    // Copy indicator values
    if(CopyBuffer(dmi_handle, 0, 0, 3, plus_di_buffer) <= 0 ||
       CopyBuffer(dmi_handle, 1, 0, 3, minus_di_buffer) <= 0 ||
       CopyBuffer(dmi_handle, 2, 0, 3, adx_buffer) <= 0) {
        Print("Failed to copy DMI indicator values");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Get ADX interval for given ADX value                            |
//+------------------------------------------------------------------+
int GetADXInterval(double adx_value)
{
    for(int i = 0; i < 10; i++) {
        if(adx_value >= adx_intervals[i][0] && adx_value < adx_intervals[i][1]) {
            return i;
        }
    }
    
    // Handle edge case for ADX = 100
    if(adx_value >= 100) return 9;
    
    return 0; // Default to lowest interval
}

//+------------------------------------------------------------------+
//| Calculate lot size based on ADX interval                        |
//+------------------------------------------------------------------+
double CalculateLotSize(int adx_interval)
{
    double lot_size = base_lot_sizes[adx_interval] * Lot_Multiplier;
    
    // Normalize lot size according to symbol specifications
    double min_lot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    double max_lot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
    double lot_step = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
    
    lot_size = MathMax(lot_size, min_lot);
    lot_size = MathMin(lot_size, max_lot);
    lot_size = NormalizeDouble(lot_size / lot_step, 0) * lot_step;
    
    return lot_size;
}

//+------------------------------------------------------------------+
//| Check for trading signals                                        |
//+------------------------------------------------------------------+
void CheckTradingSignals()
{
    // Check for DI crossovers
    bool plus_di_cross_above = (plus_di_buffer[1] > minus_di_buffer[1]) && 
                               (plus_di_buffer[2] <= minus_di_buffer[2]);
    bool minus_di_cross_above = (minus_di_buffer[1] > plus_di_buffer[1]) && 
                                (minus_di_buffer[2] <= plus_di_buffer[2]);
    
    // Buy signal: +DI crosses above -DI
    if(plus_di_cross_above && Allow_Buy) {
        // Close any existing short position first
        if(trade_info.position_type == -1) {
            ClosePosition("平空");
        }
        
        // Open long position
        int adx_interval = GetADXInterval(adx_buffer[1]);
        double lot_size = CalculateLotSize(adx_interval);
        
        if(OpenPosition(ORDER_TYPE_BUY, lot_size, adx_interval)) {
            if(Show_Chart_Labels) {
                CreateTradeLabel("开多", clrLime);
            }
        }
    }
    
    // Sell signal: -DI crosses above +DI
    if(minus_di_cross_above && Allow_Sell) {
        // Close any existing long position first
        if(trade_info.position_type == 1) {
            ClosePosition("平多");
        }
        
        // Open short position
        int adx_interval = GetADXInterval(adx_buffer[1]);
        double lot_size = CalculateLotSize(adx_interval);
        
        if(OpenPosition(ORDER_TYPE_SELL, lot_size, adx_interval)) {
            if(Show_Chart_Labels) {
                CreateTradeLabel("开空", clrRed);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Open position                                                    |
//+------------------------------------------------------------------+
bool OpenPosition(ENUM_ORDER_TYPE order_type, double lot_size, int adx_interval)
{
    // Check daily limits
    if(trade_info.daily_stoplosses >= Daily_StopLoss_Limit) {
        Print("Daily stop-loss limit reached. Trading paused.");
        trade_info.is_paused = true;
        trade_info.pause_until = TimeCurrent() + Trading_Pause_Hours * 3600;
        return false;
    }
    
    // Calculate risk-based position size
    double risk_lot_size = CalculateRiskBasedLotSize();
    lot_size = MathMin(lot_size, risk_lot_size);
    
    bool success = false;
    if(order_type == ORDER_TYPE_BUY) {
        success = trade.Buy(lot_size, Symbol());
    } else {
        success = trade.Sell(lot_size, Symbol());
    }
    
    if(success) {
        // Update trade info
        trade_info.entry_adx = adx_buffer[1];
        trade_info.entry_interval = adx_interval;
        trade_info.entry_lot_size = lot_size;
        trade_info.entry_time = TimeCurrent();
        trade_info.position_type = (order_type == ORDER_TYPE_BUY) ? 1 : -1;
        trade_info.daily_trades++;
        
        Print("Position opened: ", (order_type == ORDER_TYPE_BUY) ? "BUY" : "SELL", 
              " Lot: ", lot_size, " ADX: ", adx_buffer[1], " Interval: ", adx_interval);
        
        return true;
    } else {
        Print("Failed to open position: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
        return false;
    }
}

//+------------------------------------------------------------------+
//| Close position                                                   |
//+------------------------------------------------------------------+
void ClosePosition(string label)
{
    if(PositionSelect(Symbol())) {
        double profit = PositionGetDouble(POSITION_PROFIT);
        
        if(trade.PositionClose(Symbol())) {
            trade_info.total_profit += profit;
            
            // Check if this was a stop-loss
            if(profit < 0) {
                trade_info.daily_stoplosses++;
            }
            
            // Reset position info
            trade_info.position_type = 0;
            trade_info.entry_interval = -1;
            
            if(Show_Chart_Labels) {
                CreateTradeLabel(label, clrYellow);
            }
            
            Print("Position closed: ", label, " Profit: ", profit);
        }
    }
}

//+------------------------------------------------------------------+
//| Reduce position size                                             |
//+------------------------------------------------------------------+
void ReducePosition(double reduce_lots)
{
    if(PositionSelect(Symbol())) {
        double current_volume = PositionGetDouble(POSITION_VOLUME);
        double new_volume = MathMax(current_volume - reduce_lots, 0.01);
        
        if(new_volume < current_volume) {
            // Close partial position by opening opposite position
            ENUM_ORDER_TYPE opposite_type = (trade_info.position_type == 1) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            
            if(opposite_type == ORDER_TYPE_BUY) {
                trade.Buy(reduce_lots, Symbol());
            } else {
                trade.Sell(reduce_lots, Symbol());
            }
            
            Print("Position reduced by: ", reduce_lots, " lots");
        }
    }
}

//+------------------------------------------------------------------+
//| Manage existing positions                                        |
//+------------------------------------------------------------------+
void ManagePositions()
{
    if(trade_info.position_type == 0) return;
    
    int current_interval = GetADXInterval(adx_buffer[1]);
    int interval_change = current_interval - trade_info.entry_interval;
    
    // Check for position reduction (ADX rises)
    if(interval_change > 0) {
        double reduce_lots = interval_change * 0.01 * Lot_Multiplier;
        ReducePosition(reduce_lots);
    }
    
    // Check for stop-loss (ADX falls N intervals or more)
    if(interval_change <= -StopLoss_Intervals) {
        string label = (trade_info.position_type == 1) ? "平多" : "平空";
        ClosePosition(label);
    }
}

//+------------------------------------------------------------------+
//| Calculate risk-based lot size                                    |
//+------------------------------------------------------------------+
double CalculateRiskBasedLotSize()
{
    double account_balance = account.Balance();
    double risk_amount = account_balance * Risk_Percent / 100.0;
    
    // Simple risk calculation based on typical Bitcoin volatility
    double point_value = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
    double estimated_sl_points = 1000; // Estimated stop-loss in points
    
    double lot_size = risk_amount / (estimated_sl_points * point_value);
    
    // Normalize to symbol specifications
    double min_lot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    double max_lot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
    double lot_step = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
    
    lot_size = MathMax(lot_size, min_lot);
    lot_size = MathMin(lot_size, max_lot);
    lot_size = NormalizeDouble(lot_size / lot_step, 0) * lot_step;
    
    return lot_size;
}

//+------------------------------------------------------------------+
//| Reset daily counters                                             |
//+------------------------------------------------------------------+
void ResetDailyCounters()
{
    datetime current_date = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
    datetime last_date = StringToTime(TimeToString(trade_info.last_trade_date, TIME_DATE));
    
    if(current_date > last_date) {
        trade_info.daily_trades = 0;
        trade_info.daily_stoplosses = 0;
        trade_info.last_trade_date = TimeCurrent();
    }
}

//+------------------------------------------------------------------+
//| Create trade label on chart                                      |
//+------------------------------------------------------------------+
void CreateTradeLabel(string text, color label_color)
{
    string obj_name = "DMI_EA_Label_" + IntegerToString(TimeCurrent());
    
    double current_price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    if(ObjectCreate(0, obj_name, OBJ_TEXT, 0, TimeCurrent(), current_price)) {
        ObjectSetString(0, obj_name, OBJPROP_TEXT, text);
        ObjectSetInteger(0, obj_name, OBJPROP_COLOR, label_color);
        ObjectSetInteger(0, obj_name, OBJPROP_FONTSIZE, 10);
        ObjectSetString(0, obj_name, OBJPROP_FONT, "Arial Bold");
    }
}

//+------------------------------------------------------------------+
//| Create information panel                                         |
//+------------------------------------------------------------------+
void CreateInfoPanel()
{
    // Create background rectangle
    string panel_name = "DMI_EA_Panel";
    if(ObjectCreate(0, panel_name, OBJ_RECTANGLE_LABEL, 0, 0, 0)) {
        ObjectSetInteger(0, panel_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, panel_name, OBJPROP_XDISTANCE, 10);
        ObjectSetInteger(0, panel_name, OBJPROP_YDISTANCE, 30);
        ObjectSetInteger(0, panel_name, OBJPROP_XSIZE, 300);
        ObjectSetInteger(0, panel_name, OBJPROP_YSIZE, 250);
        ObjectSetInteger(0, panel_name, OBJPROP_BGCOLOR, Panel_Color);
        ObjectSetInteger(0, panel_name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
        ObjectSetInteger(0, panel_name, OBJPROP_WIDTH, 1);
        ObjectSetInteger(0, panel_name, OBJPROP_COLOR, clrWhite);
    }
}

//+------------------------------------------------------------------+
//| Update information panel                                         |
//+------------------------------------------------------------------+
void UpdateInfoPanel()
{
    if(!Show_Info_Panel) return;
    
    // Get current position info
    double current_profit = 0;
    double current_volume = 0;
    if(PositionSelect(Symbol())) {
        current_profit = PositionGetDouble(POSITION_PROFIT);
        current_volume = PositionGetDouble(POSITION_VOLUME);
    }
    
    // Current ADX info
    int current_interval = GetADXInterval(adx_buffer[1]);
    double current_lot_size = CalculateLotSize(current_interval);
    
    // Create info text lines
    string info_lines[15];
    info_lines[0] = "=== DMI Bitcoin EA ===";
    info_lines[1] = "总利润: $" + DoubleToString(trade_info.total_profit, 2);
    info_lines[2] = "当前盈亏: $" + DoubleToString(current_profit, 2);
    info_lines[3] = "";
    info_lines[4] = "今日交易: " + IntegerToString(trade_info.daily_trades);
    info_lines[5] = "今日止损: " + IntegerToString(trade_info.daily_stoplosses) + "/" + IntegerToString(Daily_StopLoss_Limit);
    info_lines[6] = "";
    info_lines[7] = "当前ADX: " + DoubleToString(adx_buffer[1], 1);
    info_lines[8] = "ADX区间: " + IntegerToString(current_interval) + " (" + DoubleToString(adx_intervals[current_interval][0], 0) + "-" + DoubleToString(adx_intervals[current_interval][1], 0) + ")";
    info_lines[9] = "对应手数: " + DoubleToString(current_lot_size, 2);
    info_lines[10] = "";
    info_lines[11] = "持仓方向: " + ((trade_info.position_type == 1) ? "多头" : (trade_info.position_type == -1) ? "空头" : "无");
    info_lines[12] = "持仓手数: " + DoubleToString(current_volume, 2);
    info_lines[13] = "";
    info_lines[14] = (trade_info.is_paused) ? "交易暂停中..." : "交易正常";
    
    // Update text objects
    for(int i = 0; i < 15; i++) {
        string obj_name = "DMI_EA_Info_" + IntegerToString(i);
        
        if(ObjectFind(0, obj_name) < 0) {
            ObjectCreate(0, obj_name, OBJ_LABEL, 0, 0, 0);
            ObjectSetInteger(0, obj_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
            ObjectSetInteger(0, obj_name, OBJPROP_XDISTANCE, 15);
            ObjectSetInteger(0, obj_name, OBJPROP_YDISTANCE, 40 + i * 15);
            ObjectSetInteger(0, obj_name, OBJPROP_COLOR, Text_Color);
            ObjectSetInteger(0, obj_name, OBJPROP_FONTSIZE, 8);
            ObjectSetString(0, obj_name, OBJPROP_FONT, "Consolas");
        }
        
        ObjectSetString(0, obj_name, OBJPROP_TEXT, info_lines[i]);
    }
}

//+------------------------------------------------------------------+
//| Chart event handler                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
    // Handle chart events if needed
}

//+------------------------------------------------------------------+