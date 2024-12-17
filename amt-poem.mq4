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
#include "../Include/Constants.mqh"
#include "../Include/Structures.mqh"
#include "../Include/SymbolInfo.mqh"
#include "../Include/TradeManager.mqh"
#include "../Include/RiskManager.mqh"
#include "../Include/SessionManager.mqh"
#include "../Include/Logger.mqh"

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
datetime g_lastSignalTimestamp = 0;

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

    // Monitor positions (includes trailing stops and profit protection)
        if(ENABLE_PROFIT_PROTECTION) {
            static datetime lastCheck = 0;
            if(TimeCurrent() - lastCheck >= 60) {
                g_tradeManager.MonitorPositions();
                lastCheck = TimeCurrent();
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
            // Set instrument type based on symbol
            signal.instrumentType = g_symbolInfo.IsCryptoPair() ?
                INSTRUMENT_CRYPTO : INSTRUMENT_FOREX;

            ExecuteSignal(signal);
        }
    }
}

void CloseAllPositions(string reason) {
    for(int i = OrdersTotal() - 1; i >= 0; i--) {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
            if(OrderSymbol() == Symbol()) {
                g_tradeManager.ClosePosition(OrderTicket(), reason);
            }
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
    // Compare datetime values instead of strings
        if(signal.timestamp == g_lastSignalTimestamp || signal.timestamp == 0) {
            Logger.Debug("Duplicate or invalid signal timestamp - skipping");
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

    // Use appropriate risk percentage from Constants
    double riskPercent = g_symbolInfo.IsCryptoPair() ?
        CRYPTO_STOP_PERCENT : DEFAULT_RISK_PERCENT;
    g_riskManager.SetRiskPercent(riskPercent);

    double lots = g_riskManager.CalculatePositionSize(signal.price, stopLoss);

    if(lots <= 0) {
        Logger.Error("Invalid position size calculated");
        return;
    }

    // Execute trade with reversed position handling
    bool success = false;
    if(signal.signal == SIGNAL_BUY) {
        success = g_tradeManager.OpenBuyPosition(lots, stopLoss, 0, signal.pattern);
    } else if(signal.signal == SIGNAL_SELL) {
        success = g_tradeManager.OpenSellPosition(lots, stopLoss, 0, signal.pattern);
    }

    if(success) {
        g_lastSignalTimestamp = signal.timestamp;
        Logger.Trade(StringFormat(
            "Position transition executed:" +
            "\nDirection: %s" +
            "\nLots: %.2f" +
            "\nEntry: %.5f" +
            "\nStop Loss: %.5f" +
            "\nPattern: %s",
            signal.signal == SIGNAL_BUY ? "BUY" : "SELL",
            lots,
            signal.price,
            stopLoss,
            signal.pattern
        ));
    } else {
        Logger.Error("Failed to execute position transition");
    }
}

//+------------------------------------------------------------------+
//| Fetch signals from API                                             |
//+------------------------------------------------------------------+
string FetchSignals() {
    string url = StringFormat("%s?timeframe=%s&symbol=%s",
                            API_URL,
                            TIMEFRAME,
                            Symbol());

    string headers = "Content-Type: application/json\r\n";
    char post[];
    char result[];
    string resultHeaders;

    // Send API request
    ResetLastError();
    int res = WebRequest(
        "GET",
        url,
        headers,
        API_TIMEOUT,
        post,
        result,
        resultHeaders
    );

    if(res == -1) {
        int error = GetLastError();
        if(error == 4060) {
            Logger.Error("Add URL to: Tools -> Options -> Expert Advisors -> Allow WebRequest");
            Logger.Error("URL to allow: " + url);
        } else {
            Logger.Error(StringFormat("Failed to fetch signals. Error: %d", error));
        }
        return "";
    }

    string response = CharArrayToString(result);
    if(StringLen(response) == 0) {
        Logger.Debug("No signals received");
        return "";
    }

    return response;
}

//+------------------------------------------------------------------+
//| Parse signal from API response                                     |
//+------------------------------------------------------------------+
bool ParseSignal(string response, SignalData &signal) {
    if(response == "") return false;

    Logger.Debug("Starting to parse response: " + response);

    // Remove array brackets and get first signal
    string signalStr = response;
    if(StringGetCharacter(response, 0) == '[') {
        int firstClosingBrace = StringFind(response, "},");
        if(firstClosingBrace == -1) {
            Logger.Error("Could not find end of first signal object");
            return false;
        }
        signalStr = StringSubstr(response, 1, firstClosingBrace + 1);
        Logger.Debug("Extracted first signal: " + signalStr);
    }

    bool parseSuccess = false;
    string ticker = "";
    string action = "";
    double price = 0;
    string timestamp = "";
    string pattern = "";

    // Parse ticker (symbol)
    if(StringFind(signalStr, "\"ticker\":\"") >= 0) {
        int start = StringFind(signalStr, "\"ticker\":\"") + 9;
        int end = StringFind(signalStr, "\"", start);
        ticker = StringSubstr(signalStr, start, end - start);
        Logger.Debug("Parsed ticker: " + ticker);
    }

    // Parse action (signal)
    if(StringFind(signalStr, "\"action\":\"") >= 0) {
        int start = StringFind(signalStr, "\"action\":\"") + 9;
        int end = StringFind(signalStr, "\"", start);
        action = StringSubstr(signalStr, start, end - start);
        Logger.Debug("Parsed action: " + action);
    }

    // Parse price
    if(StringFind(signalStr, "\"price\":") >= 0) {
        int start = StringFind(signalStr, "\"price\":") + 8;
        int end = StringFind(signalStr, ",", start);
        string priceStr = StringSubstr(signalStr, start, end - start);
        price = StringToDouble(priceStr);
        Logger.Debug(StringFormat("Parsed price: %.5f", price));
    }

    // Parse timestamp
    if(StringFind(signalStr, "\"timestamp\":\"") >= 0) {
        int start = StringFind(signalStr, "\"timestamp\":\"") + 12;
        int end = StringFind(signalStr, "\"", start);
        string timestampStr = StringSubstr(signalStr, start, end - start);
        Logger.Debug("Raw timestamp: " + timestampStr);

        // Parse MM/DD/YYYY HH:MM:SS PM format
        int month = (int)StringToInteger(StringSubstr(timestampStr, 0, 2));
        int day = (int)StringToInteger(StringSubstr(timestampStr, 3, 2));
        int year = (int)StringToInteger(StringSubstr(timestampStr, 6, 4));
        int hour = (int)StringToInteger(StringSubstr(timestampStr, 11, 2));
        int minute = (int)StringToInteger(StringSubstr(timestampStr, 14, 2));

        // Adjust for PM
        if(StringFind(timestampStr, "PM") >= 0 && hour < 12) hour += 12;
        if(StringFind(timestampStr, "AM") >= 0 && hour == 12) hour = 0;

        signal.timestamp = StringToTime(StringFormat("%04d.%02d.%02d %02d:%02d:00",
                                                   year, month, day, hour, minute));
        Logger.Debug("Parsed timestamp: " + TimeToString(signal.timestamp));
    }

    // Parse pattern (signalPattern)
    if(StringFind(signalStr, "\"signalPattern\":\"") >= 0) {
        int start = StringFind(signalStr, "\"signalPattern\":\"") + 16;
        int end = StringFind(signalStr, "\"", start);
        pattern = StringSubstr(signalStr, start, end - start);
        Logger.Debug("Parsed pattern: " + pattern);
    }

    // Validate parsed data
    if(ticker != "" && action != "" && price > 0 && signal.timestamp > 0) {
        signal.ticker = ticker;
        signal.signal = action == "BUY" ? SIGNAL_BUY :
                       action == "SELL" ? SIGNAL_SELL : SIGNAL_NEUTRAL;
        signal.price = price;
        signal.pattern = pattern;
        parseSuccess = true;

        Logger.Info(StringFormat(
            "Successfully parsed signal: Symbol=%s, Action=%s, Price=%.5f, Pattern=%s, Timestamp=%s",
            signal.ticker, action, signal.price, signal.pattern,
            TimeToString(signal.timestamp)
        ));
    } else {
        Logger.Error(StringFormat(
            "Validation failed: Ticker=%s, Action=%s, Price=%.5f, Timestamp=%s",
            ticker, action, price, TimeToString(signal.timestamp)
        ));
    }

    return parseSuccess;
}

//+------------------------------------------------------------------+
//| Check and apply profit protection                                  |
//+------------------------------------------------------------------+
void CheckProfitProtection(const PositionMetrics &metrics) {
    if(metrics.totalPositions == 0) return;

    for(int i = OrdersTotal() - 1; i >= 0; i--) {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
            if(OrderSymbol() == Symbol()) {
                double currentPrice = OrderType() == OP_BUY ?
                                    g_symbolInfo.GetBid() : g_symbolInfo.GetAsk();
                double openPrice = OrderOpenPrice();
                double stopLoss = OrderStopLoss();

                // Calculate profit thresholds
                double profitThreshold;
                double lockProfit;

                if(g_symbolInfo.IsCryptoPair()) {
                    profitThreshold = openPrice * (CRYPTO_PROFIT_THRESHOLD / 100.0);
                    lockProfit = openPrice * (CRYPTO_PROFIT_LOCK_PERCENT / 100.0);
                } else {
                    profitThreshold = FOREX_PROFIT_PIPS_THRESHOLD * g_symbolInfo.GetPipSize();
                    lockProfit = FOREX_PROFIT_LOCK_PIPS * g_symbolInfo.GetPipSize();
                }

                // Check if profit exceeds threshold
                if(OrderType() == OP_BUY) {
                    if((currentPrice - openPrice) >= profitThreshold) {
                        double newStop = currentPrice - lockProfit;
                        if(stopLoss == 0 || newStop > stopLoss) {
                            g_tradeManager.ModifyPosition(OrderTicket(), newStop);
                        }
                    }
                } else {
                    if((openPrice - currentPrice) >= profitThreshold) {
                        double newStop = currentPrice + lockProfit;
                        if(stopLoss == 0 || newStop < stopLoss) {
                            g_tradeManager.ModifyPosition(OrderTicket(), newStop);
                        }
                    }
                }
            }
        }
    }
}

