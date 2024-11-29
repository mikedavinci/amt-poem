//+------------------------------------------------------------------+
//|                                                   SignalReader.mq4  |
//|                                                                    |
//+------------------------------------------------------------------+
#property copyright "Miguel Esparza mikedavinci"
#property link      "TradeJourney.ai"
#property version   "1.00"
#property strict

// External parameters
extern string API_URL = "https://api.tradejourney.ai/api/alerts/mt4-forex-signals";  // API URL
extern int    REFRESH_MINUTES = 5;                    // How often to check for new signals
extern bool   DEBUG_MODE = true;                      // Print debug messages
extern string PAPERTRAIL_HOST = "logs.papertrailapp.com"; // Papertrail host
extern string PAPERTRAIL_PORT = "26548";                  // Your Papertrail port
extern string SYSTEM_NAME = "TradeJourney";                     // System identifier
extern bool   ENABLE_PROFIT_PROTECTION = true;     // Enable/disable profit protection
extern double PROFIT_LOCK_BUFFER = 2.0;         // Buffer before closing (2.0 pips for forex, 2.0% for crypto)
extern double MIN_PROFIT_TO_PROTECT = 1.0;      // Minimum profit (in pips/%) before protection activates
extern int    PROFIT_CHECK_INTERVAL = 60;        // How often to check profit protection (in seconds) 60 is 1 min
extern double RISK_PERCENT = 5;                    // Risk percentage per trade (5%)
extern int    MAX_POSITIONS = 1;                     // Maximum positions per symbol
extern int    MAX_RETRIES = 3;                       // Maximum retries for failed trades
extern double STOP_LOSS_PERCENT = 5;              // Stop loss percentage from entry
extern int    EMERGENCY_CLOSE_PERCENT = 10;          // Emergency close if loss exceeds this percentage
extern int    MAX_SLIPPAGE = 5;                      // Maximum allowed slippage in points
extern int    PRICE_DIGITS = 5;                      // Decimal places for price display (5 for forex, 3 for JPY pairs)
extern string TIMEFRAME = "60";                      // Timeframe parameter for API

// Global variables
datetime lastCheck = 0;
string lastSignalTimestamp = "";

// Structure to hold signal data
struct SignalData {
   string ticker;
   string action;
   double price;
   double stopLoss;
   double takeProfit;
   string timestamp;
   string pattern;
};

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit() {
   // Add your symbol to MarketWatch if not already there
   SymbolSelect("EURUSD+", true);
   SymbolSelect("AUDUSD+", true);
   SymbolSelect("GBPUSD+", true);
   //SymbolSelect("USDJPY+", true);
   SymbolSelect("BTCUSD", true); 
   SymbolSelect("ETHUSD", true);
   //SymbolSelect("LTCUSD", true);

   
   LogInfo("EA Initialized with Risk: " + DoubleToString(RISK_PERCENT, 2) + "%");
   LogInfo("Account Balance: " + DoubleToString(AccountBalance(), 2));
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   LogInfo("EA Deinitialized. Reason: " + IntegerToString(reason));
}

//+------------------------------------------------------------------+
//| Send Log to Papertrail                                            |
//+------------------------------------------------------------------+
void SendToPapertrail(string message, string level = "INFO") {
    string timestamp = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
    string logMessage = StringFormat(
        "{\"system\":\"%s\",\"facility\":\"MT4\",\"severity\":\"%s\",\"timestamp\":\"%s\",\"message\":\"%s\"}",
        SYSTEM_NAME,
        level,
        timestamp,
        message
    );
    
    string headers = "Content-Type: application/json\r\n";
    headers += "Host: " + PAPERTRAIL_HOST + "\r\n";
    
    char post[];
    StringToCharArray(logMessage, post);
    
    char result[];
    string resultHeaders;
    
    string url = "https://" + PAPERTRAIL_HOST + ":" + PAPERTRAIL_PORT + "/v1/event";
    
    int res = WebRequest(
        "POST",
        url,
        headers,
        5000,
        post,
        result,
        resultHeaders
    );
    
    if(res == -1) {
        int error = GetLastError();
        LogError("Failed to send log to Papertrail. Error: " + IntegerToString(error));
    }
}

