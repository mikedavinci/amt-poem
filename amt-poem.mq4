//+------------------------------------------------------------------+
//|                                                  TradeJourney.mq4   |
//|                                                      TradeJourney  |
//|                                          https://tradejourney.ai   |
//+------------------------------------------------------------------+
#property copyright "TradeJourney"
#property link      "https://tradejourney.ai"
#property version   "1.00"
#property strict

// Include all modules
#include "includes/Constants.mqh"
#include "includes/Structures.mqh"
#include "includes/SymbolInfo.mqh"
#include "includes/TradeManager.mqh"
#include "includes/RiskManager.mqh"
#include "includes/SessionManager.mqh"
#include "includes/Logger.mqh"

// External Parameters
// API Configuration
extern string API_URL = "https://api.tradejourney.ai/api/alerts/mt4-forex-signals";  // API URL
extern string PAPERTRAIL_HOST = "https://api.tradejourney.ai/api/alerts/log";        // Logging endpoint
extern string SYSTEM_NAME = "EA-TradeJourney";                                       // System identifier
extern string TIMEFRAME = "60";                                                      // Timeframe parameter

// Risk Management
extern double RISK_PERCENT = 1.0;                    // Risk percentage per trade
extern double MARGIN_BUFFER = 50.0;                  // Margin buffer percentage
extern bool ENABLE_PROFIT_PROTECTION = true;         // Enable profit protection
extern double MAX_ACCOUNT_RISK = 3.0;               // Maximum total account risk

// Session Settings
extern bool TRADE_ASIAN_SESSION = true;             // Trade during Asian session
extern bool TRADE_LONDON_SESSION = true;            // Trade during London session
extern bool TRADE_NEWYORK_SESSION = true;           // Trade during NY session
extern bool ALLOW_SESSION_OVERLAP = true;           // Allow session overlap trading

// Debug Settings
extern bool DEBUG_MODE = true;                      // Enable debug logging
extern bool ENABLE_PAPERTRAIL = true;               // Enable external logging

