//+------------------------------------------------------------------+
//|                                       StrengthMacdRsiEA.mq5 |
//|                                         Written by Jules (AI) |
//|                                    https://example.com |
//+------------------------------------------------------------------+
#property copyright "Jules (AI)"
#property link      "https://example.com"
#property version   "1.32" // Final version with Chinese comments
#property description "一个基于货币强弱、MACD和RSI指标的交易EA。v1.32添加中文注释。"

#include <Trade\Trade.mqh>

//--- 输入参数
input group             "策略设置"
input int               InpStrengthPeriod = 144;     // 强弱计算:所用的历史K线周期
input string            InpCurrencies     = "EUR,USD,JPY,GBP,CHF,AUD,CAD,NZD"; // 强弱计算:需要分析的货币列表
input double            InpMinStrengthDiff= 0.1;       // 交易过滤:最强和最弱货币的最小强度差

input group             "指标设置"
input int               InpMacdFast       = 12;        // MACD指标:快线周期
input int               InpMacdSlow       = 26;        // MACD指标:慢线周期
input int               InpMacdSignal     = 9;         // MACD指标:信号线周期
input ENUM_APPLIED_PRICE InpMacdPrice      = PRICE_CLOSE; // MACD指标:计算价格
input int               InpRsiPeriod      = 14;        // RSI指标:周期
input ENUM_APPLIED_PRICE InpRsiPrice       = PRICE_CLOSE; // RSI指标:计算价格

input group             "交易设置"
input double            InpLots           = 0.01;      // 交易手数
input ulong             InpMagic          = 12345;     // 魔术号 (用于EA识别自己的订单)
input int               InpAtrPeriod      = 14;        // ATR指标:周期 (用于计算止损止盈)
input double            InpSlMultiplier   = 2.0;       // 止损乘数: ATR数值 * 该乘数 = 止损距离
input double            InpTpMultiplier   = 3.0;       // 止盈乘数: ATR数值 * 该乘数 = 止盈距离
input int               InpSlippage       = 5;         // 允许滑点

//--- 全局变量
CTrade   trade; // MQL5标准交易类

//--- 货币强弱相关
string   g_currencies[]; // 用于存储待分析的货币名称
struct CurrencyStrength
  {
   string            name;     // 货币名称
   double            strength; // 计算出的强度值
  };

//--- 指标句柄管理
struct SymbolHandles
  {
   string            symbol;   // 交易品种名称
   int               h_macd;   // MACD句柄
   int               h_rsi;    // RSI句柄
   int               h_atr;    // ATR句柄
  };
SymbolHandles g_handles[]; // 用于存储所有需要用到的指标句柄

//--- 辅助函数的前向声明
string GetSymbolName(string ccy1, string ccy2);
void   CalculateCurrencyStrength(CurrencyStrength &strength_data[]);
void   SortStrength(CurrencyStrength &str_arr[]);

//+------------------------------------------------------------------+
//| EA初始化函数                                                     |
//+------------------------------------------------------------------+
int OnInit()
  {
   //--- 初始化交易类
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetSlippage(InpSlippage);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   //--- 解析货币列表字符串
   StringSplit(InpCurrencies, ',', g_currencies);
   if(ArraySize(g_currencies) < 2)
     {
      Print("至少需要指定2种货币才能进行强弱计算!");
      return(INIT_FAILED);
     }

   //--- 为提高性能, 在初始化时预先加载所有可能用到的指标句柄
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
               Print("为 ", symbol, " 创建指标失败。请确保该品种在市场报价中可见。");
              }
            total_pairs++;
           }
        }
     }
   Print("EA初始化成功。预加载了 ", total_pairs, " 个货币对的指标。");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| EA退出函数                                                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   //--- 释放所有在OnInit中创建的指标句柄
   Print("EA退出，释放所有指标句柄...");
   for(int i = 0; i < ArraySize(g_handles); i++)
     {
      if(g_handles[i].h_macd != INVALID_HANDLE) IndicatorRelease(g_handles[i].h_macd);
      if(g_handles[i].h_rsi != INVALID_HANDLE) IndicatorRelease(g_handles[i].h_rsi);
      if(g_handles[i].h_atr != INVALID_HANDLE) IndicatorRelease(g_handles[i].h_atr);
     }
   Print("EA已退出。原因代码: ", reason);
  }