//+------------------------------------------------------------------+
//| Enhanced Debug Print Function with Papertrail Integration          |
//+------------------------------------------------------------------+
void PrintDebug(string message, string level = "INFO") {
    string formattedMessage = TimeToString(TimeCurrent()) + " | " + message;
    
    // Still maintain local MT4 logging if debug mode is enabled
    if(DEBUG_MODE) {
        Print(formattedMessage);
    }
    
    // Send to Papertrail regardless of debug mode
    SendToPapertrail(message, level);
}

//+------------------------------------------------------------------+
//| Log Levels for Different Types of Messages                         |
//+------------------------------------------------------------------+
void LogError(string message) {
    PrintDebug(message, "ERROR");
}

void LogWarning(string message) {
    PrintDebug(message, "WARNING");
}

void LogInfo(string message) {
    PrintDebug(message, "INFO");
}

void LogDebug(string message) {
    PrintDebug(message, "DEBUG");
}

void LogTrade(string message) {
    PrintDebug(message, "TRADE");
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick() {
   // First, check for any positions that need emergency closing
   CheckEmergencyClose();
   
   if (!IsTimeToCheck()) return;
   
   string currentSymbol = Symbol();
   LogDebug("Bid Price: " + DoubleToString(MarketInfo(currentSymbol, MODE_BID), 5));

   string apiSymbol = GetBaseSymbol(currentSymbol);
   string url = StringFormat("%s?pairs=%s&tf=%s", API_URL, apiSymbol, TIMEFRAME);
   
   LogDebug("Checking for new signals: " + currentSymbol);
   
   string response = FetchSignals(url);
   if (response == "") return;
   
   SignalData signal;
   if (ParseSignal(response, signal)) {
      ProcessSignal(signal);
   }
   
   lastCheck = TimeCurrent();
   
   CheckProfitProtection();
}

//+------------------------------------------------------------------+
//| Check if it's time to refresh signals                             |
//+------------------------------------------------------------------+
bool IsTimeToCheck() {
   datetime currentTime = TimeCurrent();
   return (currentTime >= lastCheck + REFRESH_MINUTES * 60);
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
      LogError("Error in WebRequest. Error code: " + IntegerToString(errorCode));
      return "";
   }
   
   string response = CharArrayToString(result);
   LogDebug("API Response: " + response);
   return response;
}

//+------------------------------------------------------------------+
//| Parse JSON signal                                                 |
//+------------------------------------------------------------------+
bool ParseSignal(string &jsonString, SignalData &signal) {
   // Remove array brackets if present
   string json = jsonString;
   if (StringGetChar(json, 0) == '[') {
      json = StringSubstr(json, 1, StringLen(json) - 2);
   }
   
   if (StringFind(json, "ticker") < 0) return false;
   
   // Extract values using simple string manipulation
   string ticker = GetJsonValue(json, "ticker");
   // Only add "+" for forex pairs, not for crypto
   signal.ticker = (StringFind(ticker, "BTC") >= 0 || StringFind(ticker, "ETH" ) >= 0 || StringFind(ticker, "LTC") >= 0) ? ticker : ticker + "+";
   signal.action = GetJsonValue(json, "action");
   signal.price = StringToDouble(GetJsonValue(json, "price"));
   signal.stopLoss = StringToDouble(GetJsonValue(json, "stopLoss"));
   signal.takeProfit = StringToDouble(GetJsonValue(json, "takeProfit"));
   signal.timestamp = GetJsonValue(json, "timestamp");
   signal.pattern = GetJsonValue(json, "signalPattern");
   
   LogDebug("Parsed Signal - Action: " + signal.action + " Pattern: " + signal.pattern);
   return true;

   LogDebug("Parsed values - Price: " + DoubleToString(signal.price, 5) + 
           " StopLoss: " + DoubleToString(signal.stopLoss, 5) + 
           " TakeProfit: " + DoubleToString(signal.takeProfit, 5));
}

