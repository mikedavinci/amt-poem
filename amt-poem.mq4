//+------------------------------------------------------------------+
//|                                                   SignalReader.mq4  |
//|                                                                    |
//+------------------------------------------------------------------+
#property copyright "Miguel Esparza mikedavinci"
#property link "TradeJourney.ai"
#property version "1.00"
#property strict

//+------------------------------------------------------------------+
//| Constants & Definitions                                            |
//+------------------------------------------------------------------+
// Custom Error Codes (start at high number to avoid conflicts)
#define ERR_CUSTOM_START 65536
#define ERR_CUSTOM_ERROR (ERR_CUSTOM_START + 1)
#define ERR_CUSTOM_CRITICAL (ERR_CUSTOM_START + 2)

// Instrument Specifications
// Forex Pairs
#define FOREX_CONTRACT_SIZE 100000
#define FOREX_MARGIN_PERCENT 100.0
#define FOREX_DIGITS 5
#define FOREX_MARGIN_INITIAL 100000

// Crypto Pairs
#define CRYPTO_DIGITS 2

// BTC/ETH Specifications
#define CRYPTO_CONTRACT_SIZE_DEFAULT 1
#define CRYPTO_MARGIN_PERCENT_DEFAULT 0.003  // 0.3%

// LTC Specifications
#define CRYPTO_CONTRACT_SIZE_LTC 100
#define CRYPTO_MARGIN_PERCENT_LTC 0.01      // 1.0%

//+------------------------------------------------------------------+
//| Helper Functions                                                   |
//+------------------------------------------------------------------+
// Helper function to get contract size for any symbol
double GetContractSize(string symbol) {
    if(StringFind(symbol, "LTC") >= 0) return CRYPTO_CONTRACT_SIZE_LTC;
    if(StringFind(symbol, "BTC") >= 0 || StringFind(symbol, "ETH") >= 0) return CRYPTO_CONTRACT_SIZE_DEFAULT;
    return FOREX_CONTRACT_SIZE;  // Default for forex pairs
}

// Helper function to get margin percentage for any symbol
double GetMarginPercent(string symbol) {
    if(StringFind(symbol, "LTC") >= 0) return CRYPTO_MARGIN_PERCENT_LTC;
    if(StringFind(symbol, "BTC") >= 0 || StringFind(symbol, "ETH") >= 0) return CRYPTO_MARGIN_PERCENT_DEFAULT;
    return FOREX_MARGIN_PERCENT;  // Default for forex pairs
}

// Helper function to get digits for any symbol
int GetSymbolDigits(string symbol) {
    if(StringFind(symbol, "BTC") >= 0 || StringFind(symbol, "ETH") >= 0 || StringFind(symbol, "LTC") >= 0) 
        return CRYPTO_DIGITS;
    if(StringFind(symbol, "JPY") >= 0) 
        return 3;
    return FOREX_DIGITS;
}

//+------------------------------------------------------------------+
//| Data Structures                                                    |
//+------------------------------------------------------------------+
// Signal Data Structure
struct SignalData {
    string ticker;     // Trading symbol
    string action;     // BUY, SELL, or NEUTRAL
    double price;      // Signal price
    string timestamp;  // Signal timestamp
    string pattern;    // Trading pattern that generated the signal
};

// Add to global variables section
struct LastTradeInfo {
    string symbol;           // Trading symbol
    string action;          // "BUY" or "SELL"
    datetime closeTime;     // Time trade was closed
    double closePrice;      // Price at close
    string closeReason;     // "SL", "TP", "MANUAL", "EMERGENCY", "PROFIT_PROTECTION"
    double profitLoss;      // Final P/L including swap and commission
};

// Global variables
datetime lastCheck = 0;
string lastSignalTimestamp = "";
LastTradeInfo lastClosedTrades[];

// External parameters
extern string API_URL = "https://api.tradejourney.ai/api/alerts/mt4-forex-signals";  // API URL
extern int REFRESH_MINUTES = 60;                                                      // How often to check for new signals
extern bool DEBUG_MODE = true;                                                        // Print debug messages
extern string PAPERTRAIL_HOST = "https://api.tradejourney.ai/api/alerts/log";        // API endpoint for logs
extern string SYSTEM_NAME = "EA-TradeJourney";                                       // System identifier
extern bool ENABLE_PAPERTRAIL = true;                                                // Enable/disable Papertrail logging
extern bool ENABLE_PROFIT_PROTECTION = true;                                         // Enable/disable profit protection
extern int PROFIT_CHECK_INTERVAL = 300;                                               // How often to check profit protection (in seconds)
extern double FOREX_PROFIT_PIPS_THRESHOLD = 20;                                      // Minimum profit in pips before protection
extern double FOREX_PROFIT_LOCK_PIPS = 10;                                          // How many pips to keep as profit
extern double CRYPTO_PROFIT_THRESHOLD = 1.0;                                         // Minimum profit percentage before protection
extern double CRYPTO_PROFIT_LOCK_PERCENT = 0.5;                                     // Percentage of profit to protect
extern double FOREX_STOP_PIPS = 50;                                                 // Stop loss in pips for forex pairs
extern double CRYPTO_STOP_PERCENT = 2.0;                                            // Stop loss percentage for crypto pairs
extern double RISK_PERCENT = 1.0;                                                   // Risk percentage per trade
extern int MAX_POSITIONS = 1;                                                       // Maximum positions per symbol
extern int MAX_RETRIES = 3;                                                        // Maximum retries for failed trades
extern double FOREX_EMERGENCY_PIPS = 75;                                           // Emergency close level for forex (in pips)
extern int EMERGENCY_CLOSE_PERCENT = 3;                                            // Emergency close if loss exceeds this percentage
extern int MAX_SLIPPAGE = 5;                                                       // Maximum allowed slippage in points
extern int PRICE_DIGITS = 5;                                                       // Decimal places for price display (5 for forex, 3 for JPY pairs)
extern string TIMEFRAME = "60";                                                    // Timeframe parameter for API

extern bool TRADE_ASIAN_SESSION = true;                                            // Allow trading during Asian session
extern bool TRADE_LONDON_SESSION = true;                                          // Allow trading during London session
extern bool TRADE_NEWYORK_SESSION = true;                                         // Allow trading during New York session
extern bool ALLOW_SESSION_OVERLAP = true;                                         // Allow trading during session overlaps

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit() {
  // Add your symbol to MarketWatch if not already there
  SymbolSelect("EURUSD+", true);
  SymbolSelect("AUDUSD+", true);
  SymbolSelect("GBPUSD+", true);
  // SymbolSelect("USDJPY+", true);
  SymbolSelect("BTCUSD", true);
  SymbolSelect("ETHUSD", true);
  SymbolSelect("LTCUSD", true);

   
   LogInfo(StringFormat("EA Initialized with Risk: %.2f%%", RISK_PERCENT));
   LogInfo(StringFormat("Account Balance: %.2f", AccountBalance()));
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   LogInfo(StringFormat("EA Deinitialized. Reason: %d", reason));
}

//+------------------------------------------------------------------+
//| Helper function to escape JSON strings                             |
//+------------------------------------------------------------------+
string EscapeJsonString(string str) {
  string result = str;
  StringReplace(result, "\"", "\\\"");
  StringReplace(result, "\n", "\\n");
  StringReplace(result, "\r", "\\r");
  return result;
}

//+------------------------------------------------------------------+
//| Send Log to Papertrail                                            |
//+------------------------------------------------------------------+
void SendToPapertrail(string message, string level = "INFO", string symbol = "") {
    if (!ENABLE_PAPERTRAIL) {
        Print(StringFormat("Papertrail disabled - skipping log: %s", message));
        return;
    }
    
    // Convert MT4 log level to API level
    string apiLevel;
    if (level == "ERROR") apiLevel = "error";
    else if (level == "WARNING") apiLevel = "warn";
    else apiLevel = "info";
    
    // Format timestamp in ISO 8601 format
    datetime currentTime = TimeCurrent();
    string isoTimestamp = StringFormat(
        "%d-%02d-%02dT%02d:%02d:%02dZ",
        TimeYear(currentTime),
        TimeMonth(currentTime),
        TimeDay(currentTime),
        TimeHour(currentTime),
        TimeMinute(currentTime),
        TimeSeconds(currentTime)
    );
    
    // Ensure symbol is not empty
    if(symbol == "") symbol = Symbol();
    
    // Build metadata object with enhanced information
    string metadata = StringFormat(
        "{\"system\":\"%s\",\"timestamp\":\"%s\",\"level\":\"%s\",\"account\":%d,\"symbol\":\"%s\",\"timeframe\":\"%s\"}",
        SYSTEM_NAME,
        isoTimestamp,
        level,
        AccountNumber(),
        symbol,
        TIMEFRAME
    );
    
    // Build the complete payload
    string payload = StringFormat(
        "{\"message\":\"%s\",\"level\":\"%s\",\"metadata\":%s}",
        EscapeJsonString(message),
        apiLevel,
        metadata
    );
    
    string headers = "Content-Type: application/json\r\n";
    char post[];
    ArrayResize(post, StringLen(payload));
    StringToCharArray(payload, post, 0, StringLen(payload));
    
    char result[];
    string resultHeaders;
    
    ResetLastError();
    int res = WebRequest(
        "POST",
        PAPERTRAIL_HOST,
        headers,
        5000,
        post,
        result,
        resultHeaders
    );
    
    if(res == -1) {
        int error = GetLastError();
        if(error == 4060) {
            Print("ERROR: Enable WebRequest for URL: ", PAPERTRAIL_HOST);
            Print("Add URL to MetaTrader -> Tools -> Options -> Expert Advisors -> Allow WebRequest");
            return;
        }
        Print(StringFormat("Failed to send log. Error: %d - %s", error, ErrorDescription(error)));
    } else {
        string response = CharArrayToString(result, 0, ArraySize(result));
        if(DEBUG_MODE) Print(StringFormat("Log sent successfully. Response: %s", response));
    }
}

//+------------------------------------------------------------------+
//| Enhanced Debug Print Function with Papertrail Integration          |
//+------------------------------------------------------------------+
void PrintDebug(string message, string level = "INFO", string symbol = "") {
    string formattedMessage = TimeToString(TimeCurrent()) + " | " + 
                         (symbol == "" ? Symbol() : symbol) + " | " + message;
    
    SendToPapertrail(message, level, symbol);
    
    if(DEBUG_MODE) {
        Print(formattedMessage);
    }
}

//+------------------------------------------------------------------+
//| Record details of closed trade                                     |
//+------------------------------------------------------------------+
void RecordClosedTrade(string symbol, string action, 
                      double closePrice, string closeReason = "", 
                      double profitLoss = 0) {
    int size = ArraySize(lastClosedTrades);
    bool found = false;
    
    // First, try to update existing record
    for(int i = 0; i < size; i++) {
        if(lastClosedTrades[i].symbol == symbol) {
            // Update existing record
            lastClosedTrades[i].action = action;
            lastClosedTrades[i].closeTime = TimeCurrent();
            lastClosedTrades[i].closePrice = closePrice;
            lastClosedTrades[i].closeReason = closeReason;
            lastClosedTrades[i].profitLoss = profitLoss;
            found = true;
            
            LogDebug(StringFormat(
                "Updated trade record for %s:" +
                "\nAction: %s" +
                "\nClose Price: %.5f" +
                "\nClose Reason: %s" +
                "\nP/L: %.2f" +
                "\nTime: %s",
                symbol,
                action,
                closePrice,
                closeReason,
                profitLoss,
                TimeToString(lastClosedTrades[i].closeTime)
            ));
            break;
        }
    }
    
    // If not found, add new record
    if(!found) {
        ArrayResize(lastClosedTrades, size + 1);
        lastClosedTrades[size].symbol = symbol;
        lastClosedTrades[size].action = action;
        lastClosedTrades[size].closeTime = TimeCurrent();
        lastClosedTrades[size].closePrice = closePrice;
        lastClosedTrades[size].closeReason = closeReason;
        lastClosedTrades[size].profitLoss = profitLoss;
        
        LogDebug(StringFormat(
            "Created new trade record for %s:" +
            "\nAction: %s" +
            "\nClose Price: %.5f" +
            "\nClose Reason: %s" +
            "\nP/L: %.2f" +
            "\nTime: %s",
            symbol,
            action,
            closePrice,
            closeReason,
            profitLoss,
            TimeToString(lastClosedTrades[size].closeTime)
        ));
    }
    
    // Log complete trade history for symbol
    LogTradeHistory(symbol);
}

//+------------------------------------------------------------------+
//| Check if new trade is allowed based on last trade direction       |
//+------------------------------------------------------------------+
bool IsNewTradeAllowed(string symbol, string newAction) {
    // Find last trade record for this symbol
    for(int i = 0; i < ArraySize(lastClosedTrades); i++) {
        if(lastClosedTrades[i].symbol == symbol) {
            // Get time since last trade
            datetime currentTime = TimeCurrent();
            int minutesSinceLastTrade = 
                (int)((currentTime - lastClosedTrades[i].closeTime) / 60);
            
            // If last trade was BUY, only allow SELL and vice versa
            if(lastClosedTrades[i].action == "BUY" && newAction == "BUY") {
                LogDebug(StringFormat(
                    "Trade blocked for %s:" +
                    "\nWaiting for SELL signal after previous BUY" +
                    "\nLast Trade Time: %s (%d minutes ago)" +
                    "\nClose Price: %.5f" +
                    "\nClose Reason: %s" +
                    "\nP/L: %.2f",
                    symbol,
                    TimeToString(lastClosedTrades[i].closeTime),
                    minutesSinceLastTrade,
                    lastClosedTrades[i].closePrice,
                    lastClosedTrades[i].closeReason,
                    lastClosedTrades[i].profitLoss
                ));
                return false;
            }
            if(lastClosedTrades[i].action == "SELL" && newAction == "SELL") {
                LogDebug(StringFormat(
                    "Trade blocked for %s:" +
                    "\nWaiting for BUY signal after previous SELL" +
                    "\nLast Trade Time: %s (%d minutes ago)" +
                    "\nClose Price: %.5f" +
                    "\nClose Reason: %s" +
                    "\nP/L: %.2f",
                    symbol,
                    TimeToString(lastClosedTrades[i].closeTime),
                    minutesSinceLastTrade,
                    lastClosedTrades[i].closePrice,
                    lastClosedTrades[i].closeReason,
                    lastClosedTrades[i].profitLoss
                ));
                return false;
            }
            
            // Log allowed trade
            LogDebug(StringFormat(
                "New trade allowed for %s:" +
                "\nPrevious: %s" +
                "\nNew Action: %s" +
                "\nTime Since Last: %d minutes",
                symbol,
                lastClosedTrades[i].action,
                newAction,
                minutesSinceLastTrade
            ));
            return true;
        }
    }
    
    // If no previous trade found, allow the trade
    LogDebug(StringFormat(
        "No previous trade found for %s - allowing %s",
        symbol,
        newAction
    ));
    return true;
}