//+------------------------------------------------------------------+
//| EA主逻辑函数 (每个Tick或每个Bar触发)                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   //--- 新Bar判断: 确保每个Bar只执行一次逻辑
   static datetime last_time = 0;
   datetime current_time = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LAST_BAR_DATE);
   if(current_time == last_time)
     {
      return; // 如果不是新Bar, 则直接退出
     }
   last_time = current_time;

   //--- 持仓判断: 如果已有持仓, 则不进行新的交易
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetInteger(POSITION_MAGIC) == InpMagic)
        {
         return;
        }
     }

   //--- 第一步: 计算货币强弱
   CurrencyStrength strength_data[];
   CalculateCurrencyStrength(strength_data);
   SortStrength(strength_data); // 排序, strength_data[0]为最强

   //--- 第二步: 识别交易机会
   string strongest_ccy = strength_data[0].name;
   string weakest_ccy = strength_data[ArraySize(strength_data) - 1].name;

   // 如果最强和最弱的货币强度差异过小, 则认为没有明确趋势, 退出
   if(strength_data[0].strength - strength_data[ArraySize(strength_data) - 1].strength < InpMinStrengthDiff)
     {
      return;
     }

   // 组合出交易品种, 例如: 最强EUR, 最弱USD -> EURUSD
   string trade_symbol = GetSymbolName(strongest_ccy, weakest_ccy);
   if(trade_symbol == "")
     {
      return; // 如果无法组成有效的交易品种, 退出
     }

   // 判断交易方向: 如果最强货币是基础货币(前三位), 则为买入, 否则为卖出
   ENUM_ORDER_TYPE trade_direction = (StringFind(trade_symbol, strongest_ccy, 0) == 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

   //--- 第三步: 从预加载的句柄中获取指标数据
   int macd_handle = INVALID_HANDLE;
   int rsi_handle = INVALID_HANDLE;
   int atr_handle = INVALID_HANDLE;
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
   if(macd_handle == INVALID_HANDLE)
     {
      return; // 如果没找到对应品种的指标句柄, 退出
     }

   double macd_main[3], macd_signal[3], rsi_values[2], atr_values[1];
   // 从句柄复制指标数据到数组中。注意: [0]是当前K线, [1]是上一个K线, [2]是上上个K线
   if(CopyBuffer(macd_handle, 0, 0, 3, macd_main) < 3 ||      // MACD主线
      CopyBuffer(macd_handle, 1, 0, 3, macd_signal) < 3 ||    // MACD信号线
      CopyBuffer(rsi_handle, 0, 0, 2, rsi_values) < 2 ||      // RSI值
      CopyBuffer(atr_handle, 0, 1, 1, atr_values) < 1)        // ATR值(取已收盘的上一根K线的值)
     {
      return; // 如果数据复制失败, 退出
     }

   //--- 第四步: 检查入场条件
   // 买入信号: MACD在上一根K线发生金叉 (主线从下往上穿越信号线) + RSI > 50
   bool is_buy_signal = (trade_direction == ORDER_TYPE_BUY &&
                         macd_main[1] > macd_signal[1] &&      // 上一根K线, 主线 > 信号线
                         macd_main[2] <= macd_signal[2] &&     // 上上根K线, 主线 <= 信号线
                         rsi_values[1] > 50);                 // 上一根K线的RSI > 50

   // 卖出信号: MACD在上一根K线发生死叉 (主线从上往下穿越信号线) + RSI < 50
   bool is_sell_signal = (trade_direction == ORDER_TYPE_SELL &&
                          macd_main[1] < macd_signal[1] &&
                          macd_main[2] >= macd_signal[2] &&
                          rsi_values[1] < 50);

   if(is_buy_signal || is_sell_signal)
     {
      //--- 第五步: 计算止损止盈并执行交易
      double price = SymbolInfoDouble(trade_symbol, is_buy_signal ? SYMBOL_ASK : SYMBOL_BID);
      // 使用ATR计算止损和止盈距离
      double sl_dist = NormalizeDouble(atr_values[0] * InpSlMultiplier, (int)SymbolInfoInteger(trade_symbol, SYMBOL_DIGITS));
      double tp_dist = NormalizeDouble(atr_values[0] * InpTpMultiplier, (int)SymbolInfoInteger(trade_symbol, SYMBOL_DIGITS));
      double stop_loss = is_buy_signal ? price - sl_dist : price + sl_dist;
      double take_profit = is_buy_signal ? price + tp_dist : price - tp_dist;
      string comment = "Str:" + strongest_ccy + "/Wk:" + weakest_ccy;

      //--- 执行开仓
      if(!trade.PositionOpen(trade_symbol, trade_direction, InpLots, price, stop_loss, take_profit, comment))
        {
         // 如果开仓失败, 打印错误信息
         Print("开仓失败。错误代码: ", trade.ResultRetcode(), " - ", trade.ResultComment());
        }
      else
        {
         // 如果开仓成功, 打印订单号
         Print("为 ", trade_symbol, " 开仓成功。订单号: ", trade.ResultDeal());
        }
     }
  }

