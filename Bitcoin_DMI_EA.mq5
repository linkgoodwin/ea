//+------------------------------------------------------------------+
//|                                            Bitcoin_DMI_EA.mq5 |
//|                        Copyright 2024, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property description "Bitcoin DMI Trading EA with ADX-based lot sizing"

//--- Include necessary libraries
#include <Trade\Trade.mqh>

//--- Input parameters
input group "=== DMI Settings ==="
input int      DMI_Period = 14;                    // DMI Period (5-50)
input ENUM_TIMEFRAMES Timeframe = PERIOD_M15;      // Timeframe
input double   Lot_Multiplier = 1.0;               // Lot Size Multiplier (0.1-10.0)
input int      StopLoss_Intervals = 2;             // Stop-Loss Interval Count (1-5)

input group "=== Risk Management ==="
input double   Risk_Percent = 2.0;                 // Risk per Trade % (0.5-5.0)
input int      Daily_StopLoss_Limit = 3;           // Daily Stop-Loss Limit (1-10)
input int      Trading_Pause_Hours = 12;           // Trading Pause Duration (1-24 hours)

input group "=== Trading Controls ==="
input bool     Allow_Buy = true;                   // Allow Buy Trades
input bool     Allow_Sell = true;                  // Allow Sell Trades

//--- Global variables
CTrade trade;
int dmi_handle;
double plus_di[], minus_di[], adx[];
datetime last_bar_time = 0;
datetime trading_pause_until = 0;

//--- Position tracking variables
struct PositionInfo {
    bool is_open;
    ENUM_POSITION_TYPE type;
    double entry_lot_size;
    int entry_adx_interval;
    datetime entry_time;
    double entry_price;
    int current_adx_interval;
    double current_lot_size;
};

PositionInfo current_position;

//--- Statistics tracking
struct DailyStats {
    int trade_count;
    int stop_loss_count;
    double total_profit;
    datetime last_reset_date;
};

DailyStats daily_stats;

//--- Chart objects for visualization
string chart_prefix = "DMI_EA_";

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    //--- Validate input parameters
    if(DMI_Period < 5 || DMI_Period > 50) {
        Print("Error: DMI_Period must be between 5 and 50");
        return INIT_PARAMETERS_INCORRECT;
    }
    
    if(Lot_Multiplier < 0.1 || Lot_Multiplier > 10.0) {
        Print("Error: Lot_Multiplier must be between 0.1 and 10.0");
        return INIT_PARAMETERS_INCORRECT;
    }
    
    if(StopLoss_Intervals < 1 || StopLoss_Intervals > 5) {
        Print("Error: StopLoss_Intervals must be between 1 and 5");
        return INIT_PARAMETERS_INCORRECT;
    }
    
    if(Risk_Percent < 0.5 || Risk_Percent > 5.0) {
        Print("Error: Risk_Percent must be between 0.5 and 5.0");
        return INIT_PARAMETERS_INCORRECT;
    }
    
    //--- Initialize DMI indicator
    dmi_handle = iADX(_Symbol, Timeframe, DMI_Period);
    if(dmi_handle == INVALID_HANDLE) {
        Print("Error: Failed to create DMI indicator handle");
        return INIT_FAILED;
    }
    
    //--- Initialize arrays
    ArraySetAsSeries(plus_di, true);
    ArraySetAsSeries(minus_di, true);
    ArraySetAsSeries(adx, true);
    
    //--- Initialize position tracking
    InitializePosition();
    
    //--- Initialize daily stats
    InitializeDailyStats();
    
    //--- Set up chart visualization
    CreateChartObjects();
    
    Print("Bitcoin DMI EA initialized successfully");
    Print("Symbol: ", _Symbol, ", Timeframe: ", EnumToString(Timeframe));
    Print("DMI Period: ", DMI_Period, ", Lot Multiplier: ", Lot_Multiplier);
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    //--- Release indicator handle
    if(dmi_handle != INVALID_HANDLE)
        IndicatorRelease(dmi_handle);
    
    //--- Clean up chart objects
    CleanupChartObjects();
    
    Print("Bitcoin DMI EA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    //--- Check if new bar
    if(!IsNewBar())
        return;
    
    //--- Check trading pause
    if(IsTradingPaused())
        return;
    
    //--- Reset daily stats if new day
    ResetDailyStatsIfNeeded();
    
    //--- Update DMI values
    if(!UpdateDMIValues())
        return;
    
    //--- Update current position info
    UpdateCurrentPosition();
    
    //--- Check for exit/reduction conditions first
    if(current_position.is_open) {
        CheckExitConditions();
    }
    
    //--- Check for entry conditions
    if(!current_position.is_open) {
        CheckEntryConditions();
    }
    
    //--- Update visualization
    UpdateVisualization();
}