//+------------------------------------------------------------------+
//| Log complete trade history for a symbol                           |
//+------------------------------------------------------------------+
void LogTradeHistory(string symbol) {
    string history = StringFormat("Trade History for %s:", symbol);
    bool foundTrades = false;
    
    for(int i = 0; i < ArraySize(lastClosedTrades); i++) {
        if(lastClosedTrades[i].symbol == symbol) {
            history += StringFormat(
                "\n%s: %s @ %.5f (%s) P/L: %.2f",
                TimeToString(lastClosedTrades[i].closeTime),
                lastClosedTrades[i].action,
                lastClosedTrades[i].closePrice,
                lastClosedTrades[i].closeReason,
                lastClosedTrades[i].profitLoss
            );
            foundTrades = true;
        }
    }
    
    if(foundTrades) {
        LogDebug(history);
    }
}



//+------------------------------------------------------------------+
//| Logging Helper Functions                                           |
//+------------------------------------------------------------------+
void LogError(string message, string symbol = "") {
  PrintDebug(message, "ERROR", symbol);
}

void LogWarning(string message, string symbol = "") {
  PrintDebug(message, "WARNING", symbol);
}

void LogInfo(string message, string symbol = "") {
  PrintDebug(message, "INFO", symbol);
}

void LogDebug(string message, string symbol = "") {
  PrintDebug(message, "DEBUG", symbol);
}

void LogTrade(string message, string symbol = "") {
  PrintDebug(message, "TRADE", symbol);
}

//+------------------------------------------------------------------+
//| Periodic monitoring function - called at intervals                  |
//+------------------------------------------------------------------+
void PerformPeriodicChecks() {
    static datetime lastMonitoringCheck = 0;
    datetime currentTime = TimeCurrent();
    
    // Run these checks every 5 minutes (300 seconds)
    if (currentTime - lastMonitoringCheck >= 300) {
        // Risk monitoring
        MonitorRiskLevels();
        
        // Log account status
        if (DEBUG_MODE) {
            LogDebug(StringFormat(
                "Account Status:" + 
                "\nBalance: %.2f" + 
                "\nEquity: %.2f" + 
                "\nMargin Level: %.2f%%",
                AccountBalance(), 
                AccountEquity(),
                AccountMargin() > 0 ? (AccountEquity() / AccountMargin() * 100) : 0
            ));
        }
        
        // Log market conditions if needed
        LogMarketConditions(Symbol());
        
        lastMonitoringCheck = currentTime;
    }
}

//+------------------------------------------------------------------+
//| Main tick function                                                |
//+------------------------------------------------------------------+
void OnTick() {
    // Critical safety checks first
    if (!IsTradeAllowed()) {
        static datetime lastErrorLog = 0;
        if (TimeCurrent() - lastErrorLog >= 300) {  // Log every 5 minutes
            LogError("Trading not allowed - check settings");
            lastErrorLog = TimeCurrent();
        }
        return;
    }

    // Initialize tracking variables for multiple symbols
    struct SymbolState {
        bool needsCheck;
        bool isActive;
        double lastBid;
        double lastAsk;
        datetime lastUpdate;
    };
    static SymbolState symbolStates[];
    
    // Ensure we have states for all monitored symbols
    string symbols[] = {"EURUSD+", "AUDUSD+", "GBPUSD+", "BTCUSD", "ETHUSD", "LTCUSD"};
    if (ArraySize(symbolStates) == 0) {
        ArrayResize(symbolStates, ArraySize(symbols));
        for (int i = 0; i < ArraySize(symbols); i++) {
            symbolStates[i].needsCheck = true;
            symbolStates[i].isActive = true;
            symbolStates[i].lastBid = 0;
            symbolStates[i].lastAsk = 0;
            symbolStates[i].lastUpdate = 0;
        }
    }

    // Emergency close check - highest priority but rate limited
    static datetime lastEmergencyCheck = 0;
    if (TimeCurrent() - lastEmergencyCheck >= 60) {  // Check every minute
        CheckEmergencyClose();
        lastEmergencyCheck = TimeCurrent();
    }

    // Periodic monitoring checks
    PerformPeriodicChecks();

    // Signal processing checks
    if (!IsTimeToCheck()) return;

    // Process each monitored symbol
    for (int i = 0; i < ArraySize(symbols); i++) {
        string currentSymbol = symbols[i];
        double currentBid = MarketInfo(currentSymbol, MODE_BID);
        double currentAsk = MarketInfo(currentSymbol, MODE_ASK);
        
        // Get instrument specifications
        int digits = GetSymbolDigits(currentSymbol);
        double contractSize = GetContractSize(currentSymbol);
        bool isCryptoPair = (StringFind(currentSymbol, "BTC") >= 0 || 
                            StringFind(currentSymbol, "ETH") >= 0 || 
                            StringFind(currentSymbol, "LTC") >= 0);

        // Check for price updates
        if (currentBid != symbolStates[i].lastBid || 
            currentAsk != symbolStates[i].lastAsk) {
            
            symbolStates[i].lastBid = currentBid;
            symbolStates[i].lastAsk = currentAsk;
            symbolStates[i].lastUpdate = TimeCurrent();
            symbolStates[i].needsCheck = true;

            // Log significant price movements
            if (symbolStates[i].lastBid > 0) {
                double priceChange = MathAbs(currentBid - symbolStates[i].lastBid);
                double threshold = isCryptoPair ? 50 : 0.0010;
                
                if (priceChange > threshold) {
                    LogDebug(StringFormat(
                        "Significant price movement [%s]:" +
                        "\nChange: %.*f" +
                        "\nBid: %.*f" +
                        "\nAsk: %.*f" +
                        "\nSpread: %.*f",
                        currentSymbol,
                        digits, priceChange,
                        digits, currentBid,
                        digits, currentAsk,
                        digits, currentAsk - currentBid
                    ));
                }
            }
        }

        // Market status validation
        if (!IsMarketOpen(currentSymbol)) {
            symbolStates[i].isActive = false;
            continue;
        }
        
        if (!IsMarketSessionActive(currentSymbol)) {
            symbolStates[i].isActive = false;
            continue;
        }

        symbolStates[i].isActive = true;

        // Process signals if needed
        if (symbolStates[i].needsCheck) {
            // Prepare API request
            string apiSymbol = GetBaseSymbol(currentSymbol);
            string url = StringFormat("%s?pairs=%s&tf=%s", API_URL, apiSymbol, TIMEFRAME);

            // Fetch and validate signals
            string response = FetchSignals(url);
            if (response == "") {
                static datetime lastApiErrorLog = 0;
                if (TimeCurrent() - lastApiErrorLog >= 300) {  // Log every 5 minutes
                    LogError(StringFormat("API Error for %s - Empty response", currentSymbol));
                    lastApiErrorLog = TimeCurrent();
                }
                continue;
            }

            // Process signal if valid
            SignalData signal;
            if (ParseSignal(response, signal)) {
                if (signal.price <= 0) {
                    LogError(StringFormat(
                        "Invalid signal price for %s: %.*f",
                        currentSymbol,
                        digits,
                        signal.price
                    ));
                    continue;
                }

                if (signal.timestamp == lastSignalTimestamp) continue;

                ProcessSignal(signal);
            }

            symbolStates[i].needsCheck = false;
        }
    }

    // Update last check time
    lastCheck = TimeCurrent();

    // Profit protection check - rate limited
    static datetime lastProfitCheck = 0;
    if (ENABLE_PROFIT_PROTECTION && TimeCurrent() - lastProfitCheck >= PROFIT_CHECK_INTERVAL) {
        CheckProfitProtection();
        lastProfitCheck = TimeCurrent();
    }
}

//+------------------------------------------------------------------+
//| Check if it's time to refresh signals                             |
//+------------------------------------------------------------------+
bool IsTimeToCheck() {
    static datetime lastValidCheck = 0;
    datetime currentTime = TimeCurrent();
    
    // Check if enough time has passed since last check
    if (currentTime < lastValidCheck + REFRESH_MINUTES * 60) {
        return false;
    }
    
    // Validate server connectivity
    if (!IsConnected()) {
        static datetime lastConnectionError = 0;
        if (currentTime - lastConnectionError >= 300) {  // Log every 5 minutes
            LogError("No server connection - skipping signal check");
            lastConnectionError = currentTime;
        }
        return false;
    }
    
    // Update last check time only if we pass all validations
    lastValidCheck = currentTime;
    return true;
}

//+------------------------------------------------------------------+
//| Fetch signals from API                                            |
//+------------------------------------------------------------------+
string FetchSignals(string url) {
   string headers = "Content-Type: application/json\r\n";
   char post[];
   char result[];
   string resultHeaders;
   
   int res = WebRequest(
      "GET",                   // Method
      url,                     // URL
      headers,                 // Headers
      5000,                    // Timeout
      post,                    // POST data
      result,                  // Server response
      resultHeaders            // Response headers
   );
   
   if(res == -1) {
      int errorCode = GetLastError();
      LogError(StringFormat("Error in WebRequest. Error code: %d", errorCode));
      return "";
   }
   
   string response = CharArrayToString(result);
   LogDebug(StringFormat("API Response: %s", response));
   return response;
}

//+------------------------------------------------------------------+
//| Parse JSON signal                                                 |
//+------------------------------------------------------------------+
bool ParseSignal(string &jsonString, SignalData &signal) {
    // Remove array brackets if present
    string json = jsonString;
    if(StringGetChar(json, 0) == '[') {
        json = StringSubstr(json, 1, StringLen(json) - 2);
    }

    LogDebug("Parsing JSON: " + json);

    // Extract and validate required fields
    string ticker = GetJsonValue(json, "ticker");
    string action = GetJsonValue(json, "action");
    string priceStr = GetJsonValue(json, "price");
    string timestamp = GetJsonValue(json, "timestamp");
    string pattern = GetJsonValue(json, "signalPattern");

    // Validate required fields
    if(ticker == "" || action == "" || priceStr == "") {
        LogError("Missing required signal fields");
        return false;
    }

    // Validate action type
    if(action != "BUY" && action != "SELL" && action != "NEUTRAL") {
        LogError("Invalid action type: " + action);
        return false;
    }

    // Format ticker based on pair type
    signal.ticker = (StringFind(ticker, "BTC") >= 0 || 
                    StringFind(ticker, "ETH") >= 0 || 
                    StringFind(ticker, "LTC") >= 0) ? ticker : ticker + "+";

    // Validate symbol exists
    if(MarketInfo(signal.ticker, MODE_BID) == 0) {
        LogError("Invalid symbol in signal: " + signal.ticker);
        return false;
    }

    // Get the correct number of digits for the symbol
    int symbolDigits = GetSymbolDigits(signal.ticker);
    
    // Convert and validate price
    signal.price = NormalizeDouble(StringToDouble(priceStr), symbolDigits);
    if(signal.price <= 0) {
        LogError(StringFormat("Invalid price value: %s", priceStr));
        return false;
    }

    // Validate price against current market price
    double currentBid = MarketInfo(signal.ticker, MODE_BID);
    double currentAsk = MarketInfo(signal.ticker, MODE_ASK);
    double spread = NormalizeDouble(currentAsk - currentBid, symbolDigits);
    double averagePrice = NormalizeDouble((currentBid + currentAsk) / 2, symbolDigits);
    
    // Calculate maximum allowed deviation based on instrument type
    double maxDeviation;
    if(StringFind(signal.ticker, "BTC") >= 0 || 
       StringFind(signal.ticker, "ETH") >= 0 || 
       StringFind(signal.ticker, "LTC") >= 0) {
        maxDeviation = 100;  // $100 for crypto
    } else if(StringFind(signal.ticker, "JPY") >= 0) {
        maxDeviation = 0.5;  // 50 pips for JPY pairs
    } else {
        maxDeviation = 0.005;  // 50 pips for regular forex
    }

    double priceDeviation = MathAbs(signal.price - averagePrice);
    if(priceDeviation > maxDeviation) {
        LogWarning(StringFormat(
            "Large price deviation detected for %s:" +
            "\nSignal Price: %.*f" +
            "\nMarket Price: %.*f" +
            "\nDeviation: %.*f" +
            "\nSpread: %.*f" +
            "\nMax Allowed: %.*f",
            signal.ticker,
            symbolDigits, signal.price,
            symbolDigits, averagePrice,
            symbolDigits, priceDeviation,
            symbolDigits, spread,
            symbolDigits, maxDeviation
        ));
    }

    // Set remaining signal data
    signal.action = action;
    signal.timestamp = timestamp;
    signal.pattern = pattern;

    LogDebug(StringFormat(
        "Signal Parsed Successfully:" +
        "\nSymbol: %s" +
        "\nAction: %s" +
        "\nPrice: %.*f" +
        "\nDigits: %d" +
        "\nContract Size: %.2f" +
        "\nMargin Requirement: %.2f%%",
        signal.ticker,
        signal.action,
        symbolDigits, signal.price,
        symbolDigits,
        GetContractSize(signal.ticker),
        GetMarginPercent(signal.ticker) * 100
    ));

    return true;
}