//+------------------------------------------------------------------+
//| 辅助函数: 根据两个货币名称, 找到有效的交易品种名称               |
//+------------------------------------------------------------------+
string GetSymbolName(string ccy1, string ccy2)
  {
   // 尝试 ccy1+ccy2, 例如 "EUR"+"USD" -> "EURUSD"
   string symbol_name = ccy1 + ccy2;
   if(SymbolExist(symbol_name, false))
     {
      if(SymbolSelect(symbol_name, true))
        {
         return(symbol_name);
        }
     }
   // 尝试 ccy2+ccy1, 例如 "USD"+"JPY" -> "USDJPY"
   symbol_name = ccy2 + ccy1;
   if(SymbolExist(symbol_name, false))
     {
      if(SymbolSelect(symbol_name, true))
        {
         return(symbol_name);
        }
     }
   return ""; // 如果都找不到, 返回空字符串
  }

//+------------------------------------------------------------------+
//| 核心函数: 计算所有货币的强度                                     |
//+------------------------------------------------------------------+
void CalculateCurrencyStrength(CurrencyStrength &strength_data[])
  {
   ArrayResize(strength_data, ArraySize(g_currencies));
   for(int i = 0; i < ArraySize(g_currencies); i++)
     {
      strength_data[i].name = g_currencies[i];
      strength_data[i].strength = 0.0;
     }

   for(int i = 0; i < ArraySize(g_currencies); i++)
     {
      int pairs_counted = 0;
      for(int j = 0; j < ArraySize(g_currencies); j++)
        {
         if(i == j) continue;
         string symbol = GetSymbolName(g_currencies[i], g_currencies[j]);
         if(symbol == "" || Bars(symbol, _Period) < InpStrengthPeriod + 2) continue;

         // 为保证回测准确性, 仅使用已收盘的K线数据
         double p_now_arr[1];   // 上一根收盘价
         double p_then_arr[1];  // N根前的收盘价
         if(CopyClose(symbol, _Period, 1, 1, p_now_arr) != 1 ||
            CopyClose(symbol, _Period, 1 + InpStrengthPeriod, 1, p_then_arr) != 1)
           {
            continue;
           }

         double p_now = p_now_arr[0];
         double p_then = p_then_arr[0];

         if(p_then == 0) continue;

         // 计算价格变化率
         double change = (p_now - p_then) / p_then;
         // 如果当前计算的货币是基础货币(例如EURUSD中的EUR), 则变化率直接计入强度
         if(StringFind(symbol, g_currencies[i], 0) == 0)
           {
            strength_data[i].strength += change;
           }
         // 如果是报价货币(例如USDJPY中的JPY), 则变化率反向计入强度
         else
           {
            strength_data[i].strength -= change;
           }
         pairs_counted++;
        }
      // 求所有配对变化率的平均值, 作为最终强度
      if(pairs_counted > 0)
        {
         strength_data[i].strength /= pairs_counted;
        }
     }
  }

//+------------------------------------------------------------------+
//| 辅助函数: 对货币强度数组进行排序 (从强到弱)                      |
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
            temp = str_arr[i];
            str_arr[i] = str_arr[j];
            str_arr[j] = temp;
           }
        }
     }
  }
//+------------------------------------------------------------------+
