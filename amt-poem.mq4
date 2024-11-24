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
extern bool   USE_SIGNAL_SL_TP = true;               // Use Stop Loss and Take Profit from signal
extern bool   DEBUG_MODE = true;                      // Print debug messages
extern string TIMEFRAME = "240";                      // Timeframe parameter for API
extern int    MAX_SLIPPAGE = 5;                      // Maximum allowed slippage in points
extern int    PRICE_DIGITS = 5;                      // Decimal places for price display (5 for forex, 3 for JPY pairs)
extern double RISK_PERCENT = 3.0;                    // Risk percentage per trade (3%)

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
   // SymbolSelect("USDJPY+", true);
   SymbolSelect("BTCUSD", true);
   SymbolSelect("ETHUSD", true);
   
   PrintDebug("EA Initialized with Risk: " + DoubleToString(RISK_PERCENT, 2) + "%");
   PrintDebug("Account Balance: " + DoubleToString(AccountBalance(), 2));
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   PrintDebug("EA Deinitialized. Reason: " + IntegerToString(reason));
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick() {
   if (!IsTimeToCheck()) return;
   
   string currentSymbol = Symbol();
   PrintDebug("Bid Price: " + DoubleToString(MarketInfo(currentSymbol, MODE_BID), 5));

   string url = StringFormat("%s?pairs=%s&tf=%s", API_URL, currentSymbol, TIMEFRAME);
   
   PrintDebug("Checking for new signals: " + currentSymbol);
   
   string response = FetchSignals(url);
   if (response == "") return;
   
   SignalData signal;
   if (ParseSignal(response, signal)) {
      ProcessSignal(signal);
   }
   
   lastCheck = TimeCurrent();
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
      PrintDebug("Error in WebRequest. Error code: " + IntegerToString(errorCode));
      return "";
   }
   
   string response = CharArrayToString(result);
   PrintDebug("API Response: " + response);
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
   signal.ticker = GetJsonValue(json, "ticker") + "+"; 
   signal.action = GetJsonValue(json, "action");
   signal.price = StringToDouble(GetJsonValue(json, "price"));
   signal.stopLoss = StringToDouble(GetJsonValue(json, "stopLoss"));
   signal.takeProfit = StringToDouble(GetJsonValue(json, "takeProfit"));
   signal.timestamp = GetJsonValue(json, "timestamp");
   signal.pattern = GetJsonValue(json, "signalPattern");
   
   PrintDebug("Parsed Signal - Action: " + signal.action + " Pattern: " + signal.pattern);
   return true;

   PrintDebug("Parsed values - Price: " + DoubleToString(signal.price, 5) + 
           " StopLoss: " + DoubleToString(signal.stopLoss, 5) + 
           " TakeProfit: " + DoubleToString(signal.takeProfit, 5));
}

//+------------------------------------------------------------------+
//| Calculate position size based on risk percentage                   |
//+------------------------------------------------------------------+
double CalculatePositionSize(string symbol, double entryPrice, double stopLoss) {
   double accountBalance = AccountBalance();
   double maxRiskAmount = accountBalance * (RISK_PERCENT / 100);
   
   // Stop Loss distance in points
   double stopDistance = MathAbs(entryPrice - stopLoss);
   bool isJPYPair = (StringFind(symbol, "JPY") >= 0);
   int digits = isJPYPair ? 3 : 5;
   
   // Convert to pips based on pair type
   double pips;
   if(isJPYPair) {
      pips = stopDistance * 100; // For JPY pairs, multiply by 100 to get pips
   } else {
      pips = stopDistance * 10000; // For other pairs, multiply by 10000 to get pips
   }
   
   // Get tick value
   double tickValue = MarketInfo(symbol, MODE_TICKVALUE);
   if(tickValue == 0) return MarketInfo(symbol, MODE_MINLOT);
   
   // Calculate pip value and lot size
   double pipValue = tickValue * (isJPYPair ? 100 : 10000);
   double lotSize = maxRiskAmount / (pips * pipValue);
   
   // Round to broker's lot step
   double lotStep = MarketInfo(symbol, MODE_LOTSTEP);
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   
   // Ensure within broker's limits
   double minLot = MarketInfo(symbol, MODE_MINLOT);
   double maxLot = MarketInfo(symbol, MODE_MAXLOT);
   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
   
   // Debug output
   PrintDebug("Position Size Calculation for " + symbol + ":" +
              "\nAccount Balance: $" + DoubleToString(accountBalance, 2) +
              "\nMax Risk Amount: $" + DoubleToString(maxRiskAmount, 2) +
              "\nEntry Price: " + DoubleToString(entryPrice, digits) +
              "\nStop Loss: " + DoubleToString(stopLoss, digits) +
              "\nStop Distance (pips): " + DoubleToString(pips, 1) +
              "\nIs JPY Pair: " + (isJPYPair ? "Yes" : "No") +
              "\nTick Value: " + DoubleToString(tickValue, 5) +
              "\nPip Value: " + DoubleToString(pipValue, 5) +
              "\nCalculated Lot Size: " + DoubleToString(lotSize, 2));
   
   return lotSize;
}