//+------------------------------------------------------------------+
//| Calculate position size based on risk and stop loss                |
//+------------------------------------------------------------------+
double CalculatePositionSize(string symbol, double entryPrice, double stopLoss) {
    // Calculate maximum risk amount based on account balance
    double accountBalance = AccountBalance();
    double maxRiskAmount = accountBalance * (RISK_PERCENT / 100);
    double stopDistance = MathAbs(entryPrice - stopLoss);

    if (stopDistance == 0) {
        LogError("Error: Stop loss distance cannot be zero");
        return 0;
    }

    bool isCryptoPair = (StringFind(symbol, "BTC") >= 0 || 
                        StringFind(symbol, "ETH") >= 0 || 
                        StringFind(symbol, "LTC") >= 0);
    bool isJPYPair = (StringFind(symbol, "JPY") >= 0);
    int digits = GetSymbolDigits(symbol);
    double contractSize = GetContractSize(symbol);
    double marginPercent = GetMarginPercent(symbol);

    LogDebug(StringFormat(
        "Position Size Calculation Starting:" +
        "\nSymbol: %s" +
        "\nContract Size: %.2f" +
        "\nMargin Requirement: %.2f%%" +
        "\nAccount Balance: $%.2f" +
        "\nRisk Amount: $%.2f" +
        "\nEntry Price: %.*f" +
        "\nStop Loss: %.*f" +
        "\nStop Distance: %.*f",
        symbol, 
        contractSize,
        marginPercent * 100,
        accountBalance, 
        maxRiskAmount, 
        digits, entryPrice,
        digits, stopLoss,
        digits, stopDistance
    ), symbol);

    double lotSize;

    if (isCryptoPair) {
        // Calculate true USD risk per lot considering contract size
        double oneUnitValue = entryPrice * contractSize;
        double riskPerLot = stopDistance * oneUnitValue;
        
        // Initial lot size based on risk
        lotSize = maxRiskAmount / riskPerLot;
        
        // Calculate margin requirement per lot
        double marginRequired = oneUnitValue * marginPercent;
        
        // Maximum position value based on available margin with safety buffer
        double maxPositionValue = AccountFreeMargin() / (marginPercent * 1.5); // 150% margin reserve
        double maxLotsBasedOnMargin = maxPositionValue / oneUnitValue;
        
        // Maximum position based on account equity (prevent over-leverage)
        double maxEquityPercent = RISK_PERCENT * 2; // 2x risk percent for max position size
        double maxPositionEquity = AccountEquity() * (maxEquityPercent / 100);
        double maxLotsBasedOnEquity = maxPositionEquity / oneUnitValue;
        
        // Take the minimum of all constraints
        lotSize = MathMin(lotSize, maxLotsBasedOnMargin);
        lotSize = MathMin(lotSize, maxLotsBasedOnEquity);
        
        LogDebug(StringFormat(
            "Crypto Position Size Calculation:" +
            "\nOne Unit Value: $%.2f" +
            "\nRisk Per Lot: $%.2f" +
            "\nMargin Required Per Lot: $%.2f" +
            "\nMax Lots (Margin): %.4f" +
            "\nMax Lots (Equity): %.4f" +
            "\nSelected Size: %.4f",
            oneUnitValue,
            riskPerLot,
            marginRequired,
            maxLotsBasedOnMargin,
            maxLotsBasedOnEquity,
            lotSize
        ));
    } else {
        // Forex position sizing
        double point = MarketInfo(symbol, MODE_POINT);
        double tickValue = MarketInfo(symbol, MODE_TICKVALUE);
        double pipSize = isJPYPair ? 0.01 : 0.0001;
        double pipValue = isJPYPair ? (tickValue * 100) : (tickValue * 10);
        double stopPoints = stopDistance / point;
        
        // Calculate risk per standard lot
        double riskPerLot = stopPoints * tickValue;
        
        // Initial lot size based on risk
        lotSize = maxRiskAmount / riskPerLot;
        
        // Calculate margin requirement per lot
        double marginRequired = contractSize * entryPrice * marginPercent;
        double maxLotsBasedOnMargin = AccountFreeMargin() / (marginRequired * 1.5);
        
        // Maximum position based on account equity
        double maxEquityPercent = RISK_PERCENT * 2;
        double maxPositionEquity = AccountEquity() * (maxEquityPercent / 100);
        double maxLotsBasedOnEquity = maxPositionEquity / (contractSize * entryPrice);
        
        // Apply all constraints
        lotSize = MathMin(lotSize, maxLotsBasedOnMargin);
        lotSize = MathMin(lotSize, maxLotsBasedOnEquity);
        
        LogDebug(StringFormat(
            "Forex Position Size Calculation:" +
            "\nStop Distance (points): %.1f" +
            "\nPip Value: $%.5f" +
            "\nRisk Per Lot: $%.2f" +
            "\nMargin Required Per Lot: $%.2f" +
            "\nMax Lots (Margin): %.2f" +
            "\nMax Lots (Equity): %.2f" +
            "\nSelected Size: %.2f",
            stopPoints,
            pipValue,
            riskPerLot,
            marginRequired,
            maxLotsBasedOnMargin,
            maxLotsBasedOnEquity,
            lotSize
        ));
    }
    
    // Apply broker constraints
    double minLot = MarketInfo(symbol, MODE_MINLOT);
    double maxLot = MarketInfo(symbol, MODE_MAXLOT);
    double lotStep = MarketInfo(symbol, MODE_LOTSTEP);
    
    // Round to lot step
    lotSize = MathFloor(lotSize / lotStep) * lotStep;
    
    // Ensure within broker's limits
    lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
    
    // Calculate and validate final risk
    double finalRisk = CalculateFinalPositionRisk(symbol, lotSize, entryPrice, stopLoss);
    double finalRiskPercent = (finalRisk / accountBalance) * 100;
    
    LogDebug(StringFormat(
        "Final Position Size:" +
        "\nLot Size: %.4f" +
        "\nActual Risk Amount: $%.2f" +
        "\nRisk Percent: %.2f%%",
        lotSize,
        finalRisk,
        finalRiskPercent
    ));
    
    return lotSize;
}

// Helper function to calculate final position risk
double CalculateFinalPositionRisk(string symbol, double lots, double entryPrice, double stopLoss) {
    bool isCryptoPair = (StringFind(symbol, "BTC") >= 0 || 
                        StringFind(symbol, "ETH") >= 0 || 
                        StringFind(symbol, "LTC") >= 0);
    double contractSize = GetContractSize(symbol);
    double stopDistance = MathAbs(entryPrice - stopLoss);
    
    if (isCryptoPair) {
        return stopDistance * lots * contractSize;
    } else {
        double tickValue = MarketInfo(symbol, MODE_TICKVALUE);
        double point = MarketInfo(symbol, MODE_POINT);
        return (stopDistance / point) * tickValue * lots;
    }
}
//+------------------------------------------------------------------+
//| Calculate Stop Loss price based on pair type                       |
//+------------------------------------------------------------------+
double CalculateStopLoss(string symbol, int cmd, double entryPrice) {
    // Validate entry price
    if (entryPrice <= 0) {
        LogError(StringFormat("Invalid entry price for %s: %.5f", symbol, entryPrice));
        return 0;
    }
    
    // Get instrument specifications
    int digits = GetSymbolDigits(symbol);
    bool isCryptoPair = (StringFind(symbol, "BTC") >= 0 || 
                        StringFind(symbol, "ETH") >= 0 || 
                        StringFind(symbol, "LTC") >= 0);
    bool isJPYPair = (StringFind(symbol, "JPY") >= 0);
    double contractSize = GetContractSize(symbol);
    double point = MarketInfo(symbol, MODE_POINT);
    
    double stopLoss = 0;
    
    // Calculate stop loss based on instrument type
    if (isCryptoPair) {
        // Percentage-based stop for crypto
        double stopDistance = entryPrice * (CRYPTO_STOP_PERCENT / 100);
        stopLoss = cmd == OP_BUY ? 
                  NormalizeDouble(entryPrice - stopDistance, digits) :
                  NormalizeDouble(entryPrice + stopDistance, digits);
        
        // Calculate monetary value of stop loss
        double stopValue = stopDistance * contractSize;
        
        LogDebug(StringFormat(
            "Crypto Stop Loss Calculation [%s]:" +
            "\nDirection: %s" +
            "\nEntry Price: %.*f" +
            "\nStop Loss: %.*f" +
            "\nStop Distance: %.*f" +
            "\nStop Percent: %.2f%%" +
            "\nContract Size: %.2f" +
            "\nStop Value: $%.2f",
            symbol,
            cmd == OP_BUY ? "BUY" : "SELL",
            digits, entryPrice,
            digits, stopLoss,
            digits, stopDistance,
            CRYPTO_STOP_PERCENT,
            contractSize,
            stopValue
        ));
    } else {
        // Pip-based stop for forex
        double pipSize = isJPYPair ? 0.01 : 0.0001;
        double pipValue = MarketInfo(symbol, MODE_TICKVALUE) * (isJPYPair ? 100 : 10);
        double stopPips = FOREX_STOP_PIPS;
        double stopDistance = stopPips * pipSize;
        
        stopLoss = cmd == OP_BUY ? 
                  NormalizeDouble(entryPrice - stopDistance, digits) :
                  NormalizeDouble(entryPrice + stopDistance, digits);
                  
        // Calculate monetary value of stop loss
        double stopValue = FOREX_STOP_PIPS * pipValue * (contractSize / 100000.0);
        
        LogDebug(StringFormat(
            "Forex Stop Loss Calculation [%s]:" +
            "\nDirection: %s" +
            "\nEntry Price: %.*f" +
            "\nStop Loss: %.*f" +
            "\nStop Distance: %.*f" +
            "\nStop Pips: %.1f" +
            "\nPip Value: $%.5f" +
            "\nStop Value: $%.2f",
            symbol,
            cmd == OP_BUY ? "BUY" : "SELL",
            digits, entryPrice,
            digits, stopLoss,
            digits, stopDistance,
            stopPips,
            pipValue,
            stopValue
        ));
    }
    
    // Validation checks
    if (cmd == OP_BUY && stopLoss >= entryPrice) {
        LogError(StringFormat(
            "Invalid buy stop loss - must be below entry price:" +
            "\nEntry: %.*f" +
            "\nStop: %.*f",
            digits, entryPrice,
            digits, stopLoss
        ));
        return 0;
    }
    
    if (cmd == OP_SELL && stopLoss <= entryPrice) {
        LogError(StringFormat(
            "Invalid sell stop loss - must be above entry price:" +
            "\nEntry: %.*f" +
            "\nStop: %.*f",
            digits, entryPrice,
            digits, stopLoss
        ));
        return 0;
    }
    
    // Check minimum stop distance
    double minStop = MarketInfo(symbol, MODE_STOPLEVEL) * point;
    if (MathAbs(entryPrice - stopLoss) < minStop) {
        LogError(StringFormat(
            "Stop loss too close to entry price:" +
            "\nMinimum distance: %.*f" +
            "\nActual distance: %.*f",
            digits, minStop,
            digits, MathAbs(entryPrice - stopLoss)
        ));
        return 0;
    }
    
    return stopLoss;
}

//+------------------------------------------------------------------+
//| Process trading signal                                            |
//+------------------------------------------------------------------+
void ProcessSignal(SignalData &signal) {
    // Get instrument specifications and validate
    int digits = GetSymbolDigits(signal.ticker);
    double contractSize = GetContractSize(signal.ticker);
    double marginPercent = GetMarginPercent(signal.ticker);
    
    // Initial symbol validation
    if (MarketInfo(signal.ticker, MODE_BID) == 0) {
        LogError(StringFormat("Invalid symbol %s", signal.ticker));
        return;
    }

    // Market availability checks
    if (!IsMarketOpen(signal.ticker)) {
        LogDebug(StringFormat("Market closed for %s", signal.ticker));
        return;
    }

    // Duplicate signal check
    if (signal.timestamp == lastSignalTimestamp) {
        LogDebug(StringFormat("Duplicate signal for timestamp: %s", signal.timestamp));
        return;
    }

    // Determine order type
    int cmd = -1;
    if (signal.action == "BUY") cmd = OP_BUY;
    else if (signal.action == "SELL") cmd = OP_SELL;
    else {
        LogDebug(StringFormat("NEUTRAL signal for %s - no action", signal.ticker));
        return;
    }

    // Previous trade validation
    if (!IsNewTradeAllowed(signal.ticker, signal.action)) {
        LogInfo(StringFormat(
            "Signal skipped - Waiting for opposite direction after previous %s",
            signal.action
        ), signal.ticker);
        return;
    }

    // Get current market prices
    double ask = MarketInfo(signal.ticker, MODE_ASK);
    double bid = MarketInfo(signal.ticker, MODE_BID);
    double price = cmd == OP_BUY ? ask : bid;
    
    // Log market conditions
    LogDebug(StringFormat(
        "Market Prices for %s:" +
        "\nBid: %.*f" +
        "\nAsk: %.*f" +
        "\nSpread: %.*f" +
        "\nContract Size: %.2f" +
        "\nMargin Required: %.2f%%",
        signal.ticker,
        digits, bid,
        digits, ask,
        digits, ask - bid,
        contractSize,
        marginPercent * 100
    ));

    // Handle existing positions
    if (HasOpenPosition(signal.ticker)) {
        int currentPositionType = GetOpenPositionType(signal.ticker);
        
        // Close if opposite signal
        if ((cmd == OP_BUY && currentPositionType == OP_SELL) ||
            (cmd == OP_SELL && currentPositionType == OP_BUY)) {
            
            LogTrade(StringFormat(
                "Reverse signal received:" +
                "\nSymbol: %s" +
                "\nCurrent: %s" +
                "\nNew Signal: %s",
                signal.ticker,
                currentPositionType == OP_BUY ? "BUY" : "SELL",
                signal.action
            ));

            if (!CloseCurrentPosition(signal.ticker)) {
                LogError(StringFormat(
                    "Failed to close existing position for %s",
                    signal.ticker
                ));
                return;
            }
        } else {
            LogDebug(StringFormat(
                "Position exists in same direction for %s",
                signal.ticker
            ));
            return;
        }
    }

    // Risk management check
    if (!CanOpenNewPosition(signal.ticker)) {
        LogDebug(StringFormat(
            "Risk management prevented new position for %s",
            signal.ticker
        ));
        return;
    }

    // Calculate stop loss
    double sl = CalculateStopLoss(signal.ticker, cmd, price);
    if (sl == 0) {
        LogError(StringFormat(
            "Invalid stop loss calculated for %s at %.*f",
            signal.ticker,
            digits, price
        ));
        return;
    }

    // Calculate position size
    double lotSize = CalculatePositionSize(signal.ticker, price, sl);
    if (lotSize == 0) {
        LogError(StringFormat(
            "Invalid lot size calculated for %s",
            signal.ticker
        ));
        return;
    }

    // Final risk validation
    double positionRisk = CalculateFinalPositionRisk(signal.ticker, lotSize, price, sl);
    double riskPercent = (positionRisk / AccountBalance()) * 100;

    if (riskPercent > RISK_PERCENT) {
        LogError(StringFormat(
            "Trade rejected - Risk exceeds limit:" +
            "\nCalculated Risk: %.2f%%" +
            "\nMaximum Allowed: %.2f%%" +
            "\nRisk Amount: $%.2f",
            riskPercent,
            RISK_PERCENT,
            positionRisk
        ));
        return;
    }

    // Prepare order parameters
    double tp = 0;  // Take profit handled by profit protection
    int slippage = StringFind(signal.ticker, "BTC") >= 0 || 
                  StringFind(signal.ticker, "ETH") >= 0 || 
                  StringFind(signal.ticker, "LTC") >= 0 ? 
                  MAX_SLIPPAGE * 2 : MAX_SLIPPAGE;

    // Log trade details
    LogTrade(StringFormat(
        "Placing new order:" +
        "\nSymbol: %s" +
        "\nType: %s" +
        "\nLots: %.2f" +
        "\nPrice: %.*f" +
        "\nStop Loss: %.*f" +
        "\nContract Size: %.2f" +
        "\nRisk Amount: $%.2f (%.2f%%)",
        signal.ticker,
        cmd == OP_BUY ? "BUY" : "SELL",
        lotSize,
        digits, price,
        digits, sl,
        contractSize,
        positionRisk,
        riskPercent
    ));

    // Place the order
    int ticket = OrderSend(
        signal.ticker,
        cmd,
        lotSize,
        price,
        slippage,
        sl,
        tp,
        signal.pattern,
        0,
        0,
        cmd == OP_BUY ? clrGreen : clrRed
    );

    // Handle order result
    if (ticket < 0) {
        int error = GetLastError();

        // Implement retry logic
        for (int retry = 1; retry <= MAX_RETRIES; retry++) {
            LogDebug(StringFormat("Retry %d of %d", retry, MAX_RETRIES));

            RefreshRates();
            price = cmd == OP_BUY ? MarketInfo(signal.ticker, MODE_ASK)
                                : MarketInfo(signal.ticker, MODE_BID);

            ticket = OrderSend(
                signal.ticker,
                cmd,
                lotSize,
                price,
                slippage,
                sl,
                tp,
                signal.pattern,
                0,
                0,
                cmd == OP_BUY ? clrGreen : clrRed
            );

            if (ticket >= 0) break;
            Sleep(1000 * retry);  // Exponential backoff
        }

        if (ticket < 0) {
            LogError(StringFormat(
                "Order placement failed:" +
                "\nError: %d (%s)" +
                "\nSymbol: %s" +
                "\nLots: %.2f" +
                "\nPrice: %.*f",
                error,
                ErrorDescription(error),
                signal.ticker,
                lotSize,
                digits, price
            ));
            return;
        }
    }

    // Log successful trade
    if (ticket >= 0) {
        LogTrade(StringFormat(
            "Order placed successfully:" +
            "\nTicket: %d" +
            "\nSymbol: %s" +
            "\nType: %s" +
            "\nLots: %.2f" +
            "\nPrice: %.*f" +
            "\nRisk: %.2f%%",
            ticket,
            signal.ticker,
            signal.action,
            lotSize,
            digits, price,
            riskPercent
        ));
        lastSignalTimestamp = signal.timestamp;
    }
}

