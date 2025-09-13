# DMI Bitcoin Trading Expert Advisor (MQL5)

## Overview
This Expert Advisor implements a sophisticated Bitcoin trading strategy based on the Directional Movement Index (DMI) indicator. The EA uses ADX-based dynamic lot sizing and comprehensive risk management features specifically optimized for Bitcoin (BTCUSD) trading.

## Key Features

### 1. Trading Logic
- **Primary Signal**: DMI indicator (+DI, -DI, ADX crossovers)
- **Buy Signal**: +DI crosses above -DI (closes existing short positions first)
- **Sell Signal**: -DI crosses above +DI (closes existing long positions first)
- **Position Limit**: Only one position (long or short) allowed at a time
- **No Daily Trade Limits**: Every crossover triggers an entry signal

### 2. Dynamic Lot Sizing System
The EA divides the ADX range (0-100) into 10 equal intervals:

| ADX Range | Interval | Base Lot Size |
|-----------|----------|---------------|
| 90-100    | 9        | 0.01         |
| 80-90     | 8        | 0.02         |
| 70-80     | 7        | 0.03         |
| 60-70     | 6        | 0.04         |
| 50-60     | 5        | 0.05         |
| 40-50     | 4        | 0.06         |
| 30-40     | 3        | 0.07         |
| 20-30     | 2        | 0.08         |
| 10-20     | 1        | 0.09         |
| 0-10      | 0        | 0.10         |

**Logic**: Higher ADX (stronger trend) = smaller position size (more conservative)

### 3. Position Management
- **Position Reduction**: Reduce by 0.01 lots for each ADX interval rise above entry level
- **Stop-Loss Trigger**: Close entire position when ADX falls N intervals (default: 2) below entry level
- **Automatic Closure**: Opposite signal automatically closes current position before opening new one

### 4. Risk Management
- **Risk per Trade**: Configurable (0.5%-5%, default: 2% of account balance)
- **Daily Stop-Loss Limit**: Configurable (1-10 times, default: 3)
- **Trading Pause**: Automatic pause after reaching daily stop-loss limit
- **Pause Duration**: Configurable (1-24 hours, default: 12 hours)

### 5. Visualization Features
- **Chart Labels**: Chinese text labels for entries/exits
  - 开多 (Long Entry)
  - 开空 (Short Entry)  
  - 平多 (Long Close)
  - 平空 (Short Close)
- **Information Panel**: Real-time trading statistics
- **DMI Indicator**: Visual display of +DI, -DI, and ADX lines

## Input Parameters

### DMI Settings
- **DMI Period**: 5-50 (default: 14)
- **Trading Timeframe**: M5, M15, M30, H1, H4 (default: M15)
- **Lot Multiplier**: 0.1-10.0 (default: 1.0) - Applied to all base lot sizes

### Risk Management
- **Risk Percent**: 0.5-5.0% (default: 2.0%)
- **Stop-Loss Intervals**: 1-5 (default: 2)
- **Daily Stop-Loss Limit**: 1-10 (default: 3)
- **Trading Pause Hours**: 1-24 (default: 12)

### Trading Direction
- **Allow Buy**: Enable/disable long trades (default: true)
- **Allow Sell**: Enable/disable short trades (default: true)

### Display Settings
- **Show Info Panel**: Enable/disable information panel (default: true)
- **Show Chart Labels**: Enable/disable entry/exit labels (default: true)
- **Panel Color**: Background color for info panel (default: Dark Blue)
- **Text Color**: Text color for info panel (default: White)

## Information Panel Display

The EA shows a comprehensive information panel with:

```
=== DMI Bitcoin EA ===
总利润: $1,234.56          // Total Profit
当前盈亏: $123.45          // Current P&L

今日交易: 5               // Daily Trades
今日止损: 1/3             // Daily Stop-losses / Limit

当前ADX: 45.2             // Current ADX Value
ADX区间: 4 (40-50)        // ADX Interval (Range)
对应手数: 0.06            // Corresponding Lot Size

持仓方向: 多头             // Position Direction (Long/Short/None)
持仓手数: 0.06            // Position Volume

交易正常                  // Trading Status
```

## Installation Instructions

1. **Copy the EA file** (`DMI_Bitcoin_EA.mq5`) to your MetaTrader 5 `MQL5/Experts/` folder
2. **Restart MetaTrader 5** or refresh the Navigator panel
3. **Drag and drop** the EA onto a Bitcoin (BTCUSD) chart
4. **Configure parameters** in the EA settings dialog
5. **Enable AutoTrading** in MetaTrader 5
6. **Allow DLL imports** if prompted (required for trade operations)

## Recommended Settings

### For Conservative Trading:
- DMI Period: 21
- Risk Percent: 1.0%
- Lot Multiplier: 0.5
- Stop-Loss Intervals: 1
- Daily Stop-Loss Limit: 2

### For Aggressive Trading:
- DMI Period: 14
- Risk Percent: 3.0%
- Lot Multiplier: 1.5
- Stop-Loss Intervals: 3
- Daily Stop-Loss Limit: 5

### For Testing:
- Start with default settings
- Use demo account first
- Monitor for at least one week
- Adjust parameters based on performance

## Important Notes

1. **Symbol Compatibility**: Optimized for Bitcoin (BTCUSD) pairs
2. **Timeframe Flexibility**: Works on any timeframe but M15 is recommended
3. **Account Requirements**: Minimum balance recommended: $1,000
4. **Server Connection**: Requires stable internet connection
5. **News Events**: Consider disabling during major Bitcoin news events

## Risk Warnings

- **Past performance does not guarantee future results**
- **Cryptocurrency trading involves high risk**
- **Never risk more than you can afford to lose**
- **Always test on demo account first**
- **Monitor the EA regularly and adjust parameters as needed**

## Troubleshooting

### Common Issues:
1. **EA not trading**: Check if AutoTrading is enabled
2. **Invalid lot size**: Verify broker's minimum lot size requirements
3. **Indicator not loading**: Ensure DMI period is valid (5-50)
4. **High drawdown**: Reduce risk percent or lot multiplier
5. **Frequent stop-losses**: Increase stop-loss intervals

### Error Messages:
- "Failed to create DMI indicator handle": Check symbol and timeframe
- "Invalid trade parameters": Verify lot sizes and symbol specifications
- "Daily stop-loss limit reached": EA automatically pauses trading
- "Server connectivity issues": Check internet connection and broker server

## Support and Updates

For questions, bug reports, or feature requests, please refer to the EA documentation or contact the developer. Regular updates may be provided to improve performance and add new features.

## Version History

- **v1.00**: Initial release with full DMI trading system, ADX-based lot sizing, comprehensive risk management, and Chinese visualization features.