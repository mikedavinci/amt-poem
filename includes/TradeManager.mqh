//+------------------------------------------------------------------+
//|                                                  TradeManager.mqh   |
//|                                                      TradeJourney  |
//|                                          https://tradejourney.ai   |
//+------------------------------------------------------------------+
#property copyright "TradeJourney"
#property link      "https://tradejourney.ai"
#property strict

#include "Constants.mqh"
#include "Structures.mqh"
#include "SymbolInfo.mqh"
#include "RiskManager.mqh"
#include "Logger.mqh"

//+------------------------------------------------------------------+
//| Class for managing trade operations and position tracking          |
//+------------------------------------------------------------------+
class CTradeManager {
private:
    // Member variables
    CSymbolInfo*    m_symbolInfo;            // Symbol information
    CRiskManager*    m_riskManager;        // Risk management
    TradeRecord     m_lastTrade;             // Last trade record
    int             m_slippage;              // Maximum allowed slippage
    int             m_maxRetries;            // Maximum retry attempts
    bool            m_isTradeAllowed;        // Trade permission flag
    bool            m_awaitingOppositeSignal; // New flag for signal management
    ENUM_TRADE_SIGNAL m_lastClosedDirection;  // Track last closed position direction
    string          m_currentSymbol;         // Current symbol being traded
    datetime        m_lastCheck;             // Last check timestamp
    datetime        m_lastSignalTimestamp;   // Last signal timestamp

     string GetSymbol() const {
        return m_symbolInfo ? m_symbolInfo.GetSymbol() : "";
    }

    bool ValidateSymbol() const {
        if(!m_symbolInfo) {
            Logger.Error("Symbol info not initialized");
            return false;
        }
        
        string symbol = GetSymbol();
        if(symbol != Symbol()) {
            Logger.Error(StringFormat(
                "Symbol mismatch - Current: %s, MT4: %s",
                symbol, Symbol()));
            return false;
        }
        return true;
    }

    void SaveTradeState() {
        if(m_symbolInfo.GetSymbol() != Symbol()) return;
        
        string symbolPrefix = GLOBAL_VAR_PREFIX + Symbol() + "_";
        datetime currentTime = TimeCurrent();  // Get current time explicitly
        
        // Add timestamp saves
        GlobalVariableSet(symbolPrefix + "LAST_CHECK_TIME", (double)currentTime);
        GlobalVariableSet(symbolPrefix + "LAST_SIGNAL_TIME", (double)m_lastSignalTimestamp);
        
        GlobalVariableSet(symbolPrefix + "AWAITING_OPPOSITE", m_awaitingOppositeSignal ? 1 : 0);
        GlobalVariableSet(symbolPrefix + "LAST_DIRECTION", (double)m_lastClosedDirection);
        
        // Save last trade info
        GlobalVariableSet(symbolPrefix + "LAST_TRADE_TICKET", m_lastTrade.ticket);
        GlobalVariableSet(symbolPrefix + "LAST_TRADE_TYPE", (double)m_lastTrade.direction);
        GlobalVariableSet(symbolPrefix + "LAST_TRADE_LOTS", m_lastTrade.lots);
        GlobalVariableSet(symbolPrefix + "LAST_TRADE_PRICE", m_lastTrade.openPrice);
        
        Logger.Debug(StringFormat(
            "Saved trade state at %s - AwaitingOpposite: %s, LastDirection: %s",
            TimeToString(currentTime),
            m_awaitingOppositeSignal ? "Yes" : "No",
            m_lastClosedDirection == SIGNAL_BUY ? "BUY" : "SELL"));
    }
    
void LoadTradeState() {
    if(m_symbolInfo.GetSymbol() != Symbol()) return;
    
    string symbolPrefix = GLOBAL_VAR_PREFIX + Symbol() + "_";
    
    // Load timestamps with validation
    if(GlobalVariableCheck(symbolPrefix + "LAST_CHECK_TIME")) {
        double lastCheckValue = GlobalVariableGet(symbolPrefix + "LAST_CHECK_TIME");
        if(lastCheckValue > 0) {  
            m_lastCheck = (datetime)lastCheckValue;
        }
    }
    
    if(GlobalVariableCheck(symbolPrefix + "LAST_SIGNAL_TIME")) {
        double lastSignalValue = GlobalVariableGet(symbolPrefix + "LAST_SIGNAL_TIME");
        if(lastSignalValue > 0) {  
            m_lastSignalTimestamp = (datetime)lastSignalValue;
        }
    }
    
     // Load awaiting opposite signal state
    if(GlobalVariableCheck(symbolPrefix + "AWAITING_OPPOSITE")) {
        m_awaitingOppositeSignal = (GlobalVariableGet(symbolPrefix + "AWAITING_OPPOSITE") == 1);
        Logger.Debug(StringFormat(
            "Loaded awaiting opposite signal state: %s",
            m_awaitingOppositeSignal ? "Yes" : "No"
        ));
    }
    
    // Load last closed direction
    if(GlobalVariableCheck(symbolPrefix + "LAST_DIRECTION")) {
        double directionValue = GlobalVariableGet(symbolPrefix + "LAST_DIRECTION");
        if(directionValue == SIGNAL_BUY || directionValue == SIGNAL_SELL) {
            m_lastClosedDirection = (ENUM_TRADE_SIGNAL)((int)directionValue);
            Logger.Debug(StringFormat(
                "Loaded last closed direction: %s",
                m_lastClosedDirection == SIGNAL_BUY ? "BUY" : "SELL"
            ));
        }
    }
        
    // Load last trade if ticket exists
    if(GlobalVariableCheck(symbolPrefix + "LAST_TRADE_TICKET")) {
        m_lastTrade.ticket = (int)GlobalVariableGet(symbolPrefix + "LAST_TRADE_TICKET");
        m_lastTrade.direction = (ENUM_TRADE_SIGNAL)((int)GlobalVariableGet(symbolPrefix + "LAST_TRADE_TYPE"));
        m_lastTrade.lots = GlobalVariableGet(symbolPrefix + "LAST_TRADE_LOTS");
        m_lastTrade.openPrice = GlobalVariableGet(symbolPrefix + "LAST_TRADE_PRICE");
    }
        
    Logger.Debug(StringFormat(
        "Trade state loaded:" +
        "\nAwaiting Opposite: %s" +
        "\nLast Direction: %s",
        m_awaitingOppositeSignal ? "Yes" : "No",
        m_lastClosedDirection == SIGNAL_BUY ? "BUY" : "SELL"
    ));
}