//+------------------------------------------------------------------+
//| Calculate position size based on risk percentage                   |
//+------------------------------------------------------------------+
double CalculatePositionSize(string symbol, double entryPrice, double stopLoss) {
   // 1. Calculate maximum risk amount based on account balance
   double accountBalance = AccountBalance();
   double maxRiskAmount = accountBalance * (RISK_PERCENT / 100);
   
   // 2. Calculate stop loss distance in price terms
   double stopDistance = MathAbs(entryPrice - stopLoss);  // Always use the provided stop loss
   
   if(stopDistance == 0) {
      LogError("Error: Stop loss distance cannot be zero");
      return 0;  // Prevent division by zero and invalid trades
   }
   
   // 3. Identify pair type
   bool isCryptoPair = (StringFind(symbol, "BTC") >= 0 || StringFind(symbol, "ETH") >= 0 || StringFind(symbol, "LTC") >= 0);
   bool isJPYPair = (StringFind(symbol, "JPY") >= 0);
   
   // 4. Calculate position size
   double lotSize;
   
   if(isCryptoPair) {
      // For crypto, calculate based on contract value
      double contractValue = entryPrice;  // 1 lot = 1 BTC or 1 ETH
      double riskPerCoin = stopDistance;  // Direct price difference
      lotSize = maxRiskAmount / riskPerCoin;
      
      LogDebug("Crypto Position Size Calculation:" +
                 "\nContract Value: $" + DoubleToString(contractValue, 2) +
                 "\nRisk Per Coin: $" + DoubleToString(riskPerCoin, 2) +
                 "\nInitial Lot Size: " + DoubleToString(lotSize, 8));
   } else {
      // For forex pairs
      double point = MarketInfo(symbol, MODE_POINT);
      double tickValue = MarketInfo(symbol, MODE_TICKVALUE);
      
      // Convert stop distance to points
      double stopPoints = stopDistance / point;
      
      // Calculate pip value
      double pipValue;
      if(isJPYPair) {
         pipValue = tickValue * 100;  // JPY pairs have 2 decimal places
         stopPoints = stopPoints / 100;
      } else {
         pipValue = tickValue * 10;   // Other pairs have 4 decimal places
         stopPoints = stopPoints / 10;
      }
      
      // Calculate lot size based on risk
      lotSize = maxRiskAmount / (stopPoints * pipValue);
      
      LogDebug("Forex Position Size Calculation:" +
                 "\nStop Points: " + DoubleToString(stopPoints, 1) +
                 "\nPip Value: $" + DoubleToString(pipValue, 5) +
                 "\nInitial Lot Size: " + DoubleToString(lotSize, 3));
   }
   
   // Get broker's lot constraints
   double minLot = MarketInfo(symbol, MODE_MINLOT);
   double maxLot = MarketInfo(symbol, MODE_MAXLOT);
   double lotStep = MarketInfo(symbol, MODE_LOTSTEP);
   
   // Round to broker's lot step
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   
   // Ensure within broker's limits
   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
   
   // Debug output
   int digits = isCryptoPair ? 8 : (isJPYPair ? 3 : 5);
   LogDebug("Final Position Size Calculation for " + symbol + ":" +
              "\nAccount Balance: $" + DoubleToString(accountBalance, 2) +
              "\nRisk Amount: $" + DoubleToString(maxRiskAmount, 2) +
              "\nEntry Price: " + DoubleToString(entryPrice, digits) +
              "\nStop Distance: " + DoubleToString(stopDistance, digits) +
              "\nCalculated Lot Size: " + DoubleToString(lotSize, 8) +
              "\nIs Crypto: " + (isCryptoPair ? "Yes" : "No"));
   
   return lotSize;
}