//+------------------------------------------------------------------+
//| Process trading signal                                            |
//+------------------------------------------------------------------+
void ProcessSignal(SignalData &signal) {

   if(MarketInfo(signal.ticker, MODE_BID) == 0) {
      PrintDebug("Error: Invalid symbol " + signal.ticker);
      return;
   }

   if (signal.timestamp == lastSignalTimestamp) {
      PrintDebug("Signal already processed for: " + signal.timestamp);
      return;
   }
   
   int cmd = -1;
   if (signal.action == "BUY") cmd = OP_BUY;
   else if (signal.action == "SELL") cmd = OP_SELL;
   else {
      PrintDebug("NEUTRAL signal received - no action taken");
      return;
   }
   
   // Handle existing positions
   if (HasOpenPosition(signal.ticker)) {
      int currentPositionType = GetOpenPositionType(signal.ticker);
      
      if ((cmd == OP_BUY && currentPositionType == OP_SELL) || 
          (cmd == OP_SELL && currentPositionType == OP_BUY)) {
          
          PrintDebug("Closing existing " + (currentPositionType == OP_BUY ? "BUY" : "SELL") + 
                     " position before opening new " + signal.action + " position");
                     
          if (!CloseCurrentPosition(signal.ticker)) {
              PrintDebug("Failed to close existing position - new position not opened");
              return;
          }
      } else {
          PrintDebug("Position already exists in same direction - no action taken");
          return;
      }
   }
   
   // Get current market prices
   double ask = MarketInfo(signal.ticker, MODE_ASK);
   double bid = MarketInfo(signal.ticker, MODE_BID);
   double price = cmd == OP_BUY ? ask : bid;
   
   // Calculate position size based on risk
   double sl = USE_SIGNAL_SL_TP ? signal.stopLoss : 0;
   double tp = USE_SIGNAL_SL_TP ? signal.takeProfit : 0;
   
   // Only calculate position size if we have a stop loss
   double lotSize;
   if (sl != 0) {
      lotSize = CalculatePositionSize(signal.ticker, price, sl);
      PrintDebug("Calculated position size: " + DoubleToString(lotSize, 2) + 
                 " lots based on " + DoubleToString(RISK_PERCENT, 2) + "% risk");
   } else {
      PrintDebug("Warning: No stop loss provided - using minimum lot size");
      lotSize = MarketInfo(signal.ticker, MODE_MINLOT);
   }
   
   int digits = (StringFind(signal.ticker, "JPY") >= 0) ? 3 : 5;
   
   PrintDebug("Placing order:" +
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
      lotSize,               // Lot size (now calculated based on risk)
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
      PrintDebug("OrderSend error: " + IntegerToString(error) + 
                 "\nDescription: " + ErrorDescription(error) +
                 "\nSymbol: " + signal.ticker +
                 "\nLots: " + DoubleToString(lotSize, 2) +
                 "\nPrice: " + DoubleToString(price, digits));
   } else {
      PrintDebug("Order placed successfully" +
                 "\nTicket: " + IntegerToString(ticket) +
                 "\nSymbol: " + signal.ticker +
                 "\nType: " + signal.action +
                 "\nLots: " + DoubleToString(lotSize, 2) +
                 "\nPrice: " + DoubleToString(price, digits));
      lastSignalTimestamp = signal.timestamp;
   }
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
            double closePrice;
            int orderType = OrderType();
            
            if(orderType == OP_BUY) {
               closePrice = MarketInfo(symbol, MODE_BID);
            } else if(orderType == OP_SELL) {
               closePrice = MarketInfo(symbol, MODE_ASK);
            } else {
               continue;
            }
            
            PrintDebug("Attempting to close position:" +
                      "\nTicket: " + IntegerToString(OrderTicket()) +
                      "\nSymbol: " + symbol +
                      "\nType: " + (orderType == OP_BUY ? "BUY" : "SELL") +
                      "\nLots: " + DoubleToString(OrderLots(), 2) +
                      "\nClose Price: " + DoubleToString(closePrice, PRICE_DIGITS));
            
            bool result = OrderClose(
               OrderTicket(),
               OrderLots(),
               closePrice,
               MAX_SLIPPAGE,
               clrWhite
            );
            
            if(!result) {
               int error = GetLastError();
               PrintDebug("Failed to close position" +
                         "\nError: " + IntegerToString(error) +
                         "\nDescription: " + ErrorDescription(error));
               return false;
            }
            
            PrintDebug("Successfully closed position:" +
                      "\nSymbol: " + symbol +
                      "\nProfit: " + DoubleToString(OrderProfit(), 2));
            return true;
         }
      }
   }
   return false;
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
//| Debug print function                                              |
//+------------------------------------------------------------------+
void PrintDebug(string message) {
   if (DEBUG_MODE) {
      Print(TimeToString(TimeCurrent()) + " | " + message);
   }
}