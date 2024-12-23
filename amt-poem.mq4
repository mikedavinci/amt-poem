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
#include "../Include/CTradeJourney.mqh"

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
string m_currentSymbol;
CTradeJourney* g_tradeJourney = NULL;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit() {
    // Initialize logger first
    Logger.EnableDebugMode(DEBUG_MODE);
    Logger.EnablePapertrail(ENABLE_PAPERTRAIL);
    Logger.SetSystemName(SYSTEM_NAME);
    Logger.SetPapertrailHost(PAPERTRAIL_HOST);

    // Create and initialize trade journey instance
    g_tradeJourney = new CTradeJourney();
    if(!g_tradeJourney.Initialize()) {
        Logger.Error("Failed to initialize EA");
        return INIT_FAILED;
    }

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    if(g_tradeJourney != NULL) {
        delete g_tradeJourney;
        g_tradeJourney = NULL;
    }
    Logger.Info(StringFormat("EA Deinitialized. Reason: %d", reason));
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick() {
    if(g_tradeJourney != NULL) {
        g_tradeJourney.OnTick();
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
//| Parse timestamp string to datetime                                 |
//+------------------------------------------------------------------+
datetime ParseTimestamp(string rawTimestamp, bool &success) {
    success = false;
    string timestampStr = rawTimestamp;
    
    // Clean the timestamp string
    StringReplace(timestampStr, "\"", ""); // Remove quotes
    timestampStr = StringTrimRight(StringTrimLeft(timestampStr));
    
    Logger.Debug("Parsing timestamp: " + timestampStr);
    
    // Extract date components
    int month = (int)StringToInteger(StringSubstr(timestampStr, 0, 2));
    int day = (int)StringToInteger(StringSubstr(timestampStr, 3, 2));
    int year = (int)StringToInteger(StringSubstr(timestampStr, 6, 4));
    
    // Extract time components
    int hour = (int)StringToInteger(StringSubstr(timestampStr, 11, 2));
    int minute = (int)StringToInteger(StringSubstr(timestampStr, 14, 2));
    int second = (int)StringToInteger(StringSubstr(timestampStr, 17, 2));
    
    // Handle AM/PM
    bool isPM = StringFind(timestampStr, "PM") >= 0;
    if(isPM && hour < 12) hour += 12;
    
    Logger.Debug(StringFormat(
        "Timestamp components: Y:%d M:%d D:%d H:%d M:%d S:%d PM:%s",
        year, month, day, hour, minute, second,
        isPM ? "Yes" : "No"
    ));
    
    // Create datetime string in MT4 format (YYYY.MM.DD HH:MM:SS)
    string formattedDateTime = StringFormat(
        "%04d.%02d.%02d %02d:%02d:%02d",
        year, month, day, hour, minute, second
    );
    
    // Convert to datetime
    datetime result = StringToTime(formattedDateTime);
    
    if(result > 0) {
        success = true;
        Logger.Debug(StringFormat(
            "Successfully parsed timestamp: %s -> %s",
            timestampStr,
            TimeToString(result, TIME_DATE|TIME_MINUTES|TIME_SECONDS)
        ));
    } else {
        Logger.Error(StringFormat(
            "Failed to parse timestamp: %s -> %s",
            timestampStr,
            formattedDateTime
        ));
    }
    
    return result;
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
    // Initialize default values
    signal.signal = SIGNAL_NEUTRAL;
    signal.price = 0;
    signal.ticker = "";
    signal.pattern = "";

    string signalStr = response;
    
    // Remove array brackets if present
    if(StringGetCharacter(response, 0) == '[') {
        signalStr = StringSubstr(response, 1, StringLen(response) - 2);
    }
    
    Logger.Debug("Processing signal string: " + signalStr);

    // Extract ticker
    string tickerSearch = "\"ticker\":\"";
    int tickerPos = StringFind(signalStr, tickerSearch);
    if(tickerPos != -1) {
        int startQuote = tickerPos + StringLen(tickerSearch);
        int endQuote = StringFind(signalStr, "\"", startQuote);
        if(endQuote != -1) {
            signal.ticker = StringSubstr(signalStr, startQuote, endQuote - startQuote);
        }
    }

    // Extract action
    string actionSearch = "\"action\":\"";
    int actionPos = StringFind(signalStr, actionSearch);
    if(actionPos != -1) {
        int startQuote = actionPos + StringLen(actionSearch);
        int endQuote = StringFind(signalStr, "\"", startQuote);
        if(endQuote != -1) {
            string actionValue = StringSubstr(signalStr, startQuote, endQuote - startQuote);
            Logger.Debug("Raw action value: " + actionValue);
            
            // Clean and compare action
            if(StringCompare(actionValue, "BUY") == 0) {
                signal.signal = SIGNAL_BUY;
                Logger.Debug("Action set to BUY");
            }
            else if(StringCompare(actionValue, "SELL") == 0) {
                signal.signal = SIGNAL_SELL;
                Logger.Debug("Action set to SELL");
            }
        }
    }

    // Extract price
    string priceSearch = "\"price\":";
    int pricePos = StringFind(signalStr, priceSearch);
    if(pricePos != -1) {
        int startPrice = pricePos + StringLen(priceSearch);
        int endPrice = StringFind(signalStr, ",", startPrice);
        if(endPrice != -1) {
            string priceStr = StringSubstr(signalStr, startPrice, endPrice - startPrice);
            signal.price = StringToDouble(priceStr);
            Logger.Debug(StringFormat("Extracted price: %.5f", signal.price));
        }
    }

    string timestampSearch = "\"timestamp\":\"";
    int timestampPos = StringFind(signalStr, timestampSearch);
    if(timestampPos != -1) {
        int startQuote = timestampPos + StringLen(timestampSearch);
        int endQuote = StringFind(signalStr, "\"", startQuote);
        if(endQuote != -1) {
            string timestampStr = StringSubstr(signalStr, startQuote, endQuote - startQuote);
            bool parseSuccess = false;
            signal.timestamp = ParseTimestamp(timestampStr, parseSuccess);
            Logger.Debug(StringFormat("Parsed timestamp: %s -> %s", 
                timestampStr, 
                TimeToString(signal.timestamp)));

            if(!parseSuccess) {
                Logger.Error("Failed to parse timestamp: " + timestampStr);
                return false;
            }
        }
    }

    // Extract pattern
    string patternSearch = "\"signalPattern\":\"";
    int patternPos = StringFind(signalStr, patternSearch);
    if(patternPos != -1) {
        int startQuote = patternPos + StringLen(patternSearch);
        int endQuote = StringFind(signalStr, "\"", startQuote);
        if(endQuote != -1) {
            signal.pattern = StringSubstr(signalStr, startQuote, endQuote - startQuote);
        }
    }

    // Log all extracted values
    Logger.Debug(StringFormat(
        "Final extracted values:" +
        "\nTicker: [%s]" +
        "\nAction: %s" +
        "\nPrice: %.5f" +
        "\nPattern: [%s]",
        signal.ticker,
        signal.signal == SIGNAL_BUY ? "BUY" : 
            signal.signal == SIGNAL_SELL ? "SELL" : "NEUTRAL",
        signal.price,
        signal.pattern
    ));

    // Validate the signal
    bool validSignal = (
        StringLen(signal.ticker) > 0 && 
        signal.price > 0 && 
        signal.signal != SIGNAL_NEUTRAL &&
        StringLen(signal.pattern) > 0
    );

    Logger.Debug(StringFormat("Signal validation result: %s", validSignal ? "Valid" : "Invalid"));
    
    return validSignal;
}

//+------------------------------------------------------------------+
//| Check and apply profit protection                                  |
//+------------------------------------------------------------------+
void CheckProfitProtection(const PositionMetrics &metrics) {
    if(metrics.totalPositions == 0) return;

      for(int i = OrdersTotal() - 1; i >= 0; i--) {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
            if(OrderSymbol() == Symbol() && 
               StringFind(OrderComment(), "Exit Signal") == -1) { 
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

