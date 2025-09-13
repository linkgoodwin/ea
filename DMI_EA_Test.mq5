//+------------------------------------------------------------------+
//|                                                   DMI_EA_Test.mq5 |
//|                                  Copyright 2025, Trading Systems |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Trading Systems"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property script_show_inputs

//--- Test script for DMI Bitcoin EA functions
input int TestDMIPeriod = 14;

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
    Print("=== DMI Bitcoin EA Test Script ===");
    
    // Test ADX interval calculations
    TestADXIntervals();
    
    // Test lot size calculations  
    TestLotSizeCalculations();
    
    // Test DMI indicator initialization
    TestDMIIndicator();
    
    Print("=== Test Completed ===");
}

//+------------------------------------------------------------------+
//| Test ADX interval calculations                                   |
//+------------------------------------------------------------------+
void TestADXIntervals()
{
    Print("Testing ADX Interval Calculations:");
    
    // Test values
    double test_adx_values[] = {5.5, 15.2, 25.8, 35.1, 45.7, 55.3, 65.9, 75.4, 85.0, 95.6, 100.0};
    
    for(int i = 0; i < ArraySize(test_adx_values); i++) {
        int interval = GetADXInterval(test_adx_values[i]);
        double lot_size = GetBaseLotSize(interval);
        
        Print("ADX: ", DoubleToString(test_adx_values[i], 1), 
              " -> Interval: ", interval, 
              " -> Lot Size: ", DoubleToString(lot_size, 2));
    }
}

//+------------------------------------------------------------------+
//| Test lot size calculations                                       |
//+------------------------------------------------------------------+
void TestLotSizeCalculations()
{
    Print("\nTesting Lot Size Calculations:");
    
    double multipliers[] = {0.5, 1.0, 1.5, 2.0};
    
    for(int m = 0; m < ArraySize(multipliers); m++) {
        Print("Multiplier: ", DoubleToString(multipliers[m], 1));
        
        for(int i = 0; i < 10; i++) {
            double base_lot = GetBaseLotSize(i);
            double final_lot = base_lot * multipliers[m];
            
            Print("  Interval ", i, ": Base=", DoubleToString(base_lot, 2), 
                  " Final=", DoubleToString(final_lot, 2));
        }
    }
}

//+------------------------------------------------------------------+
//| Test DMI indicator initialization                                |
//+------------------------------------------------------------------+
void TestDMIIndicator()
{
    Print("\nTesting DMI Indicator:");
    
    int dmi_handle = iADX(Symbol(), PERIOD_M15, TestDMIPeriod);
    
    if(dmi_handle == INVALID_HANDLE) {
        Print("ERROR: Failed to create DMI indicator handle");
        return;
    }
    
    Print("DMI indicator handle created successfully: ", dmi_handle);
    
    // Test copying values
    double plus_di[], minus_di[], adx[];
    ArraySetAsSeries(plus_di, true);
    ArraySetAsSeries(minus_di, true);
    ArraySetAsSeries(adx, true);
    
    if(CopyBuffer(dmi_handle, 0, 0, 5, plus_di) > 0 &&
       CopyBuffer(dmi_handle, 1, 0, 5, minus_di) > 0 &&
       CopyBuffer(dmi_handle, 2, 0, 5, adx) > 0) {
        
        Print("DMI values copied successfully:");
        for(int i = 0; i < 5; i++) {
            Print("Bar ", i, ": +DI=", DoubleToString(plus_di[i], 2),
                  " -DI=", DoubleToString(minus_di[i], 2),
                  " ADX=", DoubleToString(adx[i], 2));
        }
    } else {
        Print("ERROR: Failed to copy DMI values");
    }
    
    IndicatorRelease(dmi_handle);
}

//+------------------------------------------------------------------+
//| Get ADX interval for given ADX value                            |
//+------------------------------------------------------------------+
int GetADXInterval(double adx_value)
{
    double adx_intervals[10][2] = {
        {0, 10}, {10, 20}, {20, 30}, {30, 40}, {40, 50},
        {50, 60}, {60, 70}, {70, 80}, {80, 90}, {90, 100}
    };
    
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
//| Get base lot size for interval                                   |
//+------------------------------------------------------------------+
double GetBaseLotSize(int interval)
{
    double base_lot_sizes[10] = {0.10, 0.09, 0.08, 0.07, 0.06, 0.05, 0.04, 0.03, 0.02, 0.01};
    
    if(interval >= 0 && interval < 10) {
        return base_lot_sizes[interval];
    }
    
    return 0.01; // Default minimum
}

//+------------------------------------------------------------------+