//+------------------------------------------------------------------+
//| Check if new bar has formed                                     |
//+------------------------------------------------------------------+
bool IsNewBar()
{
    datetime current_bar_time = iTime(_Symbol, Timeframe, 0);
    if(current_bar_time != last_bar_time) {
        last_bar_time = current_bar_time;
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Check if trading is paused                                      |
//+------------------------------------------------------------------+
bool IsTradingPaused()
{
    if(trading_pause_until > 0 && TimeCurrent() < trading_pause_until) {
        return true;
    }
    else if(trading_pause_until > 0 && TimeCurrent() >= trading_pause_until) {
        trading_pause_until = 0;
        Print("Trading pause ended. Resuming trading.");
    }
    return false;
}

//+------------------------------------------------------------------+
//| Update DMI indicator values                                     |
//+------------------------------------------------------------------+
bool UpdateDMIValues()
{
    //--- Copy ADX values
    if(CopyBuffer(dmi_handle, 0, 0, 3, adx) <= 0) {
        Print("Error: Failed to copy ADX buffer");
        return false;
    }
    
    //--- Copy +DI values
    if(CopyBuffer(dmi_handle, 1, 0, 3, plus_di) <= 0) {
        Print("Error: Failed to copy +DI buffer");
        return false;
    }
    
    //--- Copy -DI values
    if(CopyBuffer(dmi_handle, 2, 0, 3, minus_di) <= 0) {
        Print("Error: Failed to copy -DI buffer");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Get ADX interval (0-9) based on ADX value                       |
//+------------------------------------------------------------------+
int GetADXInterval(double adx_value)
{
    if(adx_value >= 90) return 0;  // 90-100: 0.01 lots
    if(adx_value >= 80) return 1;  // 80-90: 0.02 lots
    if(adx_value >= 70) return 2;  // 70-80: 0.03 lots
    if(adx_value >= 60) return 3;  // 60-70: 0.04 lots
    if(adx_value >= 50) return 4;  // 50-60: 0.05 lots
    if(adx_value >= 40) return 5;  // 40-50: 0.06 lots
    if(adx_value >= 30) return 6;  // 30-40: 0.07 lots
    if(adx_value >= 20) return 7;  // 20-30: 0.08 lots
    if(adx_value >= 10) return 8;  // 10-20: 0.09 lots
    return 9;                      // 0-10: 0.10 lots
}

//+------------------------------------------------------------------+
//| Calculate lot size based on ADX interval                        |
//+------------------------------------------------------------------+
double CalculateLotSize(int adx_interval)
{
    double base_lot = 0.01 + (9 - adx_interval) * 0.01;  // 0.01 to 0.10
    double lot_size = base_lot * Lot_Multiplier;
    
    //--- Apply risk management
    double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double risk_amount = account_balance * Risk_Percent / 100.0;
    
    //--- Calculate stop loss distance (simplified)
    double stop_loss_distance = 1000 * _Point;  // 1000 points for Bitcoin
    double max_lot_by_risk = risk_amount / (stop_loss_distance * _Point);
    
    //--- Use the smaller of the two
    lot_size = MathMin(lot_size, max_lot_by_risk);
    
    //--- Normalize lot size
    double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    lot_size = MathMax(min_lot, MathMin(max_lot, lot_size));
    lot_size = NormalizeDouble(lot_size / lot_step, 0) * lot_step;
    
    return lot_size;
}

//+------------------------------------------------------------------+
//| Check entry conditions                                          |
//+------------------------------------------------------------------+
void CheckEntryConditions()
{
    if(ArraySize(plus_di) < 3 || ArraySize(minus_di) < 3)
        return;
    
    //--- Check for +DI crossing above -DI (Buy signal)
    if(Allow_Buy && plus_di[0] > minus_di[0] && plus_di[1] <= minus_di[1]) {
        OpenPosition(ORDER_TYPE_BUY);
    }
    //--- Check for -DI crossing above +DI (Sell signal)
    else if(Allow_Sell && minus_di[0] > plus_di[0] && minus_di[1] <= plus_di[1]) {
        OpenPosition(ORDER_TYPE_SELL);
    }
}

//+------------------------------------------------------------------+
//| Open new position                                               |
//+------------------------------------------------------------------+
void OpenPosition(ENUM_ORDER_TYPE order_type)
{
    int adx_interval = GetADXInterval(adx[0]);
    double lot_size = CalculateLotSize(adx_interval);
    
    double price = (order_type == ORDER_TYPE_BUY) ? 
                   SymbolInfoDouble(_Symbol, SYMBOL_ASK) : 
                   SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    //--- Execute trade
    bool result = false;
    if(order_type == ORDER_TYPE_BUY) {
        result = trade.Buy(lot_size, _Symbol, price, 0, 0, "DMI Buy");
    } else {
        result = trade.Sell(lot_size, _Symbol, price, 0, 0, "DMI Sell");
    }
    
    if(result) {
        //--- Update position tracking
        current_position.is_open = true;
        current_position.type = (order_type == ORDER_TYPE_BUY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
        current_position.entry_lot_size = lot_size;
        current_position.entry_adx_interval = adx_interval;
        current_position.entry_time = TimeCurrent();
        current_position.entry_price = price;
        current_position.current_adx_interval = adx_interval;
        current_position.current_lot_size = lot_size;
        
        //--- Update statistics
        daily_stats.trade_count++;
        
        //--- Create entry label
        string label = (order_type == ORDER_TYPE_BUY) ? "开多" : "开空";
        CreateEntryLabel(label, adx_interval, lot_size);
        
        Print("Position opened: ", EnumToString(order_type), 
              ", Lot: ", lot_size, 
              ", ADX Interval: ", adx_interval,
              ", ADX Value: ", DoubleToString(adx[0], 2));
    } else {
        Print("Error opening position: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| Check exit conditions                                           |
//+------------------------------------------------------------------+
void CheckExitConditions()
{
    if(!current_position.is_open)
        return;
    
    int current_interval = GetADXInterval(adx[0]);
    int entry_interval = current_position.entry_adx_interval;
    
    //--- Check for stop loss (ADX falls N intervals below entry)
    if(current_interval >= entry_interval + StopLoss_Intervals) {
        ClosePosition("Stop Loss");
        return;
    }
    
    //--- Check for position reduction (ADX rises above entry interval)
    if(current_interval < entry_interval) {
        int intervals_risen = entry_interval - current_interval;
        double reduction_lots = intervals_risen * 0.01 * Lot_Multiplier;
        
        if(reduction_lots > 0 && current_position.current_lot_size > reduction_lots) {
            ReducePosition(reduction_lots);
        }
    }
    
    //--- Update current position info
    current_position.current_adx_interval = current_interval;
}

//+------------------------------------------------------------------+
//| Reduce position size                                            |
//+------------------------------------------------------------------+
void ReducePosition(double reduction_lots)
{
    if(!PositionSelect(_Symbol))
        return;
    
    double current_lots = PositionGetDouble(POSITION_VOLUME);
    double new_lots = current_lots - reduction_lots;
    
    //--- Normalize lot size
    double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    new_lots = MathMax(min_lot, new_lots);
    new_lots = NormalizeDouble(new_lots / lot_step, 0) * lot_step;
    
    if(new_lots < min_lot) {
        ClosePosition("Reduction");
        return;
    }
    
    //--- Execute partial close
    if(trade.PositionClosePartial(_Symbol, reduction_lots)) {
        current_position.current_lot_size = new_lots;
        Print("Position reduced by ", reduction_lots, " lots. New size: ", new_lots);
    }
}

//+------------------------------------------------------------------+
//| Close entire position                                           |
//+------------------------------------------------------------------+
void ClosePosition(string reason)
{
    if(!PositionSelect(_Symbol))
        return;
    
    if(trade.PositionClose(_Symbol)) {
        //--- Update statistics
        double profit = PositionGetDouble(POSITION_PROFIT);
        daily_stats.total_profit += profit;
        
        if(profit < 0) {
            daily_stats.stop_loss_count++;
            
            //--- Check daily stop loss limit
            if(daily_stats.stop_loss_count >= Daily_StopLoss_Limit) {
                trading_pause_until = TimeCurrent() + Trading_Pause_Hours * 3600;
                Print("Daily stop loss limit reached. Trading paused for ", Trading_Pause_Hours, " hours.");
            }
        }
        
        //--- Create exit label
        string label = (current_position.type == POSITION_TYPE_BUY) ? "平多" : "平空";
        CreateExitLabel(label, reason);
        
        //--- Reset position tracking
        InitializePosition();
        
        Print("Position closed: ", reason, ", Profit: ", DoubleToString(profit, 2));
    }
}

//+------------------------------------------------------------------+
//| Update current position information                             |
//+------------------------------------------------------------------+
void UpdateCurrentPosition()
{
    if(PositionSelect(_Symbol)) {
        current_position.is_open = true;
        current_position.type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        current_position.current_lot_size = PositionGetDouble(POSITION_VOLUME);
    } else {
        current_position.is_open = false;
    }
}

//+------------------------------------------------------------------+
//| Initialize position tracking                                    |
//+------------------------------------------------------------------+
void InitializePosition()
{
    current_position.is_open = false;
    current_position.type = POSITION_TYPE_BUY;
    current_position.entry_lot_size = 0;
    current_position.entry_adx_interval = 0;
    current_position.entry_time = 0;
    current_position.entry_price = 0;
    current_position.current_adx_interval = 0;
    current_position.current_lot_size = 0;
}

//+------------------------------------------------------------------+
//| Initialize daily statistics                                     |
//+------------------------------------------------------------------+
void InitializeDailyStats()
{
    daily_stats.trade_count = 0;
    daily_stats.stop_loss_count = 0;
    daily_stats.total_profit = 0;
    daily_stats.last_reset_date = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Reset daily statistics if new day                               |
//+------------------------------------------------------------------+
void ResetDailyStatsIfNeeded()
{
    MqlDateTime current_time, last_reset_time;
    TimeToStruct(TimeCurrent(), current_time);
    TimeToStruct(daily_stats.last_reset_date, last_reset_time);
    
    if(current_time.day != last_reset_time.day || 
       current_time.mon != last_reset_time.mon || 
       current_time.year != last_reset_time.year) {
        
        daily_stats.trade_count = 0;
        daily_stats.stop_loss_count = 0;
        daily_stats.total_profit = 0;
        daily_stats.last_reset_date = TimeCurrent();
        
        Print("Daily statistics reset for new day");
    }
}

//+------------------------------------------------------------------+
//| Create entry label on chart                                     |
//+------------------------------------------------------------------+
void CreateEntryLabel(string label, int adx_interval, double lot_size)
{
    string obj_name = chart_prefix + "Entry_" + IntegerToString(TimeCurrent());
    
    if(ObjectCreate(0, obj_name, OBJ_TEXT, 0, TimeCurrent(), iClose(_Symbol, Timeframe, 0))) {
        ObjectSetString(0, obj_name, OBJPROP_TEXT, label + "\n" + 
                       "ADX:" + IntegerToString(adx_interval) + "\n" + 
                       "L:" + DoubleToString(lot_size, 2));
        ObjectSetInteger(0, obj_name, OBJPROP_COLOR, (label == "开多") ? clrLime : clrRed);
        ObjectSetInteger(0, obj_name, OBJPROP_FONTSIZE, 8);
        ObjectSetInteger(0, obj_name, OBJPROP_ANCHOR, ANCHOR_BOTTOM);
    }
}

//+------------------------------------------------------------------+
//| Create exit label on chart                                      |
//+------------------------------------------------------------------+
void CreateExitLabel(string label, string reason)
{
    string obj_name = chart_prefix + "Exit_" + IntegerToString(TimeCurrent());
    
    if(ObjectCreate(0, obj_name, OBJ_TEXT, 0, TimeCurrent(), iClose(_Symbol, Timeframe, 0))) {
        ObjectSetString(0, obj_name, OBJPROP_TEXT, label + "\n" + reason);
        ObjectSetInteger(0, obj_name, OBJPROP_COLOR, clrYellow);
        ObjectSetInteger(0, obj_name, OBJPROP_FONTSIZE, 8);
        ObjectSetInteger(0, obj_name, OBJPROP_ANCHOR, ANCHOR_TOP);
    }
}

//+------------------------------------------------------------------+
//| Create chart objects for visualization                          |
//+------------------------------------------------------------------+
void CreateChartObjects()
{
    //--- Create data panel background
    string panel_name = chart_prefix + "DataPanel";
    if(ObjectCreate(0, panel_name, OBJ_RECTANGLE_LABEL, 0, 0, 0)) {
        ObjectSetInteger(0, panel_name, OBJPROP_XDISTANCE, 10);
        ObjectSetInteger(0, panel_name, OBJPROP_YDISTANCE, 30);
        ObjectSetInteger(0, panel_name, OBJPROP_XSIZE, 300);
        ObjectSetInteger(0, panel_name, OBJPROP_YSIZE, 200);
        ObjectSetInteger(0, panel_name, OBJPROP_BGCOLOR, C'20,20,20');
        ObjectSetInteger(0, panel_name, OBJPROP_BORDER_COLOR, clrWhite);
        ObjectSetInteger(0, panel_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    }
    
    //--- Create settings panel
    string settings_name = chart_prefix + "SettingsPanel";
    if(ObjectCreate(0, settings_name, OBJ_RECTANGLE_LABEL, 0, 0, 0)) {
        ObjectSetInteger(0, settings_name, OBJPROP_XDISTANCE, 10);
        ObjectSetInteger(0, settings_name, OBJPROP_YDISTANCE, 240);
        ObjectSetInteger(0, settings_name, OBJPROP_XSIZE, 300);
        ObjectSetInteger(0, settings_name, OBJPROP_YSIZE, 150);
        ObjectSetInteger(0, settings_name, OBJPROP_BGCOLOR, C'20,20,20');
        ObjectSetInteger(0, settings_name, OBJPROP_BORDER_COLOR, clrWhite);
        ObjectSetInteger(0, settings_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    }
}

//+------------------------------------------------------------------+
//| Update visualization                                             |
//+------------------------------------------------------------------+
void UpdateVisualization()
{
    UpdateDataPanel();
    UpdateSettingsPanel();
}

//+------------------------------------------------------------------+
//| Update data panel                                               |
//+------------------------------------------------------------------+
void UpdateDataPanel()
{
    //--- Total profit
    string profit_text = "总盈亏: $" + DoubleToString(daily_stats.total_profit, 2);
    UpdatePanelText("Profit", profit_text, 20, 50, clrWhite);
    
    //--- Daily trade count
    string trade_text = "今日交易: " + IntegerToString(daily_stats.trade_count);
    UpdatePanelText("Trades", trade_text, 20, 70, clrWhite);
    
    //--- Daily stop loss count
    string sl_text = "今日止损: " + IntegerToString(daily_stats.stop_loss_count) + 
                    "/" + IntegerToString(Daily_StopLoss_Limit);
    UpdatePanelText("StopLoss", sl_text, 20, 90, clrWhite);
    
    //--- Current ADX interval
    int current_interval = GetADXInterval(adx[0]);
    string adx_text = "ADX区间: " + IntegerToString(current_interval) + 
                     " (ADX:" + DoubleToString(adx[0], 1) + ")";
    UpdatePanelText("ADX", adx_text, 20, 110, clrWhite);
    
    //--- Current lot size
    double lot_size = CalculateLotSize(current_interval);
    string lot_text = "手数: " + DoubleToString(lot_size, 2);
    UpdatePanelText("LotSize", lot_text, 20, 130, clrWhite);
    
    //--- Current position
    string pos_text = "持仓: ";
    if(current_position.is_open) {
        pos_text += (current_position.type == POSITION_TYPE_BUY) ? "多头" : "空头";
        pos_text += " (" + DoubleToString(current_position.current_lot_size, 2) + ")";
    } else {
        pos_text += "无";
    }
    UpdatePanelText("Position", pos_text, 20, 150, clrWhite);
    
    //--- Trading status
    string status_text = "状态: ";
    if(IsTradingPaused()) {
        status_text += "暂停交易";
    } else {
        status_text += "正常交易";
    }
    UpdatePanelText("Status", status_text, 20, 170, clrWhite);
}

//+------------------------------------------------------------------+
//| Update settings panel                                           |
//+------------------------------------------------------------------+
void UpdateSettingsPanel()
{
    string settings_text = "EA设置:\n";
    settings_text += "DMI周期: " + IntegerToString(DMI_Period) + "\n";
    settings_text += "时间框架: " + EnumToString(Timeframe) + "\n";
    settings_text += "手数倍数: " + DoubleToString(Lot_Multiplier, 1) + "\n";
    settings_text += "止损区间: " + IntegerToString(StopLoss_Intervals) + "\n";
    settings_text += "风险比例: " + DoubleToString(Risk_Percent, 1) + "%\n";
    settings_text += "允许买入: " + (Allow_Buy ? "是" : "否") + "\n";
    settings_text += "允许卖出: " + (Allow_Sell ? "是" : "否");
    
    UpdatePanelText("Settings", settings_text, 20, 260, clrLightBlue);
}

//+------------------------------------------------------------------+
//| Update panel text                                               |
//+------------------------------------------------------------------+
void UpdatePanelText(string name, string text, int x, int y, color clr)
{
    string obj_name = chart_prefix + name;
    
    if(ObjectFind(0, obj_name) < 0) {
        ObjectCreate(0, obj_name, OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, obj_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    }
    
    ObjectSetString(0, obj_name, OBJPROP_TEXT, text);
    ObjectSetInteger(0, obj_name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, obj_name, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, obj_name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, obj_name, OBJPROP_FONTSIZE, 8);
}

//+------------------------------------------------------------------+
//| Clean up chart objects                                          |
//+------------------------------------------------------------------+
void CleanupChartObjects()
{
    ObjectsDeleteAll(0, chart_prefix);
}

//+------------------------------------------------------------------+