//+------------------------------------------------------------------+
//| Check and Protect Profitable Positions                             |
//+------------------------------------------------------------------+
void CheckProfitProtection() {
    static datetime lastProfitCheck = 0;
    datetime currentTime = TimeCurrent();

    if (currentTime - lastProfitCheck < PROFIT_CHECK_INTERVAL) return;
    lastProfitCheck = currentTime;

    if (!ENABLE_PROFIT_PROTECTION) return;

    // Track profit protection activity
    int cryptoProtectionTriggered = 0;
    int forexProtectionTriggered = 0;
    double totalProtectedProfit = 0;

    for (int i = 0; i < OrdersTotal(); i++) {
        if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;

        string symbol = OrderSymbol();
        bool isCryptoPair = (StringFind(symbol, "BTC") >= 0 || 
                           StringFind(symbol, "ETH") >= 0 || 
                           StringFind(symbol, "LTC") >= 0);
        bool isJPYPair = (StringFind(symbol, "JPY") >= 0);
        
        // Get symbol specifications
        int digits = GetSymbolDigits(symbol);
        double contractSize = GetContractSize(symbol);
        
        // Get position details
        double openPrice = NormalizeDouble(OrderOpenPrice(), digits);
        double currentPrice = NormalizeDouble(
            OrderType() == OP_BUY ? MarketInfo(symbol, MODE_BID) : MarketInfo(symbol, MODE_ASK),
            digits
        );
        double lots = OrderLots();

        if (isCryptoPair) {
            // Calculate position values and profit for crypto
            double positionValue = lots * contractSize * openPrice;
            double currentValue = lots * contractSize * currentPrice;
            double unrealizedPL = OrderType() == OP_BUY ? 
                                (currentValue - positionValue) : 
                                (positionValue - currentValue);
            
            double profitPercent = (unrealizedPL / positionValue) * 100;

            // Log crypto position status
            LogDebug(StringFormat(
                "Crypto Profit Check [%s]:" +
                "\nType: %s" +
                "\nLots: %.4f" +
                "\nContract Size: %.2f" +
                "\nPosition Value: $%.2f" +
                "\nCurrent Value: $%.2f" +
                "\nUnrealized P/L: $%.2f (%.2f%%)" +
                "\nProfit Threshold: %.2f%%" +
                "\nLock Level: %.2f%%",
                symbol,
                OrderType() == OP_BUY ? "BUY" : "SELL",
                lots,
                contractSize,
                positionValue,
                currentValue,
                unrealizedPL,
                profitPercent,
                CRYPTO_PROFIT_THRESHOLD,
                CRYPTO_PROFIT_LOCK_PERCENT
            ));

            // Check if profit threshold is reached
            if (profitPercent >= CRYPTO_PROFIT_THRESHOLD) {
                double lockPrice;
                
                if (OrderType() == OP_BUY) {
                    // Calculate lock price for long positions
                    lockPrice = NormalizeDouble(
                        openPrice * (1 + CRYPTO_PROFIT_LOCK_PERCENT / 100.0),
                        digits
                    );

                    // Check if price has fallen to lock level
                    if (currentPrice <= lockPrice) {
                        LogTrade(StringFormat(
                            "Crypto Profit Protection Triggered:" +
                            "\nSymbol: %s" +
                            "\nType: BUY" +
                            "\nTicket: %d" +
                            "\nProfit: %.2f%% ($%.2f)" +
                            "\nLock Level: %.2f%%" +
                            "\nOpen: %.*f" +
                            "\nCurrent: %.*f" +
                            "\nLock: %.*f",
                            symbol,
                            OrderTicket(),
                            profitPercent,
                            unrealizedPL,
                            CRYPTO_PROFIT_LOCK_PERCENT,
                            digits, openPrice,
                            digits, currentPrice,
                            digits, lockPrice
                        ));
                        
                        if (CloseCurrentPosition(symbol, OrderTicket())) {
                            cryptoProtectionTriggered++;
                            totalProtectedProfit += unrealizedPL;
                        }
                    }
                } else {
                    // Calculate lock price for short positions
                    lockPrice = NormalizeDouble(
                        openPrice * (1 - CRYPTO_PROFIT_LOCK_PERCENT / 100.0),
                        digits
                    );

                    // Check if price has risen to lock level
                    if (currentPrice >= lockPrice) {
                        LogTrade(StringFormat(
                            "Crypto Profit Protection Triggered:" +
                            "\nSymbol: %s" +
                            "\nType: SELL" +
                            "\nTicket: %d" +
                            "\nProfit: %.2f%% ($%.2f)" +
                            "\nLock Level: %.2f%%" +
                            "\nOpen: %.*f" +
                            "\nCurrent: %.*f" +
                            "\nLock: %.*f",
                            symbol,
                            OrderTicket(),
                            profitPercent,
                            unrealizedPL,
                            CRYPTO_PROFIT_LOCK_PERCENT,
                            digits, openPrice,
                            digits, currentPrice,
                            digits, lockPrice
                        ));
                        
                        if (CloseCurrentPosition(symbol, OrderTicket())) {
                            cryptoProtectionTriggered++;
                            totalProtectedProfit += unrealizedPL;
                        }
                    }
                }
            }
        } else {
            // Forex profit calculations
            double pipSize = isJPYPair ? 0.01 : 0.0001;
            double pipValue = MarketInfo(symbol, MODE_TICKVALUE) * (isJPYPair ? 100 : 10);
            double profitInPips = OrderType() == OP_BUY ? 
                                (currentPrice - openPrice) / pipSize : 
                                (openPrice - currentPrice) / pipSize;
            
            double unrealizedPL = profitInPips * pipValue * lots;

            // Log forex position status
            LogDebug(StringFormat(
                "Forex Profit Check [%s]:" +
                "\nType: %s" +
                "\nLots: %.2f" +
                "\nProfit: %.1f pips ($%.2f)" +
                "\nPip Value: $%.2f" +
                "\nProfit Threshold: %.1f pips" +
                "\nLock Level: %.1f pips",
                symbol,
                OrderType() == OP_BUY ? "BUY" : "SELL",
                lots,
                profitInPips,
                unrealizedPL,
                pipValue,
                FOREX_PROFIT_PIPS_THRESHOLD,
                FOREX_PROFIT_LOCK_PIPS
            ));

            // Check if profit threshold is reached
            if (profitInPips >= FOREX_PROFIT_PIPS_THRESHOLD) {
                double lockPrice;
                
                if (OrderType() == OP_BUY) {
                    // Calculate lock price for long positions
                    lockPrice = NormalizeDouble(
                        openPrice + (FOREX_PROFIT_LOCK_PIPS * pipSize),
                        digits
                    );

                    // Check if price has fallen to lock level
                    if (currentPrice <= lockPrice) {
                        LogTrade(StringFormat(
                            "Forex Profit Protection Triggered:" +
                            "\nSymbol: %s" +
                            "\nType: BUY" +
                            "\nTicket: %d" +
                            "\nProfit: %.1f pips ($%.2f)" +
                            "\nLock Level: %.1f pips" +
                            "\nOpen: %.*f" +
                            "\nCurrent: %.*f" +
                            "\nLock: %.*f",
                            symbol,
                            OrderTicket(),
                            profitInPips,
                            unrealizedPL,
                            FOREX_PROFIT_LOCK_PIPS,
                            digits, openPrice,
                            digits, currentPrice,
                            digits, lockPrice
                        ));
                        
                        if (CloseCurrentPosition(symbol, OrderTicket())) {
                            forexProtectionTriggered++;
                            totalProtectedProfit += unrealizedPL;
                        }
                    }
                } else {
                    // Calculate lock price for short positions
                    lockPrice = NormalizeDouble(
                        openPrice - (FOREX_PROFIT_LOCK_PIPS * pipSize),
                        digits
                    );

                    // Check if price has risen to lock level
                    if (currentPrice >= lockPrice) {
                        LogTrade(StringFormat(
                            "Forex Profit Protection Triggered:" +
                            "\nSymbol: %s" +
                            "\nType: SELL" +
                            "\nTicket: %d" +
                            "\nProfit: %.1f pips ($%.2f)" +
                            "\nLock Level: %.1f pips" +
                            "\nOpen: %.*f" +
                            "\nCurrent: %.*f" +
                            "\nLock: %.*f",
                            symbol,
                            OrderTicket(),
                            profitInPips,
                            unrealizedPL,
                            FOREX_PROFIT_LOCK_PIPS,
                            digits, openPrice,
                            digits, currentPrice,
                            digits, lockPrice
                        ));
                        
                        if (CloseCurrentPosition(symbol, OrderTicket())) {
                            forexProtectionTriggered++;
                            totalProtectedProfit += unrealizedPL;
                        }
                    }
                }
            }
        }
    }

    // Log summary if any positions were closed
    if (cryptoProtectionTriggered > 0 || forexProtectionTriggered > 0) {
        LogInfo(StringFormat(
            "Profit Protection Summary:" +
            "\nCrypto Positions Closed: %d" +
            "\nForex Positions Closed: %d" +
            "\nTotal Protected Profit: $%.2f",
            cryptoProtectionTriggered,
            forexProtectionTriggered,
            totalProtectedProfit
        ));
    }
}

//+------------------------------------------------------------------+
//| Check if we can open new positions based on risk management        |
//+------------------------------------------------------------------+
bool CanOpenNewPosition(string symbol) {
    // Get instrument specifications
    double contractSize = GetContractSize(symbol);
    double marginPercent = GetMarginPercent(symbol);
    int digits = GetSymbolDigits(symbol);
    bool isCryptoPair = (StringFind(symbol, "BTC") >= 0 || 
                        StringFind(symbol, "ETH") >= 0 || 
                        StringFind(symbol, "LTC") >= 0);

    // Initial account metrics
    double accountBalance = AccountBalance();
    double accountEquity = AccountEquity();
    double freeMargin = AccountFreeMargin();
    
    // Position tracking
    int symbolPositions = 0;
    double symbolVolume = 0;
    double totalRiskInSymbol = 0;
    
    // Analyze existing positions
    for (int i = 0; i < OrdersTotal(); i++) {
        if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
            LogError(StringFormat("Failed to select order %d: %s", 
                i, ErrorDescription(GetLastError())));
            continue;
        }
        
        if (OrderSymbol() == symbol) {
            symbolPositions++;
            symbolVolume += OrderLots();
            
            // Calculate position risk
            double openPrice = OrderOpenPrice();
            double stopLoss = OrderStopLoss();
            
            if (stopLoss != 0) {
                double positionRisk = CalculateFinalPositionRisk(
                    symbol, OrderLots(), openPrice, stopLoss);
                totalRiskInSymbol += positionRisk;
            }
        }
    }
    
    // Position limit check
    if (symbolPositions >= MAX_POSITIONS) {
        LogDebug(StringFormat(
            "Maximum positions reached for %s: %d/%d",
            symbol, symbolPositions, MAX_POSITIONS));
        return false;
    }
    
    // Calculate risk percentages
    double symbolRiskPercent = (totalRiskInSymbol / accountBalance) * 100;
    double totalAccountRisk = CalculateTotalAccountRisk();
    double accountRiskPercent = (totalAccountRisk / accountBalance) * 100;
    
    // Calculate margin requirements
    double currentPrice = MarketInfo(symbol, MODE_ASK);
    double lotSize = MarketInfo(symbol, MODE_MINLOT);  // Using minimum lot for calculation
    double positionValue = currentPrice * contractSize * lotSize;
    double marginRequired = positionValue * marginPercent;
    double marginLevel = AccountMargin() > 0 ? (accountEquity / AccountMargin() * 100) : 0;
    
    // Log position analysis
    LogDebug(StringFormat(
        "Position Analysis for %s:" +
        "\nContract Specifications:" +
        "\n  Contract Size: %.2f" +
        "\n  Margin Requirement: %.2f%%" +
        "\n  Current Price: %.*f" +
        "\nPosition Metrics:" +
        "\n  Current Positions: %d/%d" +
        "\n  Symbol Volume: %.2f" +
        "\n  Symbol Risk: %.2f%%" +
        "\nAccount Metrics:" +
        "\n  Balance: $%.2f" +
        "\n  Equity: $%.2f" +
        "\n  Free Margin: $%.2f" +
        "\n  Margin Level: %.2f%%" +
        "\n  Total Account Risk: %.2f%%",
        symbol,
        contractSize,
        marginPercent * 100,
        digits, currentPrice,
        symbolPositions, MAX_POSITIONS,
        symbolVolume,
        symbolRiskPercent,
        accountBalance,
        accountEquity,
        freeMargin,
        marginLevel,
        accountRiskPercent
    ));
    
    // Risk limit checks
    if (symbolRiskPercent >= (RISK_PERCENT * 2)) {
        LogWarning(StringFormat(
            "Symbol risk too high for %s: %.2f%% (Max: %.2f%%)",
            symbol, symbolRiskPercent, RISK_PERCENT * 2));
        return false;
    }
    
    if (accountRiskPercent >= (RISK_PERCENT * 3)) {
        LogWarning(StringFormat(
            "Account risk too high: %.2f%% (Max: %.2f%%)",
            accountRiskPercent, RISK_PERCENT * 3));
        return false;
    }
    
    // Margin safety check
    if (marginRequired > freeMargin * 0.9) {  // 90% margin threshold
        LogWarning(StringFormat(
            "Insufficient free margin for %s:" +
            "\nRequired: $%.2f" +
            "\nAvailable: $%.2f",
            symbol, marginRequired, freeMargin));
        return false;
    }
    
    if (marginLevel > 0 && marginLevel < 150) {
        LogWarning(StringFormat(
            "Margin level too low: %.2f%%",
            marginLevel));
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Get the type of open position (OP_BUY or OP_SELL)                 |
//+------------------------------------------------------------------+
int GetOpenPositionType(string symbol) {
  for (int i = 0; i < OrdersTotal(); i++) {
    if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
      if (OrderSymbol() == symbol) {
        return OrderType();
      }
    }
  }
  return -1;
}