//+------------------------------------------------------------------+
//| Process trading signal                                            |
//+------------------------------------------------------------------+
void ProcessSignal(SignalData &signal) {

   if(MarketInfo(signal.ticker, MODE_BID) == 0) {
      LogError("Error: Invalid symbol " + signal.ticker);
      return;
   }

   if (signal.timestamp == lastSignalTimestamp) {
      LogDebug("Signal already processed for: " + signal.timestamp);
      return;
   }
   
   // Check if market is open before processing signal
   if(!IsMarketOpen(signal.ticker)) {
      LogDebug("Market closed for " + signal.ticker + " - signal not processed");
      return;
   }
   
   int cmd = -1;
   if (signal.action == "BUY") cmd = OP_BUY;
   else if (signal.action == "SELL") cmd = OP_SELL;
   else {
      LogDebug("NEUTRAL signal received - no action taken");
      return;
   }
   
   // ALWAYS handle existing positions first
   if (HasOpenPosition(signal.ticker)) {
      int currentPositionType = GetOpenPositionType(signal.ticker);
      bool shouldClose = false;
      
      // Close if opposite signal or emergency threshold reached
      if ((cmd == OP_BUY && currentPositionType == OP_SELL) || 
          (cmd == OP_SELL && currentPositionType == OP_BUY)) {
          shouldClose = true;
      }
      
      if(shouldClose) {
          LogDebug("Closing existing " + (currentPositionType == OP_BUY ? "BUY" : "SELL") + 
                     " position before opening new " + signal.action + " position");
                     
          if (!CloseCurrentPosition(signal.ticker)) {
              LogError("Failed to close existing position - new position not opened");
              return;
          }
      } else {
          LogDebug("Position already exists in same direction - no action taken");
          return;
      }
   }
   
   // Only check for new positions after handling existing ones
   if(!CanOpenNewPosition(signal.ticker)) {
      LogDebug("Risk management prevented opening new position");
      return;
   }
   
   // Get current market prices
   double ask = MarketInfo(signal.ticker, MODE_ASK);
   double bid = MarketInfo(signal.ticker, MODE_BID);
   double price = cmd == OP_BUY ? ask : bid;
   
   // Calculate stop loss using external parameter
   double sl;
   if(cmd == OP_BUY) {
      sl = price * (1 - STOP_LOSS_PERCENT/100); 
   } else {
      sl = price * (1 + STOP_LOSS_PERCENT/100);
   }
   
   // Verify stop loss is valid
   if(cmd == OP_BUY && sl >= price) {
      LogError("Error: Invalid stop loss for BUY order - must be below entry price");
      return;
   }
   if(cmd == OP_SELL && sl <= price) {
      LogError("Error: Invalid stop loss for SELL order - must be above entry price");
      return;
   }
   
   double tp = 0;  // Take profit will be determined by opposite signal
   
   // Calculate position size based on risk
   double lotSize = CalculatePositionSize(signal.ticker, price, sl);
   if(lotSize == 0) {
      LogError("Error: Invalid lot size calculated");
      return;
   }
   
   // Debug output
   int digits;
   if(StringFind(signal.ticker, "BTC") >= 0 || StringFind(signal.ticker, "ETH") >= 0 || StringFind(signal.ticker, "LTC") >= 0) digits = 8;  // Most crypto pairs use 8 decimal places
   else if(StringFind(signal.ticker, "JPY") >= 0) digits = 3;
   else digits = 5;
   
   LogTrade("Placing order:" +
              "\nSymbol: " + signal.ticker +
              "\nAction: " + signal.action +
              "\nLots: " + DoubleToString(lotSize, 2) +
              "\nPrice: " + DoubleToString(price, digits) +  // Using correct digits
              "\nSL: " + DoubleToString(sl, digits) +        // Using correct digits
              "\nTP: " + DoubleToString(tp, digits) +        // Using correct digits
              "\nPattern: " + signal.pattern);
   
   int ticket = OrderSend(
      signal.ticker,          // Symbol
      cmd,                    // Operation
      lotSize,               // Lot size
      price,                 // Price
      MAX_SLIPPAGE,          // Slippage
      sl,                    // Stop Loss
      tp,                    // Take Profit
      signal.pattern,        // Comment
      0,                     // Magic Number
      0,                     // Expiration
      cmd == OP_BUY ? clrGreen : clrRed
   );
   
   if (ticket < 0) {
      int error = GetLastError();
      for(int retry = 1; retry <= MAX_RETRIES; retry++) {
         LogDebug("Retry " + IntegerToString(retry) + " of " + IntegerToString(MAX_RETRIES));
         
         RefreshRates();  // Get latest prices
         price = cmd == OP_BUY ? MarketInfo(signal.ticker, MODE_ASK) : MarketInfo(signal.ticker, MODE_BID);
         
         ticket = OrderSend(
            signal.ticker,
            cmd,
            lotSize,
            price,
            MAX_SLIPPAGE,
            sl,
            tp,
            signal.pattern,
            0,
            0,
            cmd == OP_BUY ? clrGreen : clrRed
         );
         
         if(ticket >= 0) break;  // Success
         Sleep(1000);  // Wait 1 second before retry
      }
      
      if(ticket < 0) {  // Still failed after retries
         error = GetLastError();
         LogError("OrderSend failed after " + IntegerToString(MAX_RETRIES) + " retries: " + 
                    IntegerToString(error) + 
                    "\nDescription: " + ErrorDescription(error) +
                    "\nSymbol: " + signal.ticker +
                    "\nLots: " + DoubleToString(lotSize, 2) +
                    "\nPrice: " + DoubleToString(price, digits));
      }
   } else {
      LogTrade("Order placed successfully" +
                 "\nTicket: " + IntegerToString(ticket) +
                 "\nSymbol: " + signal.ticker +
                 "\nType: " + signal.action +
                 "\nLots: " + DoubleToString(lotSize, 2) +
                 "\nPrice: " + DoubleToString(price, digits));
      lastSignalTimestamp = signal.timestamp;
   }
}

