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
extern string TIMEFRAME = "60";                                               // Timeframe parameter

// Risk Management
extern double RISK_PERCENT = 2.0;                    // Risk percentage per trade
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

    // Initialize symbol info first
    g_symbolInfo = new CSymbolInfo(_Symbol);
    if(g_symbolInfo == NULL) {
        Logger.Error("Failed to initialize SymbolInfo");
        return INIT_FAILED;
    }

    // Initialize RiskManager before TradeManager
    g_riskManager = new CRiskManager(g_symbolInfo, RISK_PERCENT, MAX_ACCOUNT_RISK, MARGIN_BUFFER);
    if(g_riskManager == NULL) {
        Logger.Error("Failed to initialize RiskManager");
        return INIT_FAILED;
    }

    // Now initialize TradeManager with the initialized RiskManager
    g_tradeManager = new CTradeManager(g_symbolInfo, g_riskManager, DEFAULT_SLIPPAGE, MAX_RETRY_ATTEMPTS);
    if(g_tradeManager == NULL) {
        Logger.Error("Failed to initialize TradeManager");
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
       //     Logger.Warning("Trading not currently allowed");
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
            if(TimeCurrent() - lastCheck >= PROFIT_CHECK_INTERVAL) {
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

    // Run checks every RISK_CHECK_INTERVAL minutes
    if(currentTime - lastCheck >= RISK_CHECK_INTERVAL) {
        // Check account status
        if(!g_riskManager.IsMarginSafe()) {
            Logger.Warning("Margin level below safe threshold");
        }

        // Log current market conditions
        string liquidity = g_sessionManager.GetLiquidityLevel();
        // Logger.Debug(StringFormat(
            // "Market Conditions:" +
            // "\nLiquidity: %s" +
            // "\nSpread: %.5f",
            // liquidity,
            // g_symbolInfo.GetSpread()
        // ));

        lastCheck = currentTime;
    }
}

//+------------------------------------------------------------------+
//| Signal processing                                                 |
//+------------------------------------------------------------------+
bool IsTimeToCheck() {
    static datetime lastSignalCheck = 0;
    datetime currentTime = TimeCurrent();

    if(currentTime - lastSignalCheck < SIGNAL_CHECK_INTERVAL) {
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
            if(signal.isExitSignal) {
                ProcessExitSignal(signal);
            } else {
                // Set instrument type based on symbol
                signal.instrumentType = g_symbolInfo.IsCryptoPair() ?
                    INSTRUMENT_CRYPTO : INSTRUMENT_FOREX;
                ExecuteSignal(signal);
            }
        }
    }
}