    // Private Methods for Trade Validation
    bool CanOpenNewPosition(ENUM_TRADE_SIGNAL newSignal) {
        if(!m_awaitingOppositeSignal) return true;

        Logger.Debug(StringFormat(
            "Validating new position:" +
            "\nNew Signal: %s" +
            "\nLast Closed: %s" +
            "\nAwaiting Opposite: %s",
            newSignal == SIGNAL_BUY ? "BUY" : "SELL",
            m_lastClosedDirection == SIGNAL_BUY ? "BUY" : "SELL",
            m_awaitingOppositeSignal ? "Yes" : "No"
        ));

        // Only allow if signal is opposite to last closed position
        if(m_lastClosedDirection == SIGNAL_BUY && newSignal == SIGNAL_SELL) {
            m_awaitingOppositeSignal = false;
            SaveTradeState();  // Add this to persist state change
            Logger.Info("Opposite signal (SELL) received after BUY exit - allowing trade");
            return true;
        }
        if(m_lastClosedDirection == SIGNAL_SELL && newSignal == SIGNAL_BUY) {
            m_awaitingOppositeSignal = false;
            SaveTradeState();  // Add this to persist state change
            Logger.Info("Opposite signal (BUY) received after SELL exit - allowing trade");
            return true;
        }

        Logger.Warning(StringFormat(
            "Trade rejected - Awaiting %s signal after %s exit",
            m_lastClosedDirection == SIGNAL_BUY ? "SELL" : "BUY",
            m_lastClosedDirection == SIGNAL_BUY ? "Bullish" : "Bearish"
        ));
        return false;
    }