//+------------------------------------------------------------------+
//| Check and Protect Profitable Positions                             |
//+------------------------------------------------------------------+
void CheckProfitProtection() {
    static datetime lastProfitCheck = 0;
    datetime currentTime = TimeCurrent();
    
    // Only check at specified intervals to reduce processing load
    if(currentTime - lastProfitCheck < PROFIT_CHECK_INTERVAL) return;
    lastProfitCheck = currentTime;
    
    if(!ENABLE_PROFIT_PROTECTION) return;
    
    for(int i = 0; i < OrdersTotal(); i++) {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
            string symbol = OrderSymbol();
            bool isCryptoPair = (StringFind(symbol, "BTC") >= 0 || StringFind(symbol, "ETH") >= 0 || StringFind(symbol, "LTC") >= 0);
            double pointValue = MarketInfo(symbol, MODE_POINT);
            double currentProfit = OrderProfit();
            double profitInPips;
            
            // Calculate profit in pips/percentage
            if(isCryptoPair) {
                profitInPips = (currentProfit / OrderOpenPrice()) * 100; // Convert to percentage
            } else {
                double pipValue = MarketInfo(symbol, MODE_TICKVALUE) * 10;
                profitInPips = currentProfit / pipValue;
            }
            
            // Only check positions that have reached minimum profit threshold
            if(profitInPips >= MIN_PROFIT_TO_PROTECT) {
                double currentPrice = OrderType() == OP_BUY ? 
                    MarketInfo(symbol, MODE_BID) : 
                    MarketInfo(symbol, MODE_ASK);
                
                // Calculate buffer based on pair type
                double bufferInPoints;
                if(isCryptoPair) {
                    bufferInPoints = OrderOpenPrice() * (PROFIT_LOCK_BUFFER/100);
                } else {
                    bufferInPoints = PROFIT_LOCK_BUFFER * 10; // Convert pips to points
                }
                
                // Calculate price at which profit would be zero (including spread)
                double breakEvenPrice = OrderOpenPrice();
                double spread = MarketInfo(symbol, MODE_SPREAD) * pointValue;
                
                // If price is approaching breakeven level (within buffer), close the position
                if(OrderType() == OP_BUY) {
                    double effectivePrice = currentPrice - spread; // Account for spread
                    if(effectivePrice <= breakEvenPrice + (isCryptoPair ? bufferInPoints : bufferInPoints * pointValue)) {
                        LogTrade("Profit protection triggered for " + symbol + 
                                 "\nProfit (pips/%): " + DoubleToString(profitInPips, 2) +
                                 "\nCurrent Price: " + DoubleToString(currentPrice, isCryptoPair ? 2 : 5) +
                                 "\nEffective Price: " + DoubleToString(effectivePrice, isCryptoPair ? 2 : 5) +
                                 "\nBreak Even: " + DoubleToString(breakEvenPrice, isCryptoPair ? 2 : 5) +
                                 "\nBuffer: " + DoubleToString(bufferInPoints, isCryptoPair ? 2 : 5));
                        CloseTradeWithProtection(OrderTicket(), "Profit protection activated");
                    }
                } else if(OrderType() == OP_SELL) {
                    double effectivePrice = currentPrice + spread; // Account for spread
                    if(effectivePrice >= breakEvenPrice - (isCryptoPair ? bufferInPoints : bufferInPoints * pointValue)) {
                        LogTrade("Profit protection triggered for " + symbol + 
                                 "\nProfit (pips/%): " + DoubleToString(profitInPips, 2) +
                                 "\nCurrent Price: " + DoubleToString(currentPrice, isCryptoPair ? 2 : 5) +
                                 "\nEffective Price: " + DoubleToString(effectivePrice, isCryptoPair ? 2 : 5) +
                                 "\nBreak Even: " + DoubleToString(breakEvenPrice, isCryptoPair ? 2 : 5) +
                                 "\nBuffer: " + DoubleToString(bufferInPoints, isCryptoPair ? 2 : 5));
                        CloseTradeWithProtection(OrderTicket(), "Profit protection activated");
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Close Trade with Retry Protection                                  |
//+------------------------------------------------------------------+
bool CloseTradeWithProtection(int ticket, string reason) {
    if(!OrderSelect(ticket, SELECT_BY_TICKET)) return false;
    
    double closePrice = OrderType() == OP_BUY ? 
        MarketInfo(OrderSymbol(), MODE_BID) : 
        MarketInfo(OrderSymbol(), MODE_ASK);
    
    bool success = false;
    for(int attempt = 0; attempt < MAX_RETRIES; attempt++) {
        success = OrderClose(ticket, OrderLots(), closePrice, MAX_SLIPPAGE, clrRed);
        if(success) {
            LogTrade("Closed position " + IntegerToString(ticket) + ": " + reason);
            break;
        }
        
        int error = GetLastError();
        LogError("Close attempt " + IntegerToString(attempt + 1) + " failed: " + 
                   ErrorDescription(error));
        Sleep(1000); // Wait 1 second before retry
        RefreshRates();
    }
    
    return success;
}

//+------------------------------------------------------------------+
//| Check if we can open new positions based on risk management        |
//+------------------------------------------------------------------+
bool CanOpenNewPosition(string symbol) {
   // Check maximum positions per symbol
   int symbolPositions = 0;
   for(int i = 0; i < OrdersTotal(); i++) {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
         if(OrderSymbol() == symbol) symbolPositions++;
      }
   }
   if(symbolPositions >= MAX_POSITIONS) {
      LogDebug("Maximum positions reached for " + symbol);
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Get the type of open position (OP_BUY or OP_SELL)                 |
//+------------------------------------------------------------------+
int GetOpenPositionType(string symbol) {
   for(int i = 0; i < OrdersTotal(); i++) {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
         if(OrderSymbol() == symbol) {
            return OrderType();
         }
      }
   }
   return -1;
}

//+------------------------------------------------------------------+
//| Close current position for the symbol                             |
//+------------------------------------------------------------------+
bool CloseCurrentPosition(string symbol) {
   for(int i = 0; i < OrdersTotal(); i++) {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
         if(OrderSymbol() == symbol) {
            double closePrice = OrderType() == OP_BUY ? MarketInfo(symbol, MODE_BID) : MarketInfo(symbol, MODE_ASK);
            
            for(int retry = 0; retry < MAX_RETRIES; retry++) {
               bool closed = OrderClose(OrderTicket(), OrderLots(), closePrice, MAX_SLIPPAGE, OrderType() == OP_BUY ? clrRed : clrGreen);
               if(closed) return true;
               
               int error = GetLastError();
               LogError("Failed to close position, attempt " + IntegerToString(retry + 1) + " of " + IntegerToString(MAX_RETRIES) +
                         "\nError: " + IntegerToString(error) +
                         "\nDescription: " + ErrorDescription(error));
               
               RefreshRates();
               Sleep(1000);  // Wait 1 second before retry
            }
            return false;  // Failed after all retries
         }
      }
   }
   return false;  // No matching position found
}

//+------------------------------------------------------------------+
//| Check if symbol has open position                                 |
//+------------------------------------------------------------------+
bool HasOpenPosition(string symbol) {
   for(int i = 0; i < OrdersTotal(); i++) {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
         if(OrderSymbol() == symbol) return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Helper function to extract JSON values                            |
//+------------------------------------------------------------------+
string GetJsonValue(string &json, string key) {
   string search = "\"" + key + "\":\"";
   int start = StringFind(json, search);
   if(start == -1) {
      // Try without quotes (for numbers)
      search = "\"" + key + "\":";
      start = StringFind(json, search);
      if(start == -1) return "";
   }
   
   start += StringLen(search);
   int end = StringFind(json, "\"", start);
   if(end == -1) {
      // Try finding comma for numbers
      end = StringFind(json, ",", start);
      if(end == -1) end = StringFind(json, "}", start);
      if(end == -1) return "";
   }
   
   return StringSubstr(json, start, end - start);
}

//+------------------------------------------------------------------+
//| Get error description                                             |
//+------------------------------------------------------------------+
string ErrorDescription(int error_code) {
   string error_string;
   
   switch(error_code) {
      case 0:   error_string = "No error";                                                break;
      case 1:   error_string = "No error, trade conditions not changed";                 break;
      case 2:   error_string = "Common error";                                           break;
      case 3:   error_string = "Invalid trade parameters";                               break;
      case 4:   error_string = "Trade server is busy";                                   break;
      case 5:   error_string = "Old version of the client terminal";                     break;
      case 6:   error_string = "No connection with trade server";                        break;
      case 7:   error_string = "Not enough rights";
      case 8:   error_string = "Too frequent requests";                                  break;
      case 9:   error_string = "Malfunctional trade operation";                         break;
      case 64:  error_string = "Account disabled";                                       break;
      case 65:  error_string = "Invalid account";                                        break;
      case 128: error_string = "Trade timeout";                                          break;
      case 129: error_string = "Invalid price";                                          break;
      case 130: error_string = "Invalid stops";                                          break;
      case 131: error_string = "Invalid trade volume";                                   break;
      case 132: error_string = "Market is closed";                                       break;
      case 133: error_string = "Trade is disabled";                                      break;
      case 134: error_string = "Not enough money";                                       break;
      case 135: error_string = "Price changed";                                          break;
      case 136: error_string = "Off quotes";                                            break;
      case 137: error_string = "Broker is busy";                                        break;
      case 138: error_string = "Requote";                                               break;
      case 139: error_string = "Order is locked";                                       break;
      case 140: error_string = "Long positions only allowed";                           break;
      case 141: error_string = "Too many requests";                                     break;
      case 145: error_string = "Modification denied because order too close to market"; break;
      case 146: error_string = "Trade context is busy";                                 break;
      case 147: error_string = "Expirations are denied by broker";                      break;
      case 148: error_string = "Amount of open and pending orders has reached the limit";break;
      default:  error_string = "Unknown error";                                         break;
   }
   
   return error_string;
}

//+------------------------------------------------------------------+
//| Check if market is open for trading                               |
//+------------------------------------------------------------------+
bool IsMarketOpen(string symbol) {
   datetime symbolTime = (datetime)MarketInfo(symbol, MODE_TIME);  // Explicit cast to datetime
   if(symbolTime == 0) return false;
   
   // Check for weekends
   int dayOfWeek = (int)TimeDayOfWeek(TimeCurrent());  // Explicit cast to int
   if(dayOfWeek == 0 || dayOfWeek == 6) {
      if(StringFind(symbol, "BTC") == -1 && StringFind(symbol, "ETH") == -1 && StringFind(symbol, "LTC") == -1) {
         LogDebug("Market closed (Weekend) for " + symbol);
         return false;  // Only allow crypto on weekends
      }
   }
   
   // Additional check for forex market hours (not needed for crypto)
   if(StringFind(symbol, "BTC") == -1 && StringFind(symbol, "ETH") == -1 && StringFind(symbol, "LTC") == -1) {
      int currentHour = (int)TimeHour(TimeCurrent());  // Explicit cast to int
      // Check if it's between Friday 22:00 and Sunday 22:00 GMT
      if(dayOfWeek == 5 && currentHour >= 22) {
         LogDebug("Market closed (Friday evening) for " + symbol);
         return false;
      }
      if(dayOfWeek == 0 && currentHour < 22) {
         LogDebug("Market closed (Sunday) for " + symbol);
         return false;
      }
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Helper function to remove "+" suffix from symbol                  |
//+------------------------------------------------------------------+
string GetBaseSymbol(string symbol) {
   // Remove the "+" suffix if it exists
   int plusPos = StringFind(symbol, "+");
   if(plusPos != -1) {
      return StringSubstr(symbol, 0, plusPos);
   }
   return symbol;
}

//+------------------------------------------------------------------+
//| Emergency close check                                             |
//+------------------------------------------------------------------+
void CheckEmergencyClose() {
   for(int i = 0; i < OrdersTotal(); i++) {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
         // Calculate current loss percentage
         double openPrice = OrderOpenPrice();
         double currentPrice = OrderType() == OP_BUY ? MarketInfo(OrderSymbol(), MODE_BID) : MarketInfo(OrderSymbol(), MODE_ASK);
         double priceChange = OrderType() == OP_BUY ? currentPrice - openPrice : openPrice - currentPrice;
         double lossPercentage = (priceChange / openPrice) * 100;
         
         // If loss exceeds emergency threshold, close immediately
         if(lossPercentage <= -EMERGENCY_CLOSE_PERCENT) {
            LogError("EMERGENCY CLOSE triggered for " + OrderSymbol() + 
                      "\nLoss: " + DoubleToString(lossPercentage, 2) + "%" +
                      "\nClosing position immediately!");
            
            if(!CloseCurrentPosition(OrderSymbol())) {
               LogError("CRITICAL ERROR: Failed to execute emergency close!");
            }
         }
      }
   }
}