//+------------------------------------------------------------------+
//| Close position with enhanced protection                            |
//+------------------------------------------------------------------+
bool CloseCurrentPosition(string symbol = "", int ticket = 0) {
    int totalTries = MAX_RETRIES;
    bool closeByTicket = (ticket > 0);
    
    // Initial order selection
    if (closeByTicket) {
        if (!OrderSelect(ticket, SELECT_BY_TICKET)) {
            LogError(StringFormat(
                "Failed to select order ticket %d: %s",
                ticket, ErrorDescription(GetLastError())));
            return false;
        }
        symbol = OrderSymbol();
    }
    
    // Get instrument specifications
    bool isCryptoPair = (StringFind(symbol, "BTC") >= 0 || 
                        StringFind(symbol, "ETH") >= 0 || 
                        StringFind(symbol, "LTC") >= 0);
    int digits = GetSymbolDigits(symbol);
    int slippage = isCryptoPair ? MAX_SLIPPAGE * 2 : MAX_SLIPPAGE;
    
    for (int attempt = 1; attempt <= totalTries; attempt++) {
        // Process orders
        if (!closeByTicket) {
            // Close all positions for symbol
            for (int i = OrdersTotal() - 1; i >= 0; i--) {
                if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES) || 
                    OrderSymbol() != symbol) continue;
                
                if (ProcessCloseOrder(OrderTicket(), attempt, totalTries, slippage)) 
                    continue;
                else 
                    return false;
            }
        } else {
            // Close specific ticket
            if (ProcessCloseOrder(ticket, attempt, totalTries, slippage)) 
                return true;
        }
        
        if (attempt < totalTries) {
            Sleep(1000 * attempt);  // Exponential backoff
            RefreshRates();
        }
    }
    
    LogError(StringFormat(
        "Failed to close position after %d attempts:" +
        "\nSymbol: %s" +
        "\nTicket: %d",
        totalTries, symbol, ticket));
        
    return false;
}