// Global Variables
CSymbolInfo* g_symbolInfo = NULL;
CTradeManager* g_tradeManager = NULL;
CRiskManager* g_riskManager = NULL;
CSessionManager* g_sessionManager = NULL;
datetime g_lastCheck = 0;
string g_lastSignalTimestamp = "";

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit() {
    // Initialize logger first
    Logger.EnableDebugMode(DEBUG_MODE);
    Logger.EnablePapertrail(ENABLE_PAPERTRAIL);
    Logger.SetSystemName(SYSTEM_NAME);
    Logger.SetPapertrailHost(PAPERTRAIL_HOST);
    
    // Log initialization start
    Logger.Info(StringFormat("Initializing %s EA...", SYSTEM_NAME));
    
    // Initialize symbol info
    g_symbolInfo = new CSymbolInfo(_Symbol);
    if(g_symbolInfo == NULL) {
        Logger.Error("Failed to initialize SymbolInfo");
        return INIT_FAILED;
    }
    
    // Initialize managers
    g_tradeManager = new CTradeManager(g_symbolInfo);
    if(g_tradeManager == NULL) {
        Logger.Error("Failed to initialize TradeManager");
        return INIT_FAILED;
    }
    
    g_riskManager = new CRiskManager(g_symbolInfo, RISK_PERCENT, MAX_ACCOUNT_RISK, MARGIN_BUFFER);
    if(g_riskManager == NULL) {
        Logger.Error("Failed to initialize RiskManager");
        return INIT_FAILED;
    }
    
    g_sessionManager = new CSessionManager(g_symbolInfo, 
                                         TRADE_ASIAN_SESSION,
                                         TRADE_LONDON_SESSION,
                                         TRADE_NEWYORK_SESSION,
                                         ALLOW_SESSION_OVERLAP);
    if(g_sessionManager == NULL) {
        Logger.Error("Failed to initialize SessionManager");
        return INIT_FAILED;
    }
    
    // Log initialization parameters
    Logger.Info(StringFormat(
        "EA Initialized with:" +
        "\nRisk: %.2f%%" +
        "\nMargin Buffer: %.2f%%" +
        "\nMax Account Risk: %.2f%%" +
        "\nProfit Protection: %s",
        RISK_PERCENT,
        MARGIN_BUFFER,
        MAX_ACCOUNT_RISK,
        ENABLE_PROFIT_PROTECTION ? "Enabled" : "Disabled"
    ));
    
    // Log account information
    Logger.Info(StringFormat(
        "Account Status:" +
        "\nBalance: %.2f" +
        "\nEquity: %.2f" +
        "\nMargin Level: %.2f%%",
        AccountBalance(),
        AccountEquity(),
        AccountMargin() > 0 ? (AccountEquity() / AccountMargin() * 100) : 0
    ));
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    // Clean up allocated resources
    if(g_symbolInfo != NULL) {
        delete g_symbolInfo;
        g_symbolInfo = NULL;
    }
    
    if(g_tradeManager != NULL) {
        delete g_tradeManager;
        g_tradeManager = NULL;
    }
    
    if(g_riskManager != NULL) {
        delete g_riskManager;
        g_riskManager = NULL;
    }
    
    if(g_sessionManager != NULL) {
        delete g_sessionManager;
        g_sessionManager = NULL;
    }
    
    Logger.Info(StringFormat("EA Deinitialized. Reason: %d", reason));
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick() {
    // Skip if managers aren't initialized
    if(g_symbolInfo == NULL || g_tradeManager == NULL || 
       g_riskManager == NULL || g_sessionManager == NULL) {
        return;
    }
    
    // Check if trading is allowed
    if(!g_tradeManager.CanTrade()) {
        static datetime lastWarning = 0;
        if(TimeCurrent() - lastWarning >= 300) {  // Log every 5 minutes
            Logger.Warning("Trading not currently allowed");
            lastWarning = TimeCurrent();
        }
        return;
    }
    
    // Check market session
    if(!g_sessionManager.IsMarketOpen()) {
        return;
    }
    
    // Perform periodic checks
    PerformPeriodicChecks();
    
    // Check for new signals
    if(IsTimeToCheck()) {
        ProcessSignals();
    }
    
    // Monitor open positions
    if(ENABLE_PROFIT_PROTECTION) {
        static datetime lastProtectionCheck = 0;
        if(TimeCurrent() - lastProtectionCheck >= 60) {  // Check every minute
            MonitorPositions();
            lastProtectionCheck = TimeCurrent();
        }
    }
}

//+------------------------------------------------------------------+
//| Periodic monitoring and maintenance                               |
//+------------------------------------------------------------------+
void PerformPeriodicChecks() {
    static datetime lastCheck = 0;
    datetime currentTime = TimeCurrent();
    
    // Run checks every 5 minutes
    if(currentTime - lastCheck >= 300) {
        // Check account status
        if(!g_riskManager.IsMarginSafe()) {
            Logger.Warning("Margin level below safe threshold");
        }
        
        // Log current market conditions
        string liquidity = g_sessionManager.GetLiquidityLevel();
        Logger.Debug(StringFormat(
            "Market Conditions:" +
            "\nLiquidity: %s" +
            "\nSpread: %.5f",
            liquidity,
            g_symbolInfo.GetSpread()
        ));
        
        lastCheck = currentTime;
    }
}

//+------------------------------------------------------------------+
//| Signal processing                                                 |
//+------------------------------------------------------------------+
bool IsTimeToCheck() {
    static datetime lastSignalCheck = 0;
    datetime currentTime = TimeCurrent();
    
    if(currentTime - lastSignalCheck < 60) {  // Check every minute
        return false;
    }
    
    lastSignalCheck = currentTime;
    return true;
}

void ProcessSignals() {
    string response = FetchSignals();
    if(response == "") return;
    
    SignalData signal;
    if(ParseSignal(response, signal)) {
        if(ValidateSignal(signal)) {
            ExecuteSignal(signal);
        }
    }
}

//+------------------------------------------------------------------+
//| Position monitoring                                               |
//+------------------------------------------------------------------+
void MonitorPositions() {
    PositionMetrics metrics = g_tradeManager.GetPositionMetrics();
    
    if(metrics.totalPositions > 0) {
        // Check profit protection
        if(ENABLE_PROFIT_PROTECTION) {
            CheckProfitProtection(metrics);
        }
        
        // Log position status
        Logger.Debug(StringFormat(
            "Position Status:" +
            "\nTotal Positions: %d" +
            "\nTotal Volume: %.2f" +
            "\nUnrealized P/L: %.2f",
            metrics.totalPositions,
            metrics.totalVolume,
            metrics.unrealizedPL
        ));
    }
}

//+------------------------------------------------------------------+
//| Signal validation and execution                                   |
//+------------------------------------------------------------------+
bool ValidateSignal(const SignalData& signal) {
    // Validate signal timestamp
    if(signal.timestamp == g_lastSignalTimestamp) {
        Logger.Debug("Duplicate signal - skipping");
        return false;
    }
    
    // Validate price
    if(signal.price <= 0) {
        Logger.Error("Invalid signal price");
        return false;
    }
    
    // Additional validations as needed
    return true;
}

void ExecuteSignal(const SignalData& signal) {
    // Calculate position size and stop loss
    double stopLoss = g_symbolInfo.CalculateStopLoss(
        signal.signal == SIGNAL_BUY ? OP_BUY : OP_SELL,
        signal.price
    );
    
    double lots = g_riskManager.CalculatePositionSize(signal.price, stopLoss);
    
    if(lots <= 0) {
        Logger.Error("Invalid position size calculated");
        return;
    }
    
    // Execute trade
    bool success = false;
    if(signal.signal == SIGNAL_BUY) {
        success = g_tradeManager.OpenBuyPosition(lots, stopLoss, 0, signal.pattern);
    } else if(signal.signal == SIGNAL_SELL) {
        success = g_tradeManager.OpenSellPosition(lots, stopLoss, 0, signal.pattern);
    }
    
    if(success) {
        g_lastSignalTimestamp = signal.timestamp;
        Logger.Trade(StringFormat(
            "Position opened:" +
            "\nDirection: %s" +
            "\nLots: %.2f" +
            "\nEntry: %.5f" +
            "\nStop Loss: %.5f",
            signal.signal == SIGNAL_BUY ? "BUY" : "SELL",
            lots,
            signal.price,
            stopLoss
        ));
    }
}