    bool ValidateEntryPrice(double signalPrice, double currentPrice, int type) {
        if(signalPrice <= 0 || currentPrice <= 0) return false;

        // Select tolerance based on instrument
        double tolerance = FOREX_ENTRY_TOLERANCE_PERCENT;
        string symbol = m_symbolInfo.GetSymbol();
        
        if(StringFind(symbol, "BTC") >= 0) {
            tolerance = BTC_ENTRY_TOLERANCE_PERCENT;
        }
        else if(StringFind(symbol, "ETH") >= 0) {
            tolerance = ETH_ENTRY_TOLERANCE_PERCENT;
        }
        else if(StringFind(symbol, "LTC") >= 0) {
            tolerance = LTC_ENTRY_TOLERANCE_PERCENT;
        }

        double deviation = MathAbs(1 - (currentPrice / signalPrice)) * 100;

        // Log the deviation check
        Logger.Debug(StringFormat(
            "Price Deviation Check:" +
            "\nSymbol: %s" +
            "\nTolerance: %.1f%%" +
            "\nDeviation: %.2f%%" +
            "\nSignal Price: %.5f" +
            "\nCurrent Price: %.5f",
            symbol,
            tolerance,
            deviation,
            signalPrice,
            currentPrice
        ));

        // If price has moved too far from signal price, reject entry
        if(deviation > tolerance) {
            Logger.Warning(StringFormat(
                "Entry price deviation too high: %.2f%%. Signal: %.5f, Current: %.5f",
                deviation, signalPrice, currentPrice));
            return false;
        }

        return true;
    }

bool ExecuteMarketOrder(int type, double lots, double signalPrice, double sl,
                       double tp, string comment, const SignalData& signal) {
    int ticket = -1;
    int attempts = 0;
    bool success = false;

    if(comment == NULL) comment = "";
    if(StringLen(comment) > 31) {
        comment = StringSubstr(comment, 0, 31);
    }

    double currentPrice = (type == OP_BUY) ? m_symbolInfo.GetAsk() : m_symbolInfo.GetBid();

    if(!m_riskManager.ValidateNewPosition(lots, currentPrice, sl, type)) {
        Logger.Warning(StringFormat(
            "Order rejected - Risk validation failed:" +
            "\nDirection: %s" +
            "\nLots: %.2f" +
            "\nPrice: %.5f" +
            "\nStop Loss: %.5f",
            type == OP_BUY ? "BUY" : "SELL",
            lots,
            currentPrice,
            sl
        ));
        return false;
    }

    while(attempts < m_maxRetries && !success) {
        if(attempts > 0) {
            RefreshRates();
            int delay = MathMin(INITIAL_RETRY_DELAY * (attempts + 1), MAX_RETRY_DELAY);
            Sleep(delay);
            currentPrice = (type == OP_BUY) ? m_symbolInfo.GetAsk() : m_symbolInfo.GetBid();
        }

        if(!ValidateEntryPrice(signalPrice, currentPrice, type)) {
            Logger.Error("Price moved too far from signal price");
            return false;
        }

        // Updated stop loss logic
        double newStopLoss;
        if(type == OP_BUY) {
            // For BUY positions, use sl2 as stop loss
            if(signal.sl2 > 0) {
                newStopLoss = signal.sl2;
                Logger.Debug(StringFormat("BUY Position: Using SL2 for stop loss: %.5f", newStopLoss));
            } else {
                Logger.Error("BUY Signal missing SL2 value for stop loss");
                return false;
            }
        } else {
            // For SELL positions, use sl2 as stop loss
            if(signal.sl2 > 0) {
                newStopLoss = signal.sl2;
                Logger.Debug(StringFormat("SELL Position: Using SL2 for stop loss: %.5f", newStopLoss));
            } else {
                Logger.Error("SELL Signal missing SL2 value for stop loss");
                return false;
            }
        }

        // Validate stop loss
        if(type == OP_BUY && (newStopLoss >= currentPrice)) {
            Logger.Error(StringFormat(
                "Invalid BUY stop loss - Must be below entry price:" +
                "\nEntry: %.5f" +
                "\nStop Loss: %.5f",
                currentPrice, newStopLoss));
            return false;
        }
        if(type == OP_SELL && (newStopLoss <= currentPrice)) {
            Logger.Error(StringFormat(
                "Invalid SELL stop loss - Must be above entry price:" +
                "\nEntry: %.5f" +
                "\nStop Loss: %.5f",
                currentPrice, newStopLoss));
            return false;
        }

        if(!m_symbolInfo.ValidateStopLoss(type, currentPrice, newStopLoss)) {
            Logger.Error(StringFormat(
                "Invalid stop loss calculated - Price: %.5f, SL: %.5f",
                currentPrice, newStopLoss));
            return false;
        }

        ticket = OrderSend(
            m_symbolInfo.GetSymbol(),
            type,
            lots,
            currentPrice,
            m_slippage,
            newStopLoss,
            tp,
            comment,
            0,
            0,
            type == OP_BUY ? clrGreen : clrRed
        );

        if(ticket > 0) {
            success = true;
            RecordTrade(ticket, type, lots, currentPrice, newStopLoss, tp, comment);
            Logger.Trade(StringFormat(
                "Order executed successfully:" +
                "\nTicket: %d" +
                "\nType: %s" +
                "\nPrice: %.5f" +
                "\nStop Loss: %.5f" +
                "\nComment: %s",
                ticket,
                type == OP_BUY ? "BUY" : "SELL",
                currentPrice,
                newStopLoss,
                comment
            ));
        } else {
            int error = GetLastError();
            LogTradeError(StringFormat("Order execution failed (Attempt %d/%d)",
                         attempts + 1, m_maxRetries), error);
            attempts++;
        }
    }
    return success;
}

bool CheckEmergencyStop(double currentPrice, double openPrice, int orderType) {
        if(m_symbolInfo.IsCryptoPair()) {
            double emergencyDistance = openPrice * (CRYPTO_EMERGENCY_STOP_PERCENT / 100.0);
            
            if(orderType == OP_BUY && currentPrice < openPrice - emergencyDistance) {
                Logger.Warning(StringFormat(
                    "Emergency stop triggered for BUY:" +
                    "\nOpen Price: %.5f" +
                    "\nCurrent Price: %.5f" +
                    "\nEmergency Distance: %.5f",
                    openPrice, currentPrice, emergencyDistance));
                return true;
            }
            if(orderType == OP_SELL && currentPrice > openPrice + emergencyDistance) {
                Logger.Warning(StringFormat(
                    "Emergency stop triggered for SELL:" +
                    "\nOpen Price: %.5f" +
                    "\nCurrent Price: %.5f" +
                    "\nEmergency Distance: %.5f",
                    openPrice, currentPrice, emergencyDistance));
                return true;
            }
        } else {
            double emergencyDistance = FOREX_EMERGENCY_PIPS * m_symbolInfo.GetPipSize();
            
            if(orderType == OP_BUY && currentPrice < openPrice - emergencyDistance) {
                Logger.Warning(StringFormat(
                    "Emergency stop triggered for BUY:" +
                    "\nOpen Price: %.5f" +
                    "\nCurrent Price: %.5f" +
                    "\nEmergency Distance: %.5f",
                    openPrice, currentPrice, emergencyDistance));
                return true;
            }
            if(orderType == OP_SELL && currentPrice > openPrice + emergencyDistance) {
                Logger.Warning(StringFormat(
                    "Emergency stop triggered for SELL:" +
                    "\nOpen Price: %.5f" +
                    "\nCurrent Price: %.5f" +
                    "\nEmergency Distance: %.5f",
                    openPrice, currentPrice, emergencyDistance));
                return true;
            }
        }
        return false;
}

void CheckTrailingStop() {
    if(!HasOpenPosition()) return;

    for(int i = OrdersTotal() - 1; i >= 0; i--) {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
            if(OrderSymbol() == m_currentSymbol) {
                int orderType = OrderType();
                double currentPrice = orderType == OP_BUY ?
                    m_symbolInfo.GetBid() : m_symbolInfo.GetAsk();
                double openPrice = OrderOpenPrice();
                double currentStop = OrderStopLoss();

                // First check emergency stop
                if(CheckEmergencyStop(currentPrice, openPrice, orderType)) {
                    ClosePosition(OrderTicket(), "EMERGENCY");
                    continue;
                }
            }
        }
    }
}

    void RecordTrade(int ticket, int type, double lots, double price,
                         double sl, double tp, string comment) {
            if(OrderSelect(ticket, SELECT_BY_TICKET)) {
                m_lastTrade.ticket = ticket;
                m_lastTrade.symbol = m_symbolInfo.GetSymbol();
                m_lastTrade.direction = type == OP_BUY ? SIGNAL_BUY : SIGNAL_SELL;
                m_lastTrade.lots = lots;
                m_lastTrade.openPrice = price;
                m_lastTrade.stopLoss = sl;
                m_lastTrade.openTime = TimeCurrent();
                m_lastTrade.comment = comment;
            }
        }

        void LogTradeError(string operation, int errorCode) {
            string message = StringFormat("%s: Error %d - %s", operation, errorCode);
            Logger.Error(message);
        }

        bool CloseExistingPositions(ENUM_TRADE_SIGNAL newSignal) {
            bool allClosed = true;
            int total = OrdersTotal();
            int closedCount = 0;

            Logger.Info(StringFormat("Closing existing positions for new %s signal",
                        newSignal == SIGNAL_BUY ? "BUY" : "SELL"));

            for(int i = total - 1; i >= 0; i--) {
                if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
                    if(OrderSymbol() == m_symbolInfo.GetSymbol()) {
                        ENUM_TRADE_SIGNAL currentPos =
                            (OrderType() == OP_BUY) ? SIGNAL_BUY : SIGNAL_SELL;

                        // Close if signals are opposite
                        if(currentPos != newSignal) {
                            double closePrice = OrderType() == OP_BUY ?
                                m_symbolInfo.GetBid() : m_symbolInfo.GetAsk();

                            Logger.Trade(StringFormat(
                                "Closing position for signal reversal:" +
                                "\nTicket: %d" +
                                "\nType: %s" +
                                "\nLots: %.2f" +
                                "\nOpen Price: %.5f" +
                                "\nClose Price: %.5f" +
                                "\nProfit: %.2f",
                                OrderTicket(),
                                OrderType() == OP_BUY ? "BUY" : "SELL",
                                OrderLots(),
                                OrderOpenPrice(),
                                closePrice,
                                OrderProfit()
                            ));

                            if(!ClosePosition(OrderTicket(), "Signal reversal")) {
                                allClosed = false;
                                Logger.Error(StringFormat("Failed to close position %d for reversal",
                                    OrderTicket()));
                            } else {
                                closedCount++;
                            }
                        }
                    }
                }
            }

            if(closedCount > 0) {
                Logger.Info(StringFormat("Closed %d positions for signal reversal", closedCount));
            }

            return allClosed;
        }

        ENUM_CLOSE_REASON StringToCloseReason(string reason) {
            if(reason == "SL") return CLOSE_SL;
            if(reason == "TP") return CLOSE_TP;
            if(reason == "EMERGENCY") return CLOSE_EMERGENCY;
            if(reason == "PROFIT_PROTECTION") return CLOSE_PROFIT_PROTECTION;
            if(StringFind(reason, "Exit Signal") >= 0) return CLOSE_EXIT_SIGNAL;  
            return CLOSE_MANUAL;
        }

        // Add new member variables
    bool m_partialExitTaken;
    double m_originalPositionSize;

    void SavePartialExitState(bool taken) {
        string symbolPrefix = GLOBAL_VAR_PREFIX + m_symbolInfo.GetSymbol() + "_";
        GlobalVariableSet(symbolPrefix + "PARTIAL_EXIT_TAKEN", taken ? 1 : 0);
    }

    bool LoadPartialExitState() {
        string symbolPrefix = GLOBAL_VAR_PREFIX + m_symbolInfo.GetSymbol() + "_";
        return GlobalVariableGet(symbolPrefix + "PARTIAL_EXIT_TAKEN") == 1;
    }

    void SaveOriginalSize(double size) {
        string symbolPrefix = GLOBAL_VAR_PREFIX + m_symbolInfo.GetSymbol() + "_";
        GlobalVariableSet(symbolPrefix + "ORIGINAL_POSITION_SIZE", size);
    }

    double LoadOriginalSize() {
        string symbolPrefix = GLOBAL_VAR_PREFIX + m_symbolInfo.GetSymbol() + "_";
        return GlobalVariableGet(symbolPrefix + "ORIGINAL_POSITION_SIZE");
    }