void ProcessExitSignal(const SignalData& signal) {
    // Find all positions for this symbol
    for(int i = OrdersTotal() - 1; i >= 0; i--) {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
            if(OrderSymbol() == signal.ticker) {
                bool shouldClose = false;
                
                // Check if exit signal matches position direction
                if(OrderType() == OP_BUY && signal.exitType == EXIT_BEARISH) {
                    shouldClose = true;
                    Logger.Debug("Closing BUY position on Bearish Exit signal");
                }
                else if(OrderType() == OP_SELL && signal.exitType == EXIT_BULLISH) {
                    shouldClose = true;
                    Logger.Debug("Closing SELL position on Bullish Exit signal");
                }
                
                if(shouldClose) {
                    g_tradeManager.ClosePosition(OrderTicket(), 
                        StringFormat("Exit Signal: %s", 
                            signal.exitType == EXIT_BEARISH ? "Bearish" : "Bullish"));
                }
            }
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
//| Get description of the MT4 error code                             |
//+------------------------------------------------------------------+
string ErrorDescription(int error_code)
{
   string error_string;
   switch(error_code)
   {
      case 0:   error_string="no error";                                                   break;
      case 1:   error_string="no error, trade conditions not changed";                     break;
      case 2:   error_string="common error";                                              break;
      case 3:   error_string="invalid trade parameters";                                  break;
      case 4:   error_string="trade server is busy";                                      break;
      case 5:   error_string="old version of the client terminal";                        break;
      case 6:   error_string="no connection with trade server";                           break;
      case 7:   error_string="not enough rights";                                         break;
      case 8:   error_string="too frequent requests";                                     break;
      case 9:   error_string="malfunctional trade operation";                            break;
      case 64:  error_string="account disabled";                                          break;
      case 65:  error_string="invalid account";                                           break;
      case 128: error_string="trade timeout";                                             break;
      case 129: error_string="invalid price";                                             break;
      case 130: error_string="invalid stops";                                             break;
      case 131: error_string="invalid trade volume";                                      break;
      case 132: error_string="market is closed";                                          break;
      case 133: error_string="trade is disabled";                                         break;
      case 134: error_string="not enough money";                                          break;
      case 135: error_string="price changed";                                             break;
      case 136: error_string="off quotes";                                                break;
      case 137: error_string="broker is busy";                                            break;
      case 138: error_string="requote";                                                   break;
      case 139: error_string="order is locked";                                           break;
      case 140: error_string="long positions only allowed";                               break;
      case 141: error_string="too many requests";                                         break;
      case 145: error_string="modification denied because order too close to market";     break;
      case 146: error_string="trade context is busy";                                     break;
      case 147: error_string="expirations are denied by broker";                         break;
      case 148: error_string="amount of open and pending orders has reached the limit";   break;
      case 149: error_string="hedging is prohibited";                                     break;
      case 150: error_string="prohibited by FIFO rules";                                  break;
      case 4000: error_string="no error";                                                 break;
      case 4001: error_string="wrong function pointer";                                   break;
      case 4002: error_string="array index is out of range";                             break;
      case 4003: error_string="no memory for function call stack";                        break;
      case 4004: error_string="recursive stack overflow";                                 break;
      case 4005: error_string="not enough stack for parameter";                           break;
      case 4006: error_string="no memory for parameter string";                           break;
      case 4007: error_string="no memory for temp string";                               break;
      case 4008: error_string="not initialized string";                                   break;
      case 4009: error_string="not initialized string in array";                          break;
      case 4010: error_string="no memory for array string";                              break;
      case 4011: error_string="too long string";                                          break;
      case 4012: error_string="remainder from zero divide";                               break;
      case 4013: error_string="zero divide";                                              break;
      case 4014: error_string="unknown command";                                          break;
      case 4015: error_string="wrong jump";                                               break;
      case 4016: error_string="not initialized array";                                    break;
      case 4017: error_string="dll calls are not allowed";                               break;
      case 4018: error_string="cannot load library";                                      break;
      case 4019: error_string="cannot call function";                                     break;
      case 4020: error_string="expert function calls are not allowed";                    break;
      case 4021: error_string="not enough memory for temp string returned from function"; break;
      case 4022: error_string="system is busy";                                          break;
      case 4050: error_string="invalid function parameters count";                        break;
      case 4051: error_string="invalid function parameter value";                         break;
      case 4052: error_string="string function internal error";                           break;
      case 4053: error_string="some array error";                                         break;
      case 4054: error_string="incorrect series array using";                             break;
      case 4055: error_string="custom indicator error";                                   break;
      case 4056: error_string="arrays are incompatible";                                  break;
      case 4057: error_string="global variables processing error";                        break;
      case 4058: error_string="global variable not found";                                break;
      case 4059: error_string="function is not allowed in testing mode";                  break;
      case 4060: error_string="function is not confirmed";                                break;
      case 4061: error_string="send mail error";                                          break;
      case 4062: error_string="string parameter expected";                                break;
      case 4063: error_string="integer parameter expected";                               break;
      case 4064: error_string="double parameter expected";                                break;
      case 4065: error_string="array as parameter expected";                              break;
      case 4066: error_string="requested history data in update state";                   break;
      case 4067: error_string="some error in trading function";                           break;
      case 4099: error_string="end of file";                                             break;
      case 4100: error_string="some file error";                                          break;
      case 4101: error_string="wrong file name";                                          break;
      case 4102: error_string="too many opened files";                                    break;
      case 4103: error_string="cannot open file";                                         break;
      case 4104: error_string="incompatible access to a file";                           break;
      case 4105: error_string="no order selected";                                        break;
      case 4106: error_string="unknown symbol";                                           break;
      case 4107: error_string="invalid price parameter for trade function";               break;
      case 4108: error_string="invalid ticket";                                           break;
      case 4109: error_string="trade is not allowed";                                     break;
      case 4110: error_string="longs are not allowed";                                    break;
      case 4111: error_string="shorts are not allowed";                                   break;
      case 4200: error_string="object already exists";                                    break;
      case 4201: error_string="unknown object property";                                  break;
      case 4202: error_string="object does not exist";                                    break;
      case 4203: error_string="unknown object type";                                      break;
      case 4204: error_string="no object name";                                           break;
      case 4205: error_string="object coordinates error";                                 break;
      case 4206: error_string="no specified subwindow";                                   break;
      default:   error_string="unknown error";
   }
   return(error_string);
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
    // Validate signal direction with explicit enum values
    string signalDirection;
    switch(signal.signal) {
        case SIGNAL_BUY:
            signalDirection = "BUY";
            Logger.Debug("Signal validated as BUY");
            break;
        case SIGNAL_SELL:
            signalDirection = "SELL";
            Logger.Debug("Signal validated as SELL");
            break;
        default:
            signalDirection = "NEUTRAL";
            Logger.Debug("Signal defaulted to NEUTRAL");
            break;
    }

    Logger.Debug(StringFormat("Signal details - Enum value: %d, Direction: %s, Price: %.5f",
                 signal.signal, signalDirection, signal.price));

    // Calculate position size and stop loss
    int orderType = (signal.signal == SIGNAL_BUY) ? OP_BUY : OP_SELL;
    double stopLoss = g_symbolInfo.CalculateStopLoss(orderType, signal.price);
    Logger.Debug(StringFormat("Calculated Stop Loss: %.5f", stopLoss));

    // Use appropriate risk percentage from Constants
    double riskPercent = g_symbolInfo.IsCryptoPair() ?
        CRYPTO_STOP_PERCENT : DEFAULT_RISK_PERCENT;
    g_riskManager.SetRiskPercent(riskPercent);
    Logger.Debug(StringFormat("Using Risk Percent: %.2f%%", riskPercent));

    double lots = g_riskManager.CalculatePositionSize(signal.price, stopLoss, orderType);
    Logger.Debug(StringFormat("Calculated Position Size: %.2f lots", lots));

    if(lots <= 0) {
        Logger.Error(StringFormat("Invalid position size calculated: %.2f", lots));
        return;
    }

    // Prepare trade comment with explicit signal information
    string tradeComment = StringFormat("TJ:%s:%s", signalDirection, signal.pattern);
    tradeComment = StringSubstr(tradeComment, 0, 31); // Ensure comment doesn't exceed MT4 limit
    Logger.Debug(StringFormat("Trade comment prepared: '%s'", tradeComment));

    // Execute trade based on explicit signal type
    bool success = false;

    switch(signal.signal) {
        case SIGNAL_BUY:
            Logger.Debug(StringFormat("Executing BUY order - Lots: %.2f, Stop Loss: %.5f", lots, stopLoss));
            success = g_tradeManager.OpenBuyPosition(lots, stopLoss, 0, tradeComment);
            break;

        case SIGNAL_SELL:
            Logger.Debug(StringFormat("Executing SELL order - Lots: %.2f, Stop Loss: %.5f", lots, stopLoss));
            success = g_tradeManager.OpenSellPosition(lots, stopLoss, 0, tradeComment);
            break;

        default:
            Logger.Warning(StringFormat("Invalid signal type (%d) - No trade executed", signal.signal));
            return;
    }

    if(success) {
        g_lastSignalTimestamp = signal.timestamp;
        Logger.Trade(StringFormat(
            "Position successfully executed:" +
            "\nDirection: %s" +
            "\nLots: %.2f" +
            "\nEntry: %.5f" +
            "\nStop Loss: %.5f" +
            "\nPattern: %s" +
            "\nSignal Value: %d",
            signalDirection,
            lots,
            signal.price,
            stopLoss,
            signal.pattern,
            signal.signal
        ));
    } else {
        int lastError = GetLastError();
        Logger.Error(StringFormat("Trade execution failed - Signal: %d, Error: %d - %s",
                    signal.signal, lastError, ErrorDescription(lastError)));
    }
}

//+------------------------------------------------------------------+
//| Fetch signals from API                                             |
//+------------------------------------------------------------------+
string FetchSignals() {
    // Remove "+" from symbol for API call
    string symbolBase = Symbol();
    if(StringFind(symbolBase, "+") >= 0) {
        symbolBase = StringSubstr(symbolBase, 0, StringFind(symbolBase, "+"));
    }

    string url = StringFormat("%s?pairs=%s&tf=%s",
                            API_URL,
                            symbolBase,  // Use clean symbol name
                            TIMEFRAME);

    Logger.Debug(StringFormat("Fetching signals from URL: %s", url));

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
    Logger.Debug("API Response: " + response);

    if(StringLen(response) == 0) {
        Logger.Debug("No signals received");
        return "";
    }

    return response;
}


//+------------------------------------------------------------------+
//| Parse signal from API response                                     |
//+------------------------------------------------------------------+

string ConvertToUpper(string text) {
    string result = text;
    StringToUpper(result);  // This modifies the string in place
    return result;
}

bool ParseSignal(string response, SignalData &signal) {
    if(response == "") return false;

    // Attempt to parse JSON response
    bool parseSuccess = false;

    // Extract first signal from array if present
    string signalStr = response;
    if(StringGetCharacter(response, 0) == '[') {
        int firstClosingBrace = StringFind(response, "},");
        if(firstClosingBrace == -1) {
            Logger.Error("Could not find end of first signal object");
            return false;
        }
        signalStr = StringSubstr(response, 1, firstClosingBrace + 1);
    }

    Logger.Debug(StringFormat("Extracted signal string (length: %d): %s", StringLen(signalStr), signalStr));

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
        int end = StringFind(signalStr, "\",", start);  // Look for "," after the closing quote
        if(end == -1) {
            Logger.Error("Malformed action field in signal");
            return false;
        }
        action = StringSubstr(signalStr, start, end - start);
        // Logger.Debug(StringFormat("Raw action from API (Length: %d): '%s'", StringLen(action), action));

        // Remove quotes from both ends if they exist
        if(StringGetCharacter(action, 0) == '"') {
            action = StringSubstr(action, 1);
        }
        if(StringGetCharacter(action, StringLen(action)-1) == '"') {
            action = StringSubstr(action, 0, StringLen(action)-1);
        }

        // Logger.Debug(StringFormat("Action after quote removal (Length: %d): '%s'", StringLen(action), action));

        // Clean up the action string
        action = StringTrimRight(StringTrimLeft(action));
        // Logger.Debug(StringFormat("Cleaned action (Length: %d): '%s'", StringLen(action), action));

       // Convert and compare
       action = ConvertToUpper(action);
       // Logger.Debug(StringFormat("Final action for comparison (Length: %d): '%s'", StringLen(action), action));
    }

    // Parse price
    if(StringFind(signalStr, "\"price\":") >= 0) {
        int start = StringFind(signalStr, "\"price\":") + 8;
        int end = StringFind(signalStr, ",", start);
        if(end < 0) end = StringFind(signalStr, "}", start);
        string priceStr = StringSubstr(signalStr, start, end - start);
        price = StringToDouble(priceStr);
        Logger.Debug(StringFormat("Parsed price: %.5f", price));
    }

    // Parse timestamp
    if(StringFind(signalStr, "\"timestamp\":\"") >= 0) {
        int start = StringFind(signalStr, "\"timestamp\":\"") + 12;
        int end = StringFind(signalStr, "\"", start);
        string timestampStr = StringSubstr(signalStr, start, end - start);
        //Logger.Debug("Raw timestamp: " + timestampStr);

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
        //Logger.Debug("Parsed timestamp: " + TimeToString(signal.timestamp));
    }

     // Parse pattern (signalPattern)
    if(StringFind(signalStr, "\"signalPattern\":\"") >= 0) {
        int start = StringFind(signalStr, "\"signalPattern\":\"") + 16;
        int end = StringFind(signalStr, "\"", start);
        pattern = StringSubstr(signalStr, start, end - start);
        
        // Check for exit signals
        if(StringFind(pattern, "ExitsBearish Exit") >= 0) {
            signal.isExitSignal = true;
            signal.exitType = EXIT_BEARISH;
            Logger.Debug("Detected Bearish Exit Signal");
        }
        else if(StringFind(pattern, "ExitsBullish Exit") >= 0) {
            signal.isExitSignal = true;
            signal.exitType = EXIT_BULLISH;
            Logger.Debug("Detected Bullish Exit Signal");
        }
    }

   // Set signal type with explicit validation and logging
   Logger.Debug("Setting signal type for action: '" + action + "'");

   Logger.Debug("Comparing action: '" + action + "' with 'BUY' and 'SELL'");

    Logger.Debug(StringFormat("StringCompare results - BUY: %d, SELL: %d",
        StringCompare(action, "BUY"), StringCompare(action, "SELL")));

    // Direct comparison (no conversion needed as API sends uppercase)
    Logger.Debug(StringFormat("Attempting to match action '%s'", action));
    if(action == "SELL") {
        signal.signal = SIGNAL_SELL;
        //Logger.Debug("Signal set to SELL (2)");
    }
    else if(action == "BUY") {
        signal.signal = SIGNAL_BUY;
        //Logger.Debug("Signal set to BUY (1)");
    }
    else {
        //Logger.Error(StringFormat("Invalid action received: '%s' (Length: %d)", action, StringLen(action)));
        return false;
    }

    // Validate all required fields
    bool validSignal = (ticker != "" && action != "" && price > 0 && signal.timestamp > 0);
    Logger.Debug(StringFormat("Signal validation - Ticker: %s, Action: %s, Price: %.5f, Timestamp: %s, Valid: %s",
        ticker, action, price, TimeToString(signal.timestamp), validSignal ? "true" : "false"));

    if(validSignal) {
        signal.ticker = ticker;
        signal.price = price;
        signal.pattern = pattern;
        parseSuccess = true;

      Logger.Info(StringFormat(
            "Successfully parsed signal: Symbol=%s, Action=%s, Price=%.5f, Pattern=%s, Timestamp=%s, Signal Type=%d",
            signal.ticker,
            action,
            signal.price,
            signal.pattern,
            TimeToString(signal.timestamp),
            signal.signal
        ));
    } else {
        Logger.Error(StringFormat(
            "Signal validation failed: Ticker=%s, Action=%s, Price=%.5f, Timestamp=%s",
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