bool ProcessCloseOrder(int ticket, int attempt, int totalTries, int slippage) {
    if (!OrderSelect(ticket, SELECT_BY_TICKET)) return false;
    
    string symbol = OrderSymbol();
    int type = OrderType();
    double lots = OrderLots();
    double openPrice = OrderOpenPrice();
    
    RefreshRates();
    double closePrice = type == OP_BUY ? 
                       MarketInfo(symbol, MODE_BID) : 
                       MarketInfo(symbol, MODE_ASK);
    
    LogTrade(StringFormat(
        "Attempting position close:" +
        "\nAttempt: %d/%d" +
        "\nTicket: %d" +
        "\nSymbol: %s" +
        "\nType: %s" +
        "\nLots: %.2f" +
        "\nClose Price: %.5f",
        attempt, totalTries,
        ticket,
        symbol,
        type == OP_BUY ? "BUY" : "SELL",
        lots,
        closePrice
    ));
    
    bool success = OrderClose(ticket, lots, closePrice, slippage, clrRed);
    
    if (success) {
        double profit = OrderProfit() + OrderSwap() + OrderCommission();
        LogTrade(StringFormat(
            "Position closed successfully:" +
            "\nTicket: %d" +
            "\nProfit: %.2f" +
            "\nAttempts: %d",
            ticket, profit, attempt));
            
        // Record the closed trade
        RecordClosedTrade(symbol, type == OP_BUY ? "BUY" : "SELL", profit);
        return true;
    }
    
    // Handle close failure
    int error = GetLastError();
    string severity = GetErrorSeverity(error);
    
    if (severity == "CRITICAL") {
        LogError(StringFormat(
            "Critical error closing position:" +
            "\nSymbol: %s" +
            "\nTicket: %d" +
            "\nAttempt: %d/%d" +
            "\nError: %s" +
            "\nSeverity: %s",
            symbol, ticket, attempt, totalTries,
            ErrorDescription(error), severity));
    } else {
        LogWarning(StringFormat(
            "Error closing position:" +
            "\nSymbol: %s" +
            "\nTicket: %d" +
            "\nAttempt: %d/%d" +
            "\nError: %s" +
            "\nSeverity: %s",
            symbol, ticket, attempt, totalTries,
            ErrorDescription(error), severity));
    }
    
    // Handle specific errors
    switch (error) {
        case ERR_TRADE_CONTEXT_BUSY:
            Sleep(1000);
            RefreshRates();
            break;
            
        case ERR_INVALID_PRICE:
        case ERR_REQUOTE:
            RefreshRates();
            break;
            
        case ERR_TOO_MANY_REQUESTS:
            Sleep(2000);
            break;
            
        case ERR_TRADE_TIMEOUT:
            Sleep(5000);
            RefreshRates();
            break;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Process individual close operation                                 |
//+------------------------------------------------------------------+
bool ProcessClose(int ticket, int attempt, int totalTries) {
    if (!OrderSelect(ticket, SELECT_BY_TICKET)) {
        LogError(StringFormat("Failed to select order %d: %s", 
            ticket, ErrorDescription(GetLastError())));
        return false;
    }

    string symbol = OrderSymbol();
    int type = OrderType();
    double lots = OrderLots();
    double openPrice = OrderOpenPrice();
    
    // Get instrument specifications
    int digits = GetSymbolDigits(symbol);
    double contractSize = GetContractSize(symbol);
    bool isCryptoPair = (StringFind(symbol, "BTC") >= 0 || 
                        StringFind(symbol, "ETH") >= 0 || 
                        StringFind(symbol, "LTC") >= 0);
    bool isJPYPair = (StringFind(symbol, "JPY") >= 0);
    
    // Calculate slippage based on instrument type
    int currentSlippage = isCryptoPair ? MAX_SLIPPAGE * 2 : MAX_SLIPPAGE;

    RefreshRates();
    double closePrice = type == OP_BUY ? 
                       MarketInfo(symbol, MODE_BID) : 
                       MarketInfo(symbol, MODE_ASK);
    
    // Calculate potential profit/loss before close
    double pipValue = isJPYPair ? 
                     MarketInfo(symbol, MODE_TICKVALUE) * 100 : 
                     MarketInfo(symbol, MODE_TICKVALUE) * 10;
    double potentialPL = OrderProfit() + OrderSwap() + OrderCommission();
    
    LogTrade(StringFormat(
        "Attempting position close:" +
        "\nTicket: %d" +
        "\nSymbol: %s" +
        "\nType: %s" +
        "\nLots: %.2f" +
        "\nContract Size: %.2f" +
        "\nOpen Price: %.*f" +
        "\nClose Price: %.*f" +
        "\nPotential P/L: %.2f" +
        "\nAttempt: %d/%d",
        ticket,
        symbol,
        type == OP_BUY ? "BUY" : "SELL",
        lots,
        contractSize,
        digits, openPrice,
        digits, closePrice,
        potentialPL,
        attempt,
        totalTries
    ));

    bool success = OrderClose(ticket, lots, closePrice, currentSlippage, clrRed);
    
    if (success) {
        // Calculate final profit/loss details
        double actualPL = OrderProfit() + OrderSwap() + OrderCommission();
        double slippage = MathAbs(closePrice - OrderClosePrice()) / 
                         (isJPYPair ? 0.01 : 0.0001);
        
        LogTrade(StringFormat(
            "Position closed successfully:" +
            "\nTicket: %d" +
            "\nSymbol: %s" +
            "\nProfit/Loss: %.2f" +
            "\nSlippage: %.1f pips" +
            "\nAttempts: %d",
            ticket,
            symbol,
            actualPL,
            slippage,
            attempt
        ));
        
        // Record the closed trade
        RecordClosedTrade(symbol, type == OP_BUY ? "BUY" : "SELL", actualPL);
        return true;
    }
    
    // Handle close failure
    int error = GetLastError();
    string severity = GetErrorSeverity(error);
    
    if (severity == "CRITICAL") {
        LogError(StringFormat(
            "Critical error closing position:" +
            "\nSymbol: %s" +
            "\nTicket: %d" +
            "\nAttempt: %d/%d" +
            "\nError: %s (%d)" +
            "\nSeverity: %s",
            symbol,
            ticket,
            attempt,
            totalTries,
            ErrorDescription(error),
            error,
            severity
        ));
    } else {
        LogWarning(StringFormat(
            "Error closing position:" +
            "\nSymbol: %s" +
            "\nTicket: %d" +
            "\nAttempt: %d/%d" +
            "\nError: %s (%d)" +
            "\nSeverity: %s",
            symbol,
            ticket,
            attempt,
            totalTries,
            ErrorDescription(error),
            error,
            severity
        ));
    }
    
    // Handle specific error cases
    switch (error) {
        case ERR_TRADE_CONTEXT_BUSY:
            Sleep(1000);
            RefreshRates();
            break;
            
        case ERR_INVALID_PRICE:
        case ERR_REQUOTE:
            RefreshRates();
            break;
            
        case ERR_TOO_MANY_REQUESTS:
            Sleep(2000);
            break;
            
        case ERR_TRADE_TIMEOUT:
            Sleep(5000);
            RefreshRates();
            break;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Check if symbol has open position                                 |
//+------------------------------------------------------------------+
bool HasOpenPosition(string symbol) {
    int total = 0;
    double totalVolume = 0;
    int buyPositions = 0;
    int sellPositions = 0;
    double buyVolume = 0;
    double sellVolume = 0;
    
    // Get instrument specifications
    double contractSize = GetContractSize(symbol);
    bool isCryptoPair = (StringFind(symbol, "BTC") >= 0 || 
                        StringFind(symbol, "ETH") >= 0 || 
                        StringFind(symbol, "LTC") >= 0);
    int digits = GetSymbolDigits(symbol);

    for (int i = 0; i < OrdersTotal(); i++) {
        if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
            LogError(StringFormat(
                "Failed to select order %d: %s",
                i, ErrorDescription(GetLastError())
            ));
            continue;
        }

        if (OrderSymbol() == symbol && 
            (OrderType() == OP_BUY || OrderType() == OP_SELL)) {
            
            total++;
            double lots = OrderLots();
            totalVolume += lots;
            
            if (OrderType() == OP_BUY) {
                buyPositions++;
                buyVolume += lots;
            } else {
                sellPositions++;
                sellVolume += lots;
            }
        }
    }

    if (total > 0) {
        // Calculate position values
        double currentPrice = MarketInfo(symbol, MODE_BID);
        double totalValue = currentPrice * totalVolume * contractSize;
        
        LogDebug(StringFormat(
            "Open Position Details [%s]:" +
            "\nTotal Positions: %d" +
            "\nBuy Positions: %d (%.2f lots)" +
            "\nSell Positions: %d (%.2f lots)" +
            "\nTotal Volume: %.2f lots" +
            "\nPosition Value: $%.2f" +
            "\nContract Size: %.2f",
            symbol,
            total,
            buyPositions, buyVolume,
            sellPositions, sellVolume,
            totalVolume,
            totalValue,
            contractSize
        ));

        return true;
    }

    return false;
}

//+------------------------------------------------------------------+
//| Get detailed position information                                  |
//+------------------------------------------------------------------+
bool GetPositionDetails(string symbol, int &positionCount, double &totalVolume,
                       int &buyCount, int &sellCount, double &avgPrice) {
    // Initialize values
    positionCount = 0;
    totalVolume = 0;
    buyCount = 0;
    sellCount = 0;
    double weightedPrice = 0;
    
    // Get instrument specifications
    double contractSize = GetContractSize(symbol);
    int digits = GetSymbolDigits(symbol);
    bool isCryptoPair = (StringFind(symbol, "BTC") >= 0 || 
                        StringFind(symbol, "ETH") >= 0 || 
                        StringFind(symbol, "LTC") >= 0);
    bool isJPYPair = (StringFind(symbol, "JPY") >= 0);
    
    // Position tracking variables
    double totalBuyValue = 0;
    double totalSellValue = 0;
    double buyVolume = 0;
    double sellVolume = 0;
    double totalMarginUsed = 0;
    double unrealizedPL = 0;
    double maxDrawdown = 0;

    for (int i = 0; i < OrdersTotal(); i++) {
        if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
            LogError(StringFormat(
                "Failed to select order %d: %s",
                i,
                ErrorDescription(GetLastError())
            ));
            continue;
        }

        if (OrderSymbol() == symbol &&
            (OrderType() == OP_BUY || OrderType() == OP_SELL)) {
            
            positionCount++;
            double lots = OrderLots();
            totalVolume += lots;
            double openPrice = OrderOpenPrice();
            weightedPrice += openPrice * lots;
            
            // Calculate position values
            double positionValue = lots * contractSize * openPrice;
            double marginUsed = isCryptoPair ? 
                              (positionValue * (StringFind(symbol, "LTC") >= 0 ? 
                               CRYPTO_MARGIN_PERCENT_LTC : CRYPTO_MARGIN_PERCENT_DEFAULT)) :
                              (positionValue * FOREX_MARGIN_PERCENT);
            
            totalMarginUsed += marginUsed;
            
            // Track position type
            if (OrderType() == OP_BUY) {
                buyCount++;
                buyVolume += lots;
                totalBuyValue += positionValue;
            } else {
                sellCount++;
                sellVolume += lots;
                totalSellValue += positionValue;
            }
            
            // Track P/L and drawdown
            double positionPL = OrderProfit() + OrderSwap() + OrderCommission();
            unrealizedPL += positionPL;
            
            if (positionPL < 0) {
                maxDrawdown = MathMax(maxDrawdown, MathAbs(positionPL));
            }
        }
    }

    if (positionCount > 0) {
        avgPrice = weightedPrice / totalVolume;
        
        // Calculate current position metrics
        double currentBid = MarketInfo(symbol, MODE_BID);
        double currentAsk = MarketInfo(symbol, MODE_ASK);
        double spread = currentAsk - currentBid;
        double totalValue = currentBid * totalVolume * contractSize;
        
        // Calculate pip values for forex
        double pipValue = 0;
        if (!isCryptoPair) {
            pipValue = MarketInfo(symbol, MODE_TICKVALUE) * (isJPYPair ? 100 : 10);
        }
        
        LogDebug(StringFormat(
            "Position Details [%s]:" +
            "\nPosition Summary:" +
            "\n  Total Positions: %d" +
            "\n  Buy Positions: %d (%.2f lots, $%.2f)" +
            "\n  Sell Positions: %d (%.2f lots, $%.2f)" +
            "\n  Total Volume: %.2f lots" +
            "\nPrice Information:" +
            "\n  Average Entry: %.*f" +
            "\n  Current Bid: %.*f" +
            "\n  Current Ask: %.*f" +
            "\n  Spread: %.*f" +
            "\nValue Metrics:" +
            "\n  Total Value: $%.2f" +
            "\n  Margin Used: $%.2f" +
            "\n  Unrealized P/L: $%.2f" +
            "\n  Max Drawdown: $%.2f" +
            "\nContract Specifications:" +
            "\n  Contract Size: %.2f" +
            "\n  Margin Requirement: %.2f%%" +
            "%s",
            symbol,
            positionCount,
            buyCount, buyVolume, totalBuyValue,
            sellCount, sellVolume, totalSellValue,
            totalVolume,
            digits, avgPrice,
            digits, currentBid,
            digits, currentAsk,
            digits, spread,
            totalValue,
            totalMarginUsed,
            unrealizedPL,
            maxDrawdown,
            contractSize,
            (isCryptoPair ? 
             (StringFind(symbol, "LTC") >= 0 ? 
              CRYPTO_MARGIN_PERCENT_LTC : CRYPTO_MARGIN_PERCENT_DEFAULT) : 
             FOREX_MARGIN_PERCENT) * 100,
            isCryptoPair ? "" : StringFormat("\n  Pip Value: $%.2f", pipValue)
        ));

        return true;
    }

    return false;
}

//+------------------------------------------------------------------+
//| Helper function to extract JSON values                            |
//+------------------------------------------------------------------+
string GetJsonValue(string &json, string key) {
  string search = "\"" + key + "\"";
  int keyStart = StringFind(json, search);
  if (keyStart == -1) return "";

  // Find the start of the value (after : and any whitespace)
  int valueStart = keyStart + StringLen(search);
  while (valueStart < StringLen(json) &&
         (StringGetChar(json, valueStart) == ' ' ||
          StringGetChar(json, valueStart) == ':')) {
    valueStart++;
  }

  // Check if value is a string (starts with quote)
  bool isString = StringGetChar(json, valueStart) == '"';

  if (isString) {
    valueStart++;  // Skip the opening quote
    int valueEnd = StringFind(json, "\"", valueStart);
    if (valueEnd == -1) return "";
    return StringSubstr(json, valueStart, valueEnd - valueStart);
  } else {
    // Handle numeric or other non-string values
    int valueEnd = StringFind(json, ",", valueStart);
    if (valueEnd == -1) valueEnd = StringFind(json, "}", valueStart);
    if (valueEnd == -1) return "";
    return StringSubstr(json, valueStart, valueEnd - valueStart);
  }
}

//+------------------------------------------------------------------+
//| Get detailed error description                                     |
//+------------------------------------------------------------------+
string ErrorDescription(int error_code) {
  string error_string;

  switch (error_code) {
    // Custom Error Messages
    case ERR_CUSTOM_START:
      error_string = "Custom error";
      break;
    case ERR_CUSTOM_START + 1:
      error_string = "Resource not found";
      break;
    case ERR_CUSTOM_START + 2:
      error_string = "Authorization error";
      break;
    case ERR_CUSTOM_START + 3:
      error_string = "Object already exists";
      break;
    case ERR_CUSTOM_START + 4:
      error_string = "Object does not exist";
      break;

    default:
      error_string = StringFormat("Unknown error (%d)", error_code);
      break;
  }

  return StringFormat("Error %d: %s", error_code, error_string);
}

//+------------------------------------------------------------------+
//| Get error severity level                                           |
//+------------------------------------------------------------------+
string GetErrorSeverity(int error_code) {
  switch (error_code) {
    // Critical Errors
    case ERR_CUSTOM_START + 1:
    case ERR_CUSTOM_START + 2:
      return "CRITICAL";

    // Serious Errors
    case ERR_CUSTOM_START + 3:
    case ERR_CUSTOM_START + 4:
      return "SERIOUS";

    default:
      return "UNKNOWN";
  }
}

//+------------------------------------------------------------------+
//| Check if market is open for trading                               |
//+------------------------------------------------------------------+
bool IsMarketOpen(string symbol) {
    datetime symbolTime = (datetime)MarketInfo(symbol, MODE_TIME);
    
    // Check server connectivity
    if (symbolTime == 0) {
        static datetime lastServerError = 0;
        if (TimeCurrent() - lastServerError >= 300) {  // Log every 5 minutes
            LogError(StringFormat("Cannot get market time for %s", symbol));
            lastServerError = TimeCurrent();
        }
        return false;
    }
    
    bool isCryptoPair = (StringFind(symbol, "BTC") >= 0 || 
                        StringFind(symbol, "ETH") >= 0 || 
                        StringFind(symbol, "LTC") >= 0);
    
    // Get current server time
    datetime serverTime = TimeCurrent();
    int currentDayOfWeek = TimeDayOfWeek(serverTime);
    
    // Check holidays first
    if (!isCryptoPair && IsForexHoliday(serverTime)) {
        LogDebug(StringFormat("Market closed - Holiday (%s)", symbol));
        return false;
    }
    
    // Weekend check (except for crypto)
    if (!isCryptoPair && (currentDayOfWeek == SATURDAY || currentDayOfWeek == SUNDAY)) {
        LogDebug(StringFormat("Market closed - Weekend (%s)", symbol));
        return false;
    }
    
    // Check trading hours based on instrument type
    if (isCryptoPair) {
        // Crypto markets trade 24/7
        return true;
    } else {
        // Verify spread for forex pairs
        double currentSpread = MarketInfo(symbol, MODE_SPREAD) * MarketInfo(symbol, MODE_POINT);
        double maxAllowedSpread = StringFind(symbol, "JPY") >= 0 ? 0.05 : 0.0005;  // 5 pips
        
        if (currentSpread > maxAllowedSpread) {
            LogWarning(StringFormat(
                "High spread detected for %s: %.5f (Max: %.5f)",
                symbol, currentSpread, maxAllowedSpread
            ));
        }
        
        // Check if forex market session is active
        return IsMarketSessionActive(symbol);
    }
}

//+------------------------------------------------------------------+
//| Check if market session is active                                  |
//+------------------------------------------------------------------+
bool IsMarketSessionActive(string symbol) {
    // Crypto pairs trade 24/7
    if (StringFind(symbol, "BTC") >= 0 || 
        StringFind(symbol, "ETH") >= 0 || 
        StringFind(symbol, "LTC") >= 0) {
        return true;
    }

    datetime serverTime = TimeCurrent();
    int serverHour = TimeHour(serverTime);
    
    // Define trading sessions (server time)
    bool isAsianSession = (serverHour >= 22 || serverHour < 8);    // 22:00 - 08:00
    bool isLondonSession = (serverHour >= 8 && serverHour < 16);   // 08:00 - 16:00
    bool isNewYorkSession = (serverHour >= 13 && serverHour < 22); // 13:00 - 22:00
    
    // Major session overlaps
    bool isLondonNYOverlap = (serverHour >= 13 && serverHour < 16); // London/NY
    bool isAsianLondonOverlap = (serverHour >= 7 && serverHour < 9); // Asian/London
    
    // Get pair type for specific session handling
    bool isJPYPair = (StringFind(symbol, "JPY") >= 0);
    bool isGBPPair = (StringFind(symbol, "GBP") >= 0);
    bool isEURPair = (StringFind(symbol, "EUR") >= 0);
    
    // Calculate liquidity status
    string currentSession = "";
    string liquidityLevel = "Normal";
    
    if (isLondonNYOverlap) {
        currentSession = "London/New York Overlap";
        liquidityLevel = "High";
    } else if (isAsianLondonOverlap) {
        currentSession = "Asian/London Overlap";
        liquidityLevel = "High";
    } else if (isLondonSession) {
        currentSession = "London";
        liquidityLevel = "High";
    } else if (isNewYorkSession) {
        currentSession = "New York";
        liquidityLevel = "High";
    } else if (isAsianSession) {
        currentSession = "Asian";
        liquidityLevel = isLondonSession ? "High" : "Moderate";
    } else {
        currentSession = "Off-Hours";
        liquidityLevel = "Low";
        
        // Log off-hours trading attempt
        LogWarning(StringFormat(
            "Trading attempt during off-hours for %s",
            symbol
        ));
        return false;
    }
    
    // Log session information
    LogDebug(StringFormat(
        "Session Status for %s:" +
        "\nCurrent Session: %s" +
        "\nLiquidity Level: %s" +
        "\nTime: %s" +
        "\nPair Type: %s",
        symbol,
        currentSession,
        liquidityLevel,
        TimeToString(serverTime),
        isJPYPair ? "JPY" : (isGBPPair ? "GBP" : (isEURPair ? "EUR" : "Other"))
    ));
    
    // Specific pair warnings
    if (isJPYPair && !isAsianSession && !isAsianLondonOverlap) {
        LogWarning(StringFormat(
            "Trading JPY pair outside Asian session: %s",
            symbol
        ));
    }
    if (isGBPPair && !isLondonSession && !isLondonNYOverlap) {
        LogWarning(StringFormat(
            "Trading GBP pair outside London session: %s",
            symbol
        ));
    }
    if (isEURPair && !isLondonSession && !isLondonNYOverlap) {
        LogWarning(StringFormat(
            "Trading EUR pair outside European session: %s",
            symbol
        ));
    }
    
    // Determine if trading should be allowed
    bool sessionAllowed = false;
    
    if (ALLOW_SESSION_OVERLAP && (isLondonNYOverlap || isAsianLondonOverlap)) {
        sessionAllowed = true;  // Always allow during major overlaps if enabled
    } else {
        sessionAllowed = (isAsianSession && TRADE_ASIAN_SESSION) ||
                        (isLondonSession && TRADE_LONDON_SESSION) ||
                        (isNewYorkSession && TRADE_NEWYORK_SESSION);
    }
    
    return sessionAllowed;
}

//+------------------------------------------------------------------+
//| Check if date is a forex market holiday                           |
//+------------------------------------------------------------------+
bool IsForexHoliday(datetime serverTime) {
  int year = TimeYear(serverTime);
  int month = TimeMonth(serverTime);
  int day = TimeDay(serverTime);
  int dayOfWeek = TimeDayOfWeek(serverTime);

  // New Year's Eve and New Year's Day
  if ((month == 12 && day == 31) || (month == 1 && day == 1)) {
    LogDebug("Forex Holiday: New Year's");
    return true;
  }

  // Christmas and Boxing Day
  if (month == 12 && (day == 24 || day == 25 || day == 26)) {
    LogDebug("Forex Holiday: Christmas Period");
    return true;
  }

  // Fixed Date Holidays
  if ((month == 1 && day == 1) ||    // New Year's Day
      (month == 5 && day == 1) ||    // Labor Day (Many European Markets)
      (month == 7 && day == 4) ||    // Independence Day (US Markets)
      (month == 12 && day == 25) ||  // Christmas
      (month == 12 && day == 26)) {  // Boxing Day
    LogDebug("Forex Holiday: Fixed Date Holiday");
    return true;
  }

  // US Holidays (affecting major forex trading)
  // Martin Luther King Jr. Day (Third Monday in January)
  if (month == 1 && dayOfWeek == MONDAY && day >= 15 && day <= 21) {
    LogDebug("Forex Holiday: Martin Luther King Jr. Day");
    return true;
  }

  // Presidents Day (Third Monday in February)
  if (month == 2 && dayOfWeek == MONDAY && day >= 15 && day <= 21) {
    LogDebug("Forex Holiday: Presidents Day");
    return true;
  }

  // Memorial Day (Last Monday in May)
  if (month == 5 && dayOfWeek == MONDAY && day >= 25 && day <= 31) {
    LogDebug("Forex Holiday: Memorial Day");
    return true;
  }

  // Independence Day (July 4 - if weekend, observed on closest weekday)
  if (month == 7) {
    if (day == 4 || (day == 3 && dayOfWeek == FRIDAY) ||
        (day == 5 && dayOfWeek == MONDAY)) {
      LogDebug("Forex Holiday: Independence Day");
      return true;
    }
  }

  // Labor Day US (First Monday in September)
  if (month == 9 && dayOfWeek == MONDAY && day <= 7) {
    LogDebug("Forex Holiday: Labor Day (US)");
    return true;
  }

  // Columbus Day (Second Monday in October)
  if (month == 10 && dayOfWeek == MONDAY && day >= 8 && day <= 14) {
    LogDebug("Forex Holiday: Columbus Day");
    return true;
  }

  // Veterans Day (November 11)
  if (month == 11 && day == 11) {
    LogDebug("Forex Holiday: Veterans Day");
    return true;
  }

  // Thanksgiving (Fourth Thursday in November) and Black Friday
  if (month == 11 && dayOfWeek == THURSDAY && day >= 22 && day <= 28) {
    LogDebug("Forex Holiday: Thanksgiving");
    return true;
  }
  if (month == 11 && dayOfWeek == FRIDAY && day >= 23 && day <= 29) {
    LogDebug("Forex Holiday: Black Friday");
    return true;
  }

  // Good Friday (approximate - varies each year)
  // Note: This is a rough approximation. Good Friday can occur between March 20
  // and April 23
  if ((month == 3 || month == 4) && dayOfWeek == FRIDAY) {
    int easterMonth = GetEasterMonth(year);
    int easterDay = GetEasterDay(year);

    // Good Friday is 2 days before Easter
    if (month == easterMonth && day == easterDay - 2) {
      LogDebug("Forex Holiday: Good Friday");
      return true;
    }
  }

  // Easter Monday
  if ((month == 3 || month == 4) && dayOfWeek == MONDAY) {
    int easterMonth = GetEasterMonth(year);
    int easterDay = GetEasterDay(year);

    if (month == easterMonth && day == easterDay + 1) {
      LogDebug("Forex Holiday: Easter Monday");
      return true;
    }
  }

  // Bank Holidays (UK)
  // Early May Bank Holiday (First Monday in May)
  if (month == 5 && dayOfWeek == MONDAY && day <= 7) {
    LogDebug("Forex Holiday: Early May Bank Holiday (UK)");
    return true;
  }

  // Spring Bank Holiday (Last Monday in May)
  if (month == 5 && dayOfWeek == MONDAY && day >= 25) {
    LogDebug("Forex Holiday: Spring Bank Holiday (UK)");
    return true;
  }

  // Summer Bank Holiday (Last Monday in August)
  if (month == 8 && dayOfWeek == MONDAY && day >= 25) {
    LogDebug("Forex Holiday: Summer Bank Holiday (UK)");
    return true;
  }

  return false;
}

//+------------------------------------------------------------------+
//| Helper function to get Easter month for a given year              |
//+------------------------------------------------------------------+
int GetEasterMonth(int year) {
  // Simplified Meeus/Jones/Butcher algorithm
  int a = year % 19;
  int b = year / 100;
  int c = year % 100;
  int d = b / 4;
  int e = b % 4;
  int f = (b + 8) / 25;
  int g = (b - f + 1) / 3;
  int h = (19 * a + b - d - g + 15) % 30;
  int i = c / 4;
  int k = c % 4;
  int l = (32 + 2 * e + 2 * i - h - k) % 7;
  int m = (a + 11 * h + 22 * l) / 451;

  return (h + l - 7 * m + 114) / 31;
}

//+------------------------------------------------------------------+
//| Helper function to get Easter day for a given year                |
//+------------------------------------------------------------------+
int GetEasterDay(int year) {
  // Simplified Meeus/Jones/Butcher algorithm
  int a = year % 19;
  int b = year / 100;
  int c = year % 100;
  int d = b / 4;
  int e = b % 4;
  int f = (b + 8) / 25;
  int g = (b - f + 1) / 3;
  int h = (19 * a + b - d - g + 15) % 30;
  int i = c / 4;
  int k = c % 4;
  int l = (32 + 2 * e + 2 * i - h - k) % 7;
  int m = (a + 11 * h + 22 * l) / 451;

  return ((h + l - 7 * m + 114) % 31) + 1;
}

//+------------------------------------------------------------------+
//| Helper function to remove "+" suffix from symbol                  |
//+------------------------------------------------------------------+
string GetBaseSymbol(string symbol) {
    int plusPos = StringFind(symbol, "+");
    if (plusPos != -1) {
        string baseSymbol = StringSubstr(symbol, 0, plusPos);
        
        // Validate resulting symbol
        if (StringLen(baseSymbol) >= 6) {
            LogDebug(StringFormat(
                "Base symbol extracted: %s from %s",
                baseSymbol,
                symbol
            ));
            return baseSymbol;
        } else {
            LogError(StringFormat(
                "Invalid base symbol length: %s from %s",
                baseSymbol,
                symbol
            ));
            return symbol;
        }
    }
    return symbol;
}

// Helper function to calculate total account risk
double CalculateTotalAccountRisk() {
    double totalRisk = 0;

    // Position metrics tracking
    struct RiskMetrics {
        int positionCount;
        double totalLots;
        double totalRisk;
        double usedMargin;
        double maxDrawdown;
        double highestRisk;
    };
    
    RiskMetrics cryptoMetrics = {0, 0, 0, 0, 0, 0};
    RiskMetrics forexMetrics = {0, 0, 0, 0, 0, 0};

    // Track individual currency risks
    struct CurrencyRisk {
        string symbol;
        double risk;
        double percentage;
    };
    CurrencyRisk currencyRisks[];
    int riskCount = 0;

    for (int i = 0; i < OrdersTotal(); i++) {
        if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
            LogError(StringFormat(
                "Failed to select order %d: %s",
                i,
                ErrorDescription(GetLastError())
            ));
            continue;
        }

        string symbol = OrderSymbol();
        bool isCryptoPair = (StringFind(symbol, "BTC") >= 0 || 
                           StringFind(symbol, "ETH") >= 0 || 
                           StringFind(symbol, "LTC") >= 0);
        bool isJPYPair = (StringFind(symbol, "JPY") >= 0);
        
        // Get instrument specifications
        int digits = GetSymbolDigits(symbol);
        double contractSize = GetContractSize(symbol);
        double marginPercent = GetMarginPercent(symbol);
        
        // Get position details
        double lots = OrderLots();
        double openPrice = OrderOpenPrice();
        double stopLoss = OrderStopLoss();
        double currentPrice = OrderType() == OP_BUY ? 
                            MarketInfo(symbol, MODE_BID) : 
                            MarketInfo(symbol, MODE_ASK);

        if (stopLoss == 0) {
            LogWarning(StringFormat(
                "Position without stop loss found:" +
                "\nTicket: %d" +
                "\nSymbol: %s" +
                "\nType: %s",
                OrderTicket(),
                symbol,
                OrderType() == OP_BUY ? "BUY" : "SELL"
            ));
            continue;
        }

        // Calculate position risk
        double positionRisk = 0;
        double unrealizedPL = OrderProfit() + OrderSwap() + OrderCommission();
        double positionValue = lots * contractSize * openPrice;
        double currentValue = lots * contractSize * currentPrice;
        
        if (isCryptoPair) {
            // Crypto risk calculation
            double actualRiskDistance;
            if (OrderType() == OP_BUY) {
                actualRiskDistance = currentPrice > stopLoss ? 
                                   0 : MathAbs(currentPrice - stopLoss);
            } else {
                actualRiskDistance = currentPrice < stopLoss ? 
                                   0 : MathAbs(currentPrice - stopLoss);
            }
            
            // Calculate risk amount considering contract size
            positionRisk = actualRiskDistance * lots * contractSize;
            
            // Update crypto metrics
            cryptoMetrics.positionCount++;
            cryptoMetrics.totalLots += lots;
            cryptoMetrics.totalRisk += positionRisk;
            cryptoMetrics.usedMargin += positionValue * marginPercent;
            cryptoMetrics.maxDrawdown = MathMax(
                cryptoMetrics.maxDrawdown,
                unrealizedPL < 0 ? MathAbs(unrealizedPL) : 0
            );
            cryptoMetrics.highestRisk = MathMax(
                cryptoMetrics.highestRisk,
                positionRisk
            );

            LogDebug(StringFormat(
                "Crypto Risk Calculation [%s]:" +
                "\nType: %s" +
                "\nContract Size: %.2f" +
                "\nCurrent Price: %.*f" +
                "\nStop Loss: %.*f" +
                "\nRisk Distance: %.*f" +
                "\nLots: %.4f" +
                "\nPosition Risk: $%.2f" +
                "\nMargin Used: $%.2f",
                symbol,
                OrderType() == OP_BUY ? "BUY" : "SELL",
                contractSize,
                digits, currentPrice,
                digits, stopLoss,
                digits, actualRiskDistance,
                lots,
                positionRisk,
                positionValue * marginPercent
            ));
        } else {
            // Forex risk calculation
            double pipSize = isJPYPair ? 0.01 : 0.0001;
            double pipValue = MarketInfo(symbol, MODE_TICKVALUE) * 
                            (isJPYPair ? 100 : 10);

            // Calculate actual risk distance based on current price
            double actualRiskDistance;
            if (OrderType() == OP_BUY) {
                actualRiskDistance = currentPrice > stopLoss ? 
                                   0 : MathAbs(currentPrice - stopLoss);
            } else {
                actualRiskDistance = currentPrice < stopLoss ? 
                                   0 : MathAbs(currentPrice - stopLoss);
            }

            double riskPips = actualRiskDistance / pipSize;
            positionRisk = riskPips * pipValue * lots;
            
            // Update forex metrics
            forexMetrics.positionCount++;
            forexMetrics.totalLots += lots;
            forexMetrics.totalRisk += positionRisk;
            forexMetrics.usedMargin += positionValue * marginPercent;
            forexMetrics.maxDrawdown = MathMax(
                forexMetrics.maxDrawdown,
                unrealizedPL < 0 ? MathAbs(unrealizedPL) : 0
            );
            forexMetrics.highestRisk = MathMax(
                forexMetrics.highestRisk,
                positionRisk
            );

            LogDebug(StringFormat(
                "Forex Risk Calculation [%s]:" +
                "\nType: %s" +
                "\nContract Size: %.2f" +
                "\nCurrent Price: %.*f" +
                "\nStop Loss: %.*f" +
                "\nPips at Risk: %.1f" +
                "\nPip Value: %.5f" +
                "\nLots: %.2f" +
                "\nPosition Risk: $%.2f" +
                "\nMargin Used: $%.2f",
                symbol,
                OrderType() == OP_BUY ? "BUY" : "SELL",
                contractSize,
                digits, currentPrice,
                digits, stopLoss,
                riskPips,
                pipValue,
                lots,
                positionRisk,
                positionValue * marginPercent
            ));
        }

        // Track individual currency risks
        ArrayResize(currencyRisks, riskCount + 1);
        currencyRisks[riskCount].symbol = symbol;
        currencyRisks[riskCount].risk = positionRisk;
        currencyRisks[riskCount].percentage = 
            (positionRisk / AccountBalance()) * 100;
        riskCount++;

        totalRisk += positionRisk;
    }

    // Calculate overall risk metrics
    double accountBalance = AccountBalance();
    double totalRiskPercent = (totalRisk / accountBalance) * 100;
    double marginLevel = AccountMargin() > 0 ? 
                        (AccountEquity() / AccountMargin() * 100) : 0;

    // Log comprehensive risk summary
    LogDebug(StringFormat(
        "Total Account Risk Summary:" +
        "\nAccount Metrics:" +
        "\n  Balance: $%.2f" +
        "\n  Equity: $%.2f" +
        "\n  Total Risk: $%.2f (%.2f%%)" +
        "\n  Margin Level: %.2f%%" +
        "\nCrypto Positions:" +
        "\n  Count: %d" +
        "\n  Total Lots: %.4f" +
        "\n  Risk Amount: $%.2f" +
        "\n  Used Margin: $%.2f" +
        "\n  Max Drawdown: $%.2f" +
        "\n  Highest Risk: $%.2f" +
        "\nForex Positions:" +
        "\n  Count: %d" +
        "\n  Total Lots: %.2f" +
        "\n  Risk Amount: $%.2f" +
        "\n  Used Margin: $%.2f" +
        "\n  Max Drawdown: $%.2f" +
        "\n  Highest Risk: $%.2f",
        accountBalance,
        AccountEquity(),
        totalRisk,
        totalRiskPercent,
        marginLevel,
        cryptoMetrics.positionCount,
        cryptoMetrics.totalLots,
        cryptoMetrics.totalRisk,
        cryptoMetrics.usedMargin,
        cryptoMetrics.maxDrawdown,
        cryptoMetrics.highestRisk,
        forexMetrics.positionCount,
        forexMetrics.totalLots,
        forexMetrics.totalRisk,
        forexMetrics.usedMargin,
        forexMetrics.maxDrawdown,
        forexMetrics.highestRisk
    ));

    // Log individual currency risks if multiple positions exist
    if (riskCount > 1) {
        string riskDetails = "Individual Currency Risks:";
        for (int i = 0; i < riskCount; i++) {
            riskDetails += StringFormat(
                "\n  %s: $%.2f (%.2f%%)",
                currencyRisks[i].symbol,
                currencyRisks[i].risk,
                currencyRisks[i].percentage
            );
        }
        LogDebug(riskDetails);
    }

    return totalRisk;
}

//+------------------------------------------------------------------+
// Helper function to validate position risk /
//+------------------------------------------------------------------+
bool ValidatePositionRisk(string symbol, double lots, double entryPrice, double stopLoss) {
    double accountBalance = AccountBalance();
    double stopDistance = MathAbs(entryPrice - stopLoss);
    bool isCryptoPair = (StringFind(symbol, "BTC") >= 0 || 
                        StringFind(symbol, "ETH") >= 0 || 
                        StringFind(symbol, "LTC") >= 0);
    
    int digits = GetSymbolDigits(symbol);
    double contractSize = GetContractSize(symbol);
    double marginPercent = GetMarginPercent(symbol);

    // Validate input parameters
    if (stopDistance <= 0) {
        LogError(StringFormat(
            "Invalid stop distance:" +
            "\nEntry: %.*f" +
            "\nStop: %.*f" +
            "\nDistance: %.*f",
            digits, entryPrice,
            digits, stopLoss,
            digits, stopDistance
        ));
        return false;
    }

    // Calculate position risk
    double positionRisk = CalculateFinalPositionRisk(symbol, lots, entryPrice, stopLoss);

    // Calculate required margin
    double requiredMargin = entryPrice * lots * contractSize * marginPercent;
    double availableMargin = AccountFreeMargin();
    
    // Log risk and margin calculations
    LogDebug(StringFormat(
        "Position Risk Validation:" +
        "\nSymbol: %s" +
        "\nContract Size: %.2f" +
        "\nMargin Requirement: %.2f%%" +
        "\nPosition Risk: $%.2f" +
        "\nRequired Margin: $%.2f" +
        "\nAvailable Margin: $%.2f",
        symbol,
        contractSize,
        marginPercent * 100,
        positionRisk,
        requiredMargin,
        availableMargin
    ));

    // Check margin requirements
    if (requiredMargin > availableMargin * 0.9) { // 90% margin threshold
        LogError(StringFormat(
            "Insufficient margin:" +
            "\nRequired: $%.2f" +
            "\nAvailable: $%.2f",
            requiredMargin,
            availableMargin
        ));
        return false;
    }

    // Calculate risk percentages
    double positionRiskPercent = (positionRisk / accountBalance) * 100;
    double totalRisk = CalculateTotalAccountRisk() + positionRisk;
    double totalRiskPercent = (totalRisk / accountBalance) * 100;

    // Risk threshold checks
    if (positionRiskPercent > (RISK_PERCENT * 2)) {
        LogError(StringFormat(
            "Position risk exceeds limit:" +
            "\nRisk: %.2f%%" +
            "\nMaximum Allowed: %.2f%%",
            positionRiskPercent,
            RISK_PERCENT * 2
        ));
        return false;
    }

    if (totalRiskPercent > (RISK_PERCENT * 3)) {
        LogError(StringFormat(
            "Total account risk exceeds limit:" +
            "\nCurrent Risk: %.2f%%" +
            "\nNew Position Risk: %.2f%%" +
            "\nTotal Risk: %.2f%%" +
            "\nMaximum Allowed: %.2f%%",
            (CalculateTotalAccountRisk() / accountBalance) * 100,
            positionRiskPercent,
            totalRiskPercent,
            RISK_PERCENT * 3
        ));
        return false;
    }

    return true;
}

//+------------------------------------------------------------------+
//| Helper function to monitor risk levels                             |
//+------------------------------------------------------------------+
void MonitorRiskLevels() {
    static datetime lastWarningTime = 0;
    static datetime lastRiskCheck = 0;
    datetime currentTime = TimeCurrent();

    // Calculate key metrics
    double accountBalance = AccountBalance();
    double accountEquity = AccountEquity();
    double totalRisk = CalculateTotalAccountRisk();
    double currentRiskPercent = (totalRisk / accountBalance) * 100;
    double maxAllowedRisk = RISK_PERCENT * 3;
    
    // Track position metrics by instrument type
    struct PositionMetrics {
        int count;
        double totalLots;
        double totalRisk;
        double usedMargin;
        double maxDrawdown;
    };
    PositionMetrics cryptoMetrics = {0, 0, 0, 0, 0};
    PositionMetrics forexMetrics = {0, 0, 0, 0, 0};

    // Analyze all open positions
    for (int i = 0; i < OrdersTotal(); i++) {
        if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;

        string symbol = OrderSymbol();
        bool isCryptoPair = (StringFind(symbol, "BTC") >= 0 || 
                           StringFind(symbol, "ETH") >= 0 || 
                           StringFind(symbol, "LTC") >= 0);
        
        double contractSize = GetContractSize(symbol);
        double marginPercent = GetMarginPercent(symbol);
        int digits = GetSymbolDigits(symbol);
        
        // Calculate position metrics
        double positionValue = OrderLots() * contractSize * OrderOpenPrice();
        double usedMargin = positionValue * marginPercent;
        double unrealizedPL = OrderProfit() + OrderSwap() + OrderCommission();
        double drawdown = unrealizedPL < 0 ? MathAbs(unrealizedPL) : 0;

        double currentRisk = CalculateFinalPositionRisk(
            symbol,
            OrderLots(),
            OrderOpenPrice(),
            OrderStopLoss()
        );

        // Update respective metrics
        if (isCryptoPair) {
            cryptoMetrics.count++;
            cryptoMetrics.totalLots += OrderLots();
            cryptoMetrics.totalRisk += currentRisk;
            cryptoMetrics.usedMargin += usedMargin;
            cryptoMetrics.maxDrawdown = MathMax(cryptoMetrics.maxDrawdown, drawdown);
        } else {
            forexMetrics.count++;
            forexMetrics.totalLots += OrderLots();
            forexMetrics.totalRisk += currentRisk;
            forexMetrics.usedMargin += usedMargin;
            forexMetrics.maxDrawdown = MathMax(forexMetrics.maxDrawdown, drawdown);
        }
    }

    // Risk threshold for warnings (80% of maximum allowed)
    double riskWarningThreshold = maxAllowedRisk * 0.8;
    double marginWarningThreshold = 150.0; // 150% margin level warning

    // Calculate margin level
    double totalMargin = cryptoMetrics.usedMargin + forexMetrics.usedMargin;
    double marginLevel = totalMargin > 0 ? (accountEquity / totalMargin) * 100 : 0;

    // Log comprehensive risk analysis every 5 minutes
    if (currentTime - lastRiskCheck >= 300) {
        LogDebug(StringFormat(
            "Risk Level Monitoring:" +
            "\nAccount Metrics:" +
            "\n  Balance: $%.2f" +
            "\n  Equity: $%.2f" +
            "\n  Total Risk: $%.2f (%.2f%%)" +
            "\n  Margin Level: %.2f%%" +
            "\n  Max Allowed Risk: %.2f%%" +
            "\nCrypto Positions:" +
            "\n  Count: %d" +
            "\n  Total Lots: %.4f" +
            "\n  Risk Amount: $%.2f" +
            "\n  Used Margin: $%.2f" +
            "\n  Max Drawdown: $%.2f" +
            "\nForex Positions:" +
            "\n  Count: %d" +
            "\n  Total Lots: %.2f" +
            "\n  Risk Amount: $%.2f" +
            "\n  Used Margin: $%.2f" +
            "\n  Max Drawdown: $%.2f",
            accountBalance,
            accountEquity,
            totalRisk,
            currentRiskPercent,
            marginLevel,
            maxAllowedRisk,
            cryptoMetrics.count,
            cryptoMetrics.totalLots,
            cryptoMetrics.totalRisk,
            cryptoMetrics.usedMargin,
            cryptoMetrics.maxDrawdown,
            forexMetrics.count,
            forexMetrics.totalLots,
            forexMetrics.totalRisk,
            forexMetrics.usedMargin,
            forexMetrics.maxDrawdown
        ));
        
        lastRiskCheck = currentTime;
    }

    // Issue warnings if needed (every 5 minutes)
    if (currentTime - lastWarningTime >= 300) {
        // Risk level warnings
        if (currentRiskPercent >= riskWarningThreshold) {
            LogWarning(StringFormat(
                "HIGH RISK ALERT:" +
                "\nCurrent Risk: %.2f%%" +
                "\nWarning Level: %.2f%%" +
                "\nMax Allowed: %.2f%%" +
                "\nRisk Amount: $%.2f",
                currentRiskPercent,
                riskWarningThreshold,
                maxAllowedRisk,
                totalRisk
            ));
            lastWarningTime = currentTime;
        }

        // Margin level warning
        if (marginLevel > 0 && marginLevel < marginWarningThreshold) {
            LogWarning(StringFormat(
                "LOW MARGIN LEVEL ALERT:" +
                "\nMargin Level: %.2f%%" +
                "\nWarning Threshold: %.2f%%" +
                "\nEquity: $%.2f" +
                "\nUsed Margin: $%.2f",
                marginLevel,
                marginWarningThreshold,
                accountEquity,
                totalMargin
            ));
        }

        // Drawdown warnings
        double totalDrawdown = cryptoMetrics.maxDrawdown + forexMetrics.maxDrawdown;
        double drawdownPercent = (totalDrawdown / accountBalance) * 100;
        if (drawdownPercent >= 5) {  // 5% drawdown warning
            LogWarning(StringFormat(
                "HIGH DRAWDOWN ALERT:" +
                "\nDrawdown: %.2f%%" +
                "\nDrawdown Amount: $%.2f" +
                "\nCrypto Drawdown: $%.2f" +
                "\nForex Drawdown: $%.2f",
                drawdownPercent,
                totalDrawdown,
                cryptoMetrics.maxDrawdown,
                forexMetrics.maxDrawdown
            ));
        }
    }
}

//+------------------------------------------------------------------+
//| Emergency close check                                             |
//+------------------------------------------------------------------+
void CheckEmergencyClose() {
    for (int i = 0; i < OrdersTotal(); i++) {
        if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;

        string symbol = OrderSymbol();
        int digits = GetSymbolDigits(symbol);
        bool isCryptoPair = (StringFind(symbol, "BTC") >=0 || 
                           StringFind(symbol, "ETH") >= 0 || 
                           StringFind(symbol, "LTC") >= 0);
        bool isJPYPair = (StringFind(symbol, "JPY") >= 0);
        double contractSize = GetContractSize(symbol);
        
        double openPrice = OrderOpenPrice();
        double currentPrice = OrderType() == OP_BUY ? 
                            MarketInfo(symbol, MODE_BID) : 
                            MarketInfo(symbol, MODE_ASK);
        double lots = OrderLots();

        // Calculate position values and losses
        if (isCryptoPair) {
            // Calculate crypto position values
            double positionValue = lots * contractSize * currentPrice;
            double openValue = lots * contractSize * openPrice;
            
            // Calculate loss in monetary terms and percentage
            double unrealizedPL = OrderType() == OP_BUY ? 
                                (currentPrice - openPrice) * lots * contractSize :
                                (openPrice - currentPrice) * lots * contractSize;
            
            double lossPercent = (MathAbs(unrealizedPL) / openValue) * 100;
            
            LogDebug(StringFormat(
                "Crypto Emergency Check [%s]:" +
                "\nType: %s" +
                "\nOpen Value: $%.2f" +
                "\nCurrent Value: $%.2f" +
                "\nUnrealized P/L: $%.2f" +
                "\nLoss Percent: %.2f%%" +
                "\nEmergency Threshold: %.2f%%",
                symbol,
                OrderType() == OP_BUY ? "BUY" : "SELL",
                openValue,
                positionValue,
                unrealizedPL,
                lossPercent,
                EMERGENCY_CLOSE_PERCENT
            ));

            // Emergency close check
            if (unrealizedPL < 0 && lossPercent >= EMERGENCY_CLOSE_PERCENT) {
                LogError(StringFormat(
                    "CRYPTO EMERGENCY CLOSE TRIGGERED:" +
                    "\nSymbol: %s" +
                    "\nTicket: %d" +
                    "\nLoss: %.2f%%" +
                    "\nLoss Amount: $%.2f",
                    symbol,
                    OrderTicket(),
                    lossPercent,
                    MathAbs(unrealizedPL)
                ));
                
                ExecuteEmergencyClose(OrderTicket(), symbol);
            }
        } else {
            // Forex position calculations
            double pipSize = isJPYPair ? 0.01 : 0.0001;
            double pipValue = MarketInfo(symbol, MODE_TICKVALUE) * (isJPYPair ? 100 : 10);
            
            // Calculate loss in pips
            double lossInPips = OrderType() == OP_BUY ?
                              (openPrice - currentPrice) / pipSize :
                              (currentPrice - openPrice) / pipSize;
                              
            // Calculate monetary loss
            double unrealizedPL = lossInPips * pipValue * lots;
            
            LogDebug(StringFormat(
                "Forex Emergency Check [%s]:" +
                "\nType: %s" +
                "\nLoss Pips: %.1f" +
                "\nUnrealized P/L: $%.2f" +
                "\nEmergency Threshold: %.1f pips",
                symbol,
                OrderType() == OP_BUY ? "BUY" : "SELL",
                lossInPips,
                unrealizedPL,
                FOREX_EMERGENCY_PIPS
            ));

            // Emergency close check
            if (lossInPips >= FOREX_EMERGENCY_PIPS) {
                LogError(StringFormat(
                    "FOREX EMERGENCY CLOSE TRIGGERED:" +
                    "\nSymbol: %s" +
                    "\nTicket: %d" +
                    "\nLoss Pips: %.1f" +
                    "\nLoss Amount: $%.2f",
                    symbol,
                    OrderTicket(),
                    lossInPips,
                    MathAbs(unrealizedPL)
                ));
                
                ExecuteEmergencyClose(OrderTicket(), symbol);
            }
        }
    }
}

// Helper function to execute emergency close
void ExecuteEmergencyClose(int ticket, string symbol) {
    // Set maximum slippage for emergency close
    int emergencySlippage = MAX_SLIPPAGE * 2;  // Double normal slippage for emergency
    
    // Attempt emergency close
    if (!OrderSelect(ticket, SELECT_BY_TICKET)) {
        LogError(StringFormat("Failed to select order %d for emergency close", ticket));
        return;
    }
    
    double lots = OrderLots();
    int type = OrderType();
    double closePrice = type == OP_BUY ? 
                       MarketInfo(symbol, MODE_BID) : 
                       MarketInfo(symbol, MODE_ASK);
    
    for (int attempt = 1; attempt <= MAX_RETRIES; attempt++) {
        bool success = OrderClose(ticket, lots, closePrice, emergencySlippage, clrRed);
        
        if (success) {
            LogTrade(StringFormat(
                "Emergency Close Successful:" +
                "\nTicket: %d" +
                "\nSymbol: %s" +
                "\nLots: %.2f" +
                "\nClose Price: %.5f" +
                "\nAttempt: %d",
                ticket, symbol, lots, closePrice, attempt
            ));
            return;
        }
        
        int error = GetLastError();
        LogWarning(StringFormat(
            "Emergency Close Failed - Attempt %d:" +
            "\nTicket: %d" +
            "\nError: %d (%s)",
            attempt, ticket, error, ErrorDescription(error)
        ));
        
        if (attempt < MAX_RETRIES) {
            Sleep(1000 * attempt);  // Exponential backoff
            RefreshRates();
            closePrice = type == OP_BUY ? 
                        MarketInfo(symbol, MODE_BID) : 
                        MarketInfo(symbol, MODE_ASK);
        }
    }
    
    LogError(StringFormat(
        "Emergency Close Failed After %d Attempts:" +
        "\nTicket: %d" +
        "\nSymbol: %s",
        MAX_RETRIES, ticket, symbol
    ));
}

//+------------------------------------------------------------------+
//| Log Account Performance Metrics                                    |
//+------------------------------------------------------------------+
void LogAccountStatus() {
  string metrics = StringFormat(
      "Account Performance Metrics:" + "\nBalance: %.2f" + "\nEquity: %.2f" +
          "\nFloating P/L: %.2f" + "\nMargin Used: %.2f" +
          "\nFree Margin: %.2f" + "\nMargin Level: %.2f%%",
      AccountBalance(), AccountEquity(), AccountEquity() - AccountBalance(),
      AccountMargin(), AccountFreeMargin(),
      AccountMargin() != 0 ? (AccountEquity() / AccountMargin() * 100) : 0);

  LogInfo(metrics);
}

//+------------------------------------------------------------------+
//| Log Daily Performance Summary                                      |
//+------------------------------------------------------------------+
void LogDailyPerformance() {
  static datetime lastDayChecked = 0;
  datetime currentTime = TimeCurrent();

  // Only log once per day
  if (TimeDay(currentTime) == TimeDay(lastDayChecked)) return;

  double totalProfit = 0;
  int totalTrades = 0;
  int winningTrades = 0;

  // Calculate daily statistics
  for (int i = OrdersHistoryTotal() - 1; i >= 0; i--) {
    if (OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) {
      if (TimeDay(OrderCloseTime()) == TimeDay(currentTime)) {
        totalProfit += OrderProfit() + OrderSwap() + OrderCommission();
        totalTrades++;
        if (OrderProfit() > 0) winningTrades++;
      }
    }
  }

  string summary =
      StringFormat("Daily Performance Summary:" + "\nDate: %s" +
                       "\nTotal Profit/Loss: %.2f" + "\nTotal Trades: %d" +
                       "\nWinning Trades: %d" + "\nWin Rate: %.2f%%",
                   TimeToString(currentTime, TIME_DATE), totalProfit,
                   totalTrades, winningTrades,
                   totalTrades > 0 ? (winningTrades * 100.0 / totalTrades) : 0);

  LogInfo(summary);
  lastDayChecked = currentTime;
}

//+------------------------------------------------------------------+
//| Log Market Conditions                                             |
//+------------------------------------------------------------------+
void LogMarketConditions(string symbol) {
  double spread =
      MarketInfo(symbol, MODE_SPREAD) * MarketInfo(symbol, MODE_POINT);
  string conditions = StringFormat(
      "Market Conditions for %s:" + "\nBid: %.5f" + "\nAsk: %.5f" +
          "\nSpread: %.5f" + "\nDigits: %d" + "\nPip Value: %.5f" +
          "\nMin Lot: %.2f" + "\nMax Lot: %.2f" + "\nLot Step: %.2f",
      symbol, MarketInfo(symbol, MODE_BID), MarketInfo(symbol, MODE_ASK),
      spread, (int)MarketInfo(symbol, MODE_DIGITS),
      MarketInfo(symbol, MODE_TICKVALUE), MarketInfo(symbol, MODE_MINLOT),
      MarketInfo(symbol, MODE_MAXLOT), MarketInfo(symbol, MODE_LOTSTEP));

  LogInfo(conditions, symbol);
}

//+------------------------------------------------------------------+
//| Log Trading Volume                                                |
//+------------------------------------------------------------------+
void LogTradingVolume(string symbol) {
  long currentVolume = (long)iVolume(symbol, PERIOD_CURRENT, 0);
  long previousVolume = (long)iVolume(symbol, PERIOD_CURRENT, 1);

  string volumeInfo =
      StringFormat("Trading Volume for %s:" + "\nCurrent Bar Volume: %I64d" +
                       "\nPrevious Bar Volume: %I64d",
                   symbol, currentVolume, previousVolume);

  LogDebug(volumeInfo, symbol);
}