public:
    // Constructor
    CTradeManager(CSymbolInfo* symbolInfo, CRiskManager* riskManager, int slippage = DEFAULT_SLIPPAGE,
                  int maxRetries = MAX_RETRY_ATTEMPTS)
        : m_symbolInfo(symbolInfo),
          m_riskManager(riskManager),
          m_slippage(slippage),
          m_maxRetries(maxRetries) {
        m_isTradeAllowed = true;
        m_currentSymbol = m_symbolInfo.GetSymbol();
        LoadTradeState();
    }

    bool HasOpenPositionInDirection(ENUM_TRADE_SIGNAL direction) {
        int total = OrdersTotal();
        for(int i = 0; i < total; i++) {
            if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
                if(OrderSymbol() == m_symbolInfo.GetSymbol()) {
                    ENUM_TRADE_SIGNAL posDirection =
                        (OrderType() == OP_BUY) ? SIGNAL_BUY : SIGNAL_SELL;
                    if(posDirection == direction) return true;
                }
            }
        }
        return false;
    }

void ProcessExitSignal(const SignalData& signal) {
   Logger.Info(StringFormat("Processing exit signal for %s - Type: %s, TP Price: %.5f", 
       m_symbolInfo.GetSymbol(),
       signal.exitType == EXIT_BULLISH ? "BULLISH" : "BEARISH",
       signal.price));

   for(int i = OrdersTotal() - 1; i >= 0; i--) {
       if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
           if(OrderSymbol() == m_symbolInfo.GetSymbol()) {
               // Check if the exit signal matches position type
               bool matchingExit = (OrderType() == OP_BUY && signal.exitType == EXIT_BULLISH) ||
                                 (OrderType() == OP_SELL && signal.exitType == EXIT_BEARISH);
               
               if(matchingExit) {
                   // Load partial exit state
                   bool partialExitTaken = LoadPartialExitState();
                   double originalSize = LoadOriginalSize();
                   
                   // First exit signal - partial exit
                   if(!partialExitTaken) {
                       double currentLots = OrderLots();
                       SaveOriginalSize(currentLots); // Save original size
                       double partialLots = NormalizeDouble(currentLots * (PARTIAL_EXIT_PERCENT / 100.0), 2);
                       
                       if(ClosePartialPosition(OrderTicket(), partialLots, "Partial Exit Signal")) {
                           SavePartialExitState(true);
                           Logger.Info(StringFormat(
                               "Partial exit executed:" +
                               "\nTicket: %d" +
                               "\nOriginal Size: %.2f" +
                               "\nClosed Size: %.2f (%.1f%%)" +
                               "\nRemaining: %.2f (%.1f%%)",
                               OrderTicket(),
                               currentLots,
                               partialLots,
                               PARTIAL_EXIT_PERCENT,
                               currentLots - partialLots,
                               REMAINING_VOLUME_PERCENT
                           ));
                       }
                   }
                   // Second exit signal - close remaining position
                   else {
                       if(ClosePosition(OrderTicket(), "Full Exit Signal")) {
                           // m_awaitingOppositeSignal is set inside ClosePosition
                           // Update last closed direction
                           m_lastClosedDirection = OrderType() == OP_BUY ? SIGNAL_BUY : SIGNAL_SELL;
                           
                           // Reset partial exit state
                           SavePartialExitState(false);
                           SaveOriginalSize(0);
                           
                           Logger.Info(StringFormat(
                               "Closed remaining position:" +
                               "\nTicket: %d" +
                               "\nDirection: %s" +
                               "\nClose Price: %.5f" +
                               "\nAwaiting opposite signal set to: %s" +
                               "\nLast closed direction: %s",
                               OrderTicket(),
                               OrderType() == OP_BUY ? "BUY" : "SELL",
                               OrderType() == OP_BUY ? m_symbolInfo.GetBid() : m_symbolInfo.GetAsk(),
                               m_awaitingOppositeSignal ? "YES" : "NO",
                               m_lastClosedDirection == SIGNAL_BUY ? "BUY" : "SELL"
                           ));
                           SaveTradeState();
                       }
                   }
               } else {
                   Logger.Debug(StringFormat(
                       "Exit signal does not match position:" +
                       "\nPosition: %s" +
                       "\nExit Type: %s" +
                       "\nTicket: %d",
                       OrderType() == OP_BUY ? "BUY" : "SELL",
                       signal.exitType == EXIT_BULLISH ? "BULLISH" : "BEARISH",
                       OrderTicket()
                   ));
               }
           }
       }
   }
}

