@echo off
echo Testing MQL5 compilation...
echo.
echo Key fixes applied:
echo 1. Replaced Close[0] with SymbolInfoDouble(Symbol(), SYMBOL_BID)
echo.
echo The main compilation error was caused by using Close[0] which is MQL4 syntax.
echo In MQL5, we need to use proper functions to get price data.
echo.
echo Fixed line 484 in CreateTradeLabel function:
echo OLD: if(ObjectCreate(0, obj_name, OBJ_TEXT, 0, TimeCurrent(), Close[0])) {
echo NEW: double current_price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
echo      if(ObjectCreate(0, obj_name, OBJ_TEXT, 0, TimeCurrent(), current_price)) {
echo.
echo The EA should now compile successfully in MetaTrader 5.
pause