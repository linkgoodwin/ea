//+------------------------------------------------------------------+
//|                                       StrengthMacdRsiEA.mq5 |
//|                                         Written by Jules (AI) |
//|                                    https://example.com |
//+------------------------------------------------------------------+
#property copyright "Jules (AI)"
#property link      "https://example.com"
#property version   "1.20"
#property description "A trading EA based on Currency Strength, MACD, and RSI. Version 1.20 addresses performance review feedback."

#include <Trade\Trade.mqh>

//--- input parameters
input group             "Strategy Settings"
input int               InpStrengthPeriod = 144;     // Period for Strength Calculation (Bars)
input string            InpCurrencies     = "EUR,USD,JPY,GBP,CHF,AUD,CAD,NZD"; // Currencies to Analyze
input double            InpMinStrengthDiff= 0.1;       // Minimum strength difference to trade

input group             "Indicator Settings"
input int               InpMacdFast       = 12;        // MACD Fast EMA
input int               InpMacdSlow       = 26;        // MACD Slow EMA
input int               InpMacdSignal     = 9;         // MACD Signal SMA
input ENUM_APPLIED_PRICE InpMacdPrice      = PRICE_CLOSE; // MACD Applied Price
input int               InpRsiPeriod      = 14;        // RSI Period
input ENUM_APPLIED_PRICE InpRsiPrice       = PRICE_CLOSE; // RSI Applied Price

input group             "Trading Settings"
input double            InpLots           = 0.01;      // Lots
input ulong             InpMagic          = 12345;     // Magic Number
input int               InpAtrPeriod      = 14;        // ATR Period for SL/TP
input double            InpSlMultiplier   = 2.0;       // ATR SL Multiplier
input double            InpTpMultiplier   = 3.0;       // ATR TP Multiplier
input int               InpSlippage       = 5;         // Slippage

//--- global variables
CTrade   trade;

//--- currency strength related
string   g_currencies[];
struct CurrencyStrength
  {
   string            name;
   double            strength;
  };

//--- Indicator Handles Management
struct SymbolHandles
  {
   string            symbol;
   int               h_macd;
   int               h_rsi;
   int               h_atr;
  };
SymbolHandles g_handles[];

//+------------------------------------------------------------------+
//| Helper function to find a valid symbol name for a currency pair  |
//+------------------------------------------------------------------+
string GetSymbolName(string ccy1, string ccy2)
  {
   string symbol_name = ccy1 + ccy2;
   if(SymbolExist(symbol_name, false))
     {
      if(SymbolSelect(symbol_name, true)) return(symbol_name);
     }
   symbol_name = ccy2 + ccy1;
   if(SymbolExist(symbol_name, false))
     {
      if(SymbolSelect(symbol_name, true)) return(symbol_name);
     }
   return "";
  }

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- Initialize CTrade
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetSlippage(InpSlippage);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

//--- Parse currency string
   StringSplit(InpCurrencies, ',', g_currencies);
   if(ArraySize(g_currencies) < 2)
     {
      Print("At least 2 currencies must be specified!");
      return(INIT_FAILED);
     }

//--- Pre-load all indicator handles for performance
   int total_pairs = 0;
   for(int i = 0; i < ArraySize(g_currencies); i++)
     {
      for(int j = i + 1; j < ArraySize(g_currencies); j++)
        {
         string symbol = GetSymbolName(g_currencies[i], g_currencies[j]);
         if(symbol != "")
           {
            ArrayResize(g_handles, total_pairs + 1);
            g_handles[total_pairs].symbol = symbol;
            g_handles[total_pairs].h_macd = iMACD(symbol, _Period, InpMacdFast, InpMacdSlow, InpMacdSignal, InpMacdPrice);
            g_handles[total_pairs].h_rsi = iRSI(symbol, _Period, InpRsiPeriod, InpRsiPrice);
            g_handles[total_pairs].h_atr = iATR(symbol, _Period, InpAtrPeriod);
            if(g_handles[total_pairs].h_macd==INVALID_HANDLE || g_handles[total_pairs].h_rsi==INVALID_HANDLE || g_handles[total_pairs].h_atr==INVALID_HANDLE)
            {
               Print("Failed to create indicators for ", symbol, ". Please ensure it is visible in Market Watch.");
            }
            total_pairs++;
           }
        }
     }
   Print("EA Initialized. ", total_pairs, " currency pairs pre-loaded.");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//--- Release all indicator handles
   for(int i = 0; i < ArraySize(g_handles); i++)
     {
      if(g_handles[i].h_macd != INVALID_HANDLE) IndicatorRelease(g_handles[i].h_macd);
      if(g_handles[i].h_rsi != INVALID_HANDLE) IndicatorRelease(g_handles[i].h_rsi);
      if(g_handles[i].h_atr != INVALID_HANDLE) IndicatorRelease(g_handles[i].h_atr);
     }
   Print("EA Deinitialized. Reason: ", reason);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//--- New bar check
   static datetime last_time = 0;
   datetime current_time = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LAST_BAR_DATE);
   if(current_time == last_time) return;
   last_time = current_time;

//--- Check for existing position
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetInteger(POSITION_MAGIC) == InpMagic) return;
     }

//--- STEP 1: Calculate currency strength
   CurrencyStrength strength_data[];
   CalculateCurrencyStrength(strength_data);
   SortStrength(strength_data);

//--- STEP 2: Identify trade opportunity
   string strongest_ccy = strength_data[0].name;
   string weakest_ccy = strength_data[ArraySize(strength_data) - 1].name;

   if(strength_data[0].strength - strength_data[ArraySize(strength_data) - 1].strength < InpMinStrengthDiff) return;

   string trade_symbol = GetSymbolName(strongest_ccy, weakest_ccy);
   if(trade_symbol == "") return;

   ENUM_ORDER_TYPE trade_direction = (StringFind(trade_symbol, strongest_ccy, 0) == 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

//--- STEP 3: Get indicator data
   int macd_handle = INVALID_HANDLE, rsi_handle = INVALID_HANDLE, atr_handle = INVALID_HANDLE;
   for(int i = 0; i < ArraySize(g_handles); i++)
     {
      if(g_handles[i].symbol == trade_symbol)
        {
         macd_handle = g_handles[i].h_macd;
         rsi_handle = g_handles[i].h_rsi;
         atr_handle = g_handles[i].h_atr;
         break;
        }
     }
   if(macd_handle == INVALID_HANDLE) return;

   double macd_main[3], macd_signal[3], rsi_values[2], atr_values[1];
   if(CopyBuffer(macd_handle, 0, 1, 3, macd_main) < 3 || CopyBuffer(macd_handle, 1, 1, 3, macd_signal) < 3 ||
      CopyBuffer(rsi_handle, 0, 1, 2, rsi_values) < 2 || CopyBuffer(atr_handle, 0, 0, 1, atr_values) < 1)
     {
      return;
     }

//--- STEP 4: Check Entry Conditions
   bool is_buy_signal = trade_direction == ORDER_TYPE_BUY && macd_main[1] > macd_signal[1] && macd_main[2] <= macd_signal[2] && rsi_values[1] > 50;
   bool is_sell_signal = trade_direction == ORDER_TYPE_SELL && macd_main[1] < macd_signal[1] && macd_main[2] >= macd_signal[2] && rsi_values[1] < 50;

   if(is_buy_signal || is_sell_signal)
     {
      //--- STEP 5: Execute trade
      double price = SymbolInfoDouble(trade_symbol, is_buy_signal ? SYMBOL_ASK : SYMBOL_BID);
      double sl_dist = NormalizeDouble(atr_values[0] * InpSlMultiplier, (int)SymbolInfoInteger(trade_symbol, SYMBOL_DIGITS));
      double tp_dist = NormalizeDouble(atr_values[0] * InpTpMultiplier, (int)SymbolInfoInteger(trade_symbol, SYMBOL_DIGITS));
      double stop_loss = is_buy_signal ? price - sl_dist : price + sl_dist;
      double take_profit = is_buy_signal ? price + tp_dist : price - tp_dist;

      string comment = "Str:" + strongest_ccy + "/Wk:" + weakest_ccy;
      MqlTradeResult result;
      trade.PositionOpen(trade_symbol, trade_direction, InpLots, price, stop_loss, take_profit, comment, result);
      Print("Trade execution attempted for ", trade_symbol, ". Result: ", result.retcode, " - ", result.comment);
     }
  }

//+------------------------------------------------------------------+
//| Calculates the strength of each currency                         |
//+------------------------------------------------------------------+
void CalculateCurrencyStrength(out CurrencyStrength &strength_data[])
  {
   ArrayResize(strength_data, ArraySize(g_currencies));
   for(int i = 0; i < ArraySize(g_currencies); i++){strength_data[i].name = g_currencies[i]; strength_data[i].strength = 0.0;}

   for(int i = 0; i < ArraySize(g_currencies); i++)
     {
      int pairs_counted = 0;
      for(int j = 0; j < ArraySize(g_currencies); j++)
        {
         if(i == j) continue;
         string symbol = GetSymbolName(g_currencies[i], g_currencies[j]);
         if(symbol == "" || Bars(symbol, _Period) < InpStrengthPeriod + 1) continue;
         double p_then_arr[1];
         if(CopyClose(symbol, _Period, InpStrengthPeriod, 1, p_then_arr) != 1) continue;
         double p_now = SymbolInfoDouble(symbol, SYMBOL_BID);
         if(p_then_arr[0] == 0) continue;
         double change = (p_now - p_then_arr[0]) / p_then_arr[0];
         if(StringFind(symbol, g_currencies[i], 0) == 0) strength_data[i].strength += change;
         else strength_data[i].strength -= change;
         pairs_counted++;
        }
      if(pairs_counted > 0) strength_data[i].strength /= pairs_counted;
     }
  }

//+------------------------------------------------------------------+
//| Sorts the currency strength array (strongest first)              |
//+------------------------------------------------------------------+
void SortStrength(CurrencyStrength &str_arr[])
  {
   int n = ArraySize(str_arr);
   CurrencyStrength temp;
   for(int i = 0; i < n - 1; i++)
     {
      for(int j = i + 1; j < n; j++)
        {
         if(str_arr[i].strength < str_arr[j].strength)
           {
            temp = str_arr[i]; str_arr[i] = str_arr[j]; str_arr[j] = temp;
           }
        }
     }
  }
//+------------------------------------------------------------------+