bool ClosePartialPosition(int ticket, double lots, string reason = "") {
        if(!OrderSelect(ticket, SELECT_BY_POS, MODE_TRADES)) {
            Logger.Error("Failed to select order for partial close");
            return false;
        }

        double closePrice = OrderType() == OP_BUY ? m_symbolInfo.GetBid() : m_symbolInfo.GetAsk();
        bool success = OrderClose(ticket, lots, closePrice, m_slippage, clrRed);

        if(success) {
            Logger.Trade(StringFormat(
                "Partial position closed:" +
                "\nTicket: %d" +
                "\nLots Closed: %.2f" +
                "\nClose Price: %.5f" +
                "\nReason: %s",
                ticket,
                lots,
                closePrice,
                reason
            ));
        } else {
            LogTradeError("Partial close failed", GetLastError());
        }

        return success;
    }
    
    // Trade Execution Methods
bool OpenBuyPosition(double lots, double sl, double tp, string comment, const SignalData& signal) {

     if(!m_symbolInfo || !m_riskManager) {
        Logger.Error("Dependencies not initialized in OpenBuyPosition");
        return false;
    }

        // Validate symbol
        if(m_symbolInfo.GetSymbol() != Symbol()) {
            Logger.Error(StringFormat(
                "Symbol mismatch in OpenBuyPosition - Expected: %s, Got: %s",
                Symbol(), m_symbolInfo.GetSymbol()));
            return false;
        }

        if(!CanTrade()) return false;

        Logger.Debug(StringFormat(
            "Buy Position Request:" +
            "\nAwaiting Opposite: %s" +
            "\nLast Closed Direction: %s",
            m_awaitingOppositeSignal ? "Yes" : "No",
            m_lastClosedDirection == SIGNAL_BUY ? "BUY" : "SELL"
        ));

        if(!CanOpenNewPosition(SIGNAL_BUY)) {
            Logger.Warning(StringFormat(
                "Buy position rejected - Awaiting opposite signal after %s position stop loss",
                m_lastClosedDirection == SIGNAL_BUY ? "BUY" : "SELL"
            ));
            return false;
        }

        // Check for existing buy position
        if(HasOpenPositionInDirection(SIGNAL_BUY)) {
            Logger.Warning("Buy position already exists - skipping");
            return false;
        }

        // Close any existing sell positions first
        if(HasOpenPosition()) {
            if(!CloseExistingPositions(SIGNAL_BUY)) {
                Logger.Error("Failed to close existing positions before buy");
                return false;
            }
        }

        double price = m_symbolInfo.GetAsk();
        if(!m_symbolInfo.ValidateStopLoss(OP_BUY, price, sl)) {
            Logger.Error("Invalid stop loss for buy order");
            return false;
        }

        bool result = ExecuteMarketOrder(OP_BUY, lots, signal.price, sl, tp, comment, signal);

        if(result) {
            SaveTradeState();
        }

        return result;
}

bool OpenSellPosition(double lots, double sl, double tp, string comment, const SignalData& signal) {

    if(!m_symbolInfo || !m_riskManager) {
        Logger.Error("Dependencies not initialized in OpenSellPosition");
        return false;
    }
    

        // Validate symbol
        if(m_symbolInfo.GetSymbol() != Symbol()) {
            Logger.Error(StringFormat(
                "Symbol mismatch in OpenSellPosition - Expected: %s, Got: %s",
                Symbol(), m_symbolInfo.GetSymbol()));
            return false;
        }

        if(!CanTrade()) return false;
        
        Logger.Debug(StringFormat(
            "Sell Position Request:" +
            "\nAwaiting Opposite: %s" +
            "\nLast Closed Direction: %s",
            m_awaitingOppositeSignal ? "Yes" : "No",
            m_lastClosedDirection == SIGNAL_BUY ? "BUY" : "SELL"
        ));

        if(!CanOpenNewPosition(SIGNAL_SELL)) {
            Logger.Warning(StringFormat(
                "Sell position rejected - Awaiting opposite signal after %s position stop loss",
                m_lastClosedDirection == SIGNAL_BUY ? "BUY" : "SELL"
            ));
            return false;
        }

        // Check for existing sell position
        if(HasOpenPositionInDirection(SIGNAL_SELL)) {
            Logger.Warning("Sell position already exists - skipping");
            return false;
        }

        // Close any existing buy positions first
        if(HasOpenPosition()) {
            if(!CloseExistingPositions(SIGNAL_SELL)) {
                Logger.Error("Failed to close existing positions before sell");
                return false;
            }
        }

        double price = m_symbolInfo.GetBid();
        if(!m_symbolInfo.ValidateStopLoss(OP_SELL, price, sl)) {
            Logger.Error("Invalid stop loss for sell order");
            return false;
        }

        bool result = ExecuteMarketOrder(OP_SELL, lots, signal.price, sl, tp, comment, signal);
        if(result) {
            SaveTradeState(); 
        }

        return result;
}

bool ClosePosition(int ticket, string reason = "") {
    if(m_symbolInfo.GetSymbol() != Symbol()) {
        Logger.Error(StringFormat(
            "Symbol mismatch in ClosePosition - Expected: %s, Got: %s",
            Symbol(), m_symbolInfo.GetSymbol()));
        return false;
    }

    if(!OrderSelect(ticket, SELECT_BY_TICKET)) {
        LogTradeError("Order select failed", GetLastError());
        return false;
    }

    // Store position details before closing
    ENUM_TRADE_SIGNAL currentDirection = OrderType() == OP_BUY ? SIGNAL_BUY : SIGNAL_SELL;
    double openPrice = OrderOpenPrice();
    double stopLoss = OrderStopLoss();
    double closePrice = OrderType() == OP_BUY ? m_symbolInfo.GetBid() : m_symbolInfo.GetAsk();
    
    Logger.Info(StringFormat(
        "Attempting to close position:" +
        "\nTicket: %d" +
        "\nReason: %s" +
        "\nDirection: %s" +
        "\nOpen Price: %.5f" +
        "\nStop Loss: %.5f" +
        "\nClose Price: %.5f",
        ticket, reason,
        currentDirection == SIGNAL_BUY ? "BUY" : "SELL",
        openPrice, stopLoss, closePrice
    ));

    bool success = OrderClose(ticket, OrderLots(), closePrice, m_slippage, clrRed);
    
    if(success) {
        // Update trade record
        m_lastTrade.closePrice = closePrice;
        m_lastTrade.closeTime = TimeCurrent();
        m_lastTrade.closeReason = StringToCloseReason(reason);
        m_lastTrade.profit = OrderProfit() + OrderSwap() + OrderCommission();

        // Always update last closed direction
        m_lastClosedDirection = currentDirection;
        
        // Only set awaiting opposite signal for full position closures
        // Check if this is a full exit signal or non-partial close
        bool isFullExit = (reason == "Full Exit Signal" || 
                          StringFind(reason, "Partial") == -1);
        
        if(isFullExit) {
            m_awaitingOppositeSignal = true;
            Logger.Info("Setting awaiting opposite signal after full position closure");
        } else {
            Logger.Info("Partial closure - not setting awaiting opposite signal");
        }

        // Determine close reason for logging
        string closeReasonStr;
        if(reason == "SL") closeReasonStr = "STOP LOSS";
        else if(reason == "EMERGENCY") closeReasonStr = "EMERGENCY STOP";
        else if(StringFind(reason, "Exit Signal") >= 0) closeReasonStr = "TAKE PROFIT EXIT";
        else if(StringFind(reason, "trailing") >= 0) closeReasonStr = "TRAILING STOP";
        else closeReasonStr = "MANUAL CLOSE";

        Logger.Trade(StringFormat(
            isFullExit ? "POSITION CLOSED - AWAITING OPPOSITE SIGNAL" : "PARTIAL POSITION CLOSED" +
            "\n----------------------------------------" +
            "\nSymbol: %s" +
            "\nTicket: %d" +
            "\nClose Reason: %s" +
            "\nClosed Direction: %s" +
            "\nEntry Price: %.5f" +
            "\nStop Loss: %.5f" +
            "\nClose Price: %.5f" +
            "\nP/L: %.2f" +
            "\nAwaiting Opposite: %s" +
            (isFullExit ? "\nNext Valid Direction: %s" : "") +
            "\nClose Time: %s",
            m_symbolInfo.GetSymbol(),
            ticket,
            closeReasonStr,
            currentDirection == SIGNAL_BUY ? "BUY" : "SELL",
            openPrice,
            stopLoss,
            closePrice,
            m_lastTrade.profit,
            m_awaitingOppositeSignal ? "YES" : "NO",
            isFullExit ? (currentDirection == SIGNAL_BUY ? "SELL ONLY" : "BUY ONLY") : "",
            TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS)
        ));
        
        SaveTradeState(); 
    } else {
        LogTradeError("Order close failed", GetLastError());
    }

    return success;
}

bool ModifyPosition(int ticket, double sl, double tp = 0) {
    // Validate symbol
    if(m_symbolInfo.GetSymbol() != Symbol()) {
        Logger.Error(StringFormat(
            "Symbol mismatch in ModifyPosition - Expected: %s, Got: %s",
            Symbol(), m_symbolInfo.GetSymbol()));
        return false;
    }

    if(!OrderSelect(ticket, SELECT_BY_TICKET)) {
        LogTradeError("Order select failed", GetLastError());
        return false;
    }

    // Get current position details
    double openPrice = OrderOpenPrice();
    double currentSL = OrderStopLoss();
    int orderType = OrderType();
    double currentPrice = orderType == OP_BUY ? m_symbolInfo.GetBid() : m_symbolInfo.GetAsk();

    // Emergency stop validation
    bool isEmergencyStop = false;
    if(m_symbolInfo.IsCryptoPair()) {
        double emergencyDistance = openPrice * (CRYPTO_EMERGENCY_STOP_PERCENT / 100.0);
        if(orderType == OP_BUY) {
            isEmergencyStop = currentPrice < openPrice - emergencyDistance;
        } else {
            isEmergencyStop = currentPrice > openPrice + emergencyDistance;
        }
    } else {
        double emergencyPips = FOREX_EMERGENCY_PIPS * m_symbolInfo.GetPipSize();
        if(orderType == OP_BUY) {
            isEmergencyStop = currentPrice < openPrice - emergencyPips;
        } else {
            isEmergencyStop = currentPrice > openPrice + emergencyPips;
        }
    }

    // Only proceed if this is an emergency stop modification
    if(!isEmergencyStop) {
        Logger.Warning(StringFormat(
            "Stop loss modification rejected - Not an emergency stop:" +
            "\nTicket: %d" +
            "\nDirection: %s" +
            "\nCurrent Price: %.5f" +
            "\nOpen Price: %.5f" +
            "\nProposed SL: %.5f",
            ticket,
            orderType == OP_BUY ? "BUY" : "SELL",
            currentPrice,
            openPrice,
            sl));
        return false;
    }

    // Emergency stop validation
    if(orderType == OP_BUY && sl >= currentPrice) {
        Logger.Error(StringFormat(
            "Invalid emergency stop for BUY - Must be below current price:" +
            "\nCurrent Price: %.5f" +
            "\nProposed SL: %.5f",
            currentPrice, sl));
        return false;
    }
    if(orderType == OP_SELL && sl <= currentPrice) {
        Logger.Error(StringFormat(
            "Invalid emergency stop for SELL - Must be above current price:" +
            "\nCurrent Price: %.5f" +
            "\nProposed SL: %.5f",
            currentPrice, sl));
        return false;
    }

    // Log modification attempt
    Logger.Debug(StringFormat(
        "Emergency Stop Modification:" +
        "\nTicket: %d" +
        "\nDirection: %s" +
        "\nOpen Price: %.5f" +
        "\nCurrent Price: %.5f" +
        "\nCurrent SL: %.5f" +
        "\nEmergency SL: %.5f",
        ticket,
        orderType == OP_BUY ? "BUY" : "SELL",
        openPrice,
        currentPrice,
        currentSL,
        sl
    ));

    // Proceed with modification
    bool success = OrderModify(ticket, openPrice, sl, tp, 0);

    if(success) {
        Logger.Info(StringFormat(
            "Emergency stop modification successful:" +
            "\nTicket: %d" +
            "\nDirection: %s" +
            "\nOpen Price: %.5f" +
            "\nOld SL: %.5f" +
            "\nNew Emergency SL: %.5f" +
            "\nCurrent Price: %.5f",
            ticket,
            orderType == OP_BUY ? "BUY" : "SELL",
            openPrice,
            currentSL,
            sl,
            currentPrice
        ));
    } else {
        LogTradeError("Emergency stop modification failed", GetLastError());
    }

    return success;
}

        // Position Information Methods
        bool HasOpenPosition() {
            int total = OrdersTotal();
            for(int i = 0; i < total; i++) {
                if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
                    if(OrderSymbol() == m_currentSymbol) {
                        return true;
                    }
                }
            }
            return false;
        }

        PositionMetrics GetPositionMetrics() {
            PositionMetrics metrics;

            int total = OrdersTotal();
            for(int i = 0; i < total; i++) {
                if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
                    if(OrderSymbol() == m_currentSymbol) {
                        metrics.totalPositions++;
                        metrics.totalVolume += OrderLots();
                        metrics.weightedPrice += OrderOpenPrice() * OrderLots();
                        metrics.unrealizedPL += OrderProfit() + OrderSwap() + OrderCommission();

                        // Calculate margin for this position
                        double contractSize = MarketInfo(OrderSymbol(), MODE_LOTSIZE);
                        double marginRequired = MarketInfo(OrderSymbol(), MODE_MARGINREQUIRED);
                        metrics.usedMargin += OrderLots() * marginRequired;
                    }
                }
            }

            if(metrics.totalPositions > 0) {
                metrics.weightedPrice /= metrics.totalVolume;
            }

            return metrics;
        }

        // Trade Permission Control Methods
        void EnableTrading() { m_isTradeAllowed = true; }
        void DisableTrading() { m_isTradeAllowed = false; }
        bool CanTrade() const { return m_isTradeAllowed && IsTradeAllowed(); }

        // Last Trade Information Methods
        TradeRecord GetLastTrade() const { return m_lastTrade; }

        // Position Monitoring Methods
        void MonitorPositions() {
            if(HasOpenPosition()) {
                CheckTrailingStop();
            }
        }
    };