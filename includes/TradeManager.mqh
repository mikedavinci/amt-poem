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
    datetime        m_lastExitSignalTime;    // Last exit signal timestamp
    bool            m_partialExitTaken;      // Track partial exit state
    double          m_originalPositionSize;  // Original position size before partial exit

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

    bool IsNewExitSignal(const SignalData& signal) {
        if(!ValidateSymbol()) return false;
        
        string symbolPrefix = GLOBAL_VAR_PREFIX + m_symbolInfo.GetSymbol() + "_";
        datetime lastSignalTime = 0;
        
        // Load last exit signal timestamp
        if(GlobalVariableCheck(symbolPrefix + "LAST_EXIT_SIGNAL")) {
            lastSignalTime = (datetime)GlobalVariableGet(symbolPrefix + "LAST_EXIT_SIGNAL");
        }

        Logger.Debug(StringFormat(
            "Checking exit signal timestamp:" +
            "\nNew Signal: %s" +
            "\nLast Signal: %s",
            TimeToString(signal.timestamp),
            TimeToString(lastSignalTime)
        ));

        // If timestamps match or new signal is older, reject it
        if(signal.timestamp <= lastSignalTime) {
            Logger.Warning(StringFormat(
                "Exit signal timestamp validation failed:" +
                "\nCurrent: %s" +
                "\nLast Exit: %s",
                TimeToString(signal.timestamp),
                TimeToString(lastSignalTime)
            ));
            return false;
        }
        
        return true;
    }

    void SaveSignalTimestamp(datetime timestamp) {
        if(!ValidateSymbol()) return;
        
        string symbolPrefix = GLOBAL_VAR_PREFIX + m_symbolInfo.GetSymbol() + "_";
        
        // Save the timestamp
        GlobalVariableSet(symbolPrefix + "LAST_EXIT_SIGNAL", (double)timestamp);
        
        Logger.Debug(StringFormat(
            "Saved exit signal timestamp: %s",
            TimeToString(timestamp)
        ));
    }

  void SaveTradeState() {
    if(m_symbolInfo.GetSymbol() != Symbol()) return;
    
    string symbolPrefix = GLOBAL_VAR_PREFIX + Symbol() + "_";
    datetime currentTime = TimeCurrent();  // Get current time explicitly
    
    // Add timestamp saves
    GlobalVariableSet(symbolPrefix + "LAST_CHECK", (double)currentTime);
    GlobalVariableSet(symbolPrefix + "LAST_SIGNAL", (double)m_lastSignalTimestamp);
    GlobalVariableSet(symbolPrefix + "LAST_EXIT_SIGNAL", (double)m_lastSignalTimestamp); // Add exit signal timestamp
    
    // Save signal state
    GlobalVariableSet(symbolPrefix + "AWAITING_OPPOSITE", m_awaitingOppositeSignal ? 1 : 0);
    GlobalVariableSet(symbolPrefix + "LAST_DIRECTION", (double)m_lastClosedDirection);
    
    // Save partial exit state
    GlobalVariableSet(symbolPrefix + "PARTIAL_EXIT_TAKEN", m_partialExitTaken ? 1 : 0);
    GlobalVariableSet(symbolPrefix + "ORIGINAL_POSITION_SIZE", m_originalPositionSize);
    
    // Save last trade info
    GlobalVariableSet(symbolPrefix + "LAST_TRADE_TICKET", m_lastTrade.ticket);
    GlobalVariableSet(symbolPrefix + "LAST_TRADE_TYPE", (double)m_lastTrade.direction);
    GlobalVariableSet(symbolPrefix + "LAST_TRADE_LOTS", m_lastTrade.lots);
    GlobalVariableSet(symbolPrefix + "LAST_TRADE_PRICE", m_lastTrade.openPrice);
    
    // Enhanced logging
    Logger.Debug(StringFormat(
        "Saved trade state:" +
        "\nSymbol: %s" +
        "\nTime: %s" +
        "\nAwaiting Opposite: %s" +
        "\nLast Direction: %s" +
        "\nPartial Exit Taken: %s" +
        "\nOriginal Position Size: %.2f" +
        "\nLast Trade Ticket: %d" +
        "\nLast Trade Lots: %.2f",
        Symbol(),
        TimeToString(currentTime),
        m_awaitingOppositeSignal ? "Yes" : "No",
        m_lastClosedDirection == SIGNAL_BUY ? "BUY" : "SELL",
        m_partialExitTaken ? "Yes" : "No",
        m_originalPositionSize,
        m_lastTrade.ticket,
        m_lastTrade.lots));
}
    
void LoadTradeState() {
    if(m_symbolInfo.GetSymbol() != Symbol()) return;
    
    string symbolPrefix = GLOBAL_VAR_PREFIX + Symbol() + "_";
    
    // Load timestamps with validation
    if(GlobalVariableCheck(symbolPrefix + "LAST_CHECK")) {
        double lastCheckValue = GlobalVariableGet(symbolPrefix + "LAST_CHECK");
        if(lastCheckValue > 0) {  
            m_lastCheck = (datetime)lastCheckValue;
        }
    }
    
    if(GlobalVariableCheck(symbolPrefix + "LAST_SIGNAL")) {
        double lastSignalValue = GlobalVariableGet(symbolPrefix + "LAST_SIGNAL");
        if(lastSignalValue > 0) {  
            m_lastSignalTimestamp = (datetime)lastSignalValue;
        }
    }
    
    // Load exit signal timestamp
    if(GlobalVariableCheck(symbolPrefix + "LAST_EXIT_SIGNAL")) {
        double lastExitValue = GlobalVariableGet(symbolPrefix + "LAST_EXIT_SIGNAL");
        if(lastExitValue > 0) {
            m_lastExitSignalTime = (datetime)lastExitValue;
        }
    }
    
    // Load signal state
    if(GlobalVariableCheck(symbolPrefix + "AWAITING_OPPOSITE")) {
        m_awaitingOppositeSignal = (GlobalVariableGet(symbolPrefix + "AWAITING_OPPOSITE") == 1);
    }
    
    if(GlobalVariableCheck(symbolPrefix + "LAST_DIRECTION")) {
        double directionValue = GlobalVariableGet(symbolPrefix + "LAST_DIRECTION");
        if(directionValue == SIGNAL_BUY || directionValue == SIGNAL_SELL) {
            m_lastClosedDirection = (ENUM_TRADE_SIGNAL)((int)directionValue);
        }
    }

    // Load partial exit state
    if(GlobalVariableCheck(symbolPrefix + "PARTIAL_EXIT_TAKEN")) {
        m_partialExitTaken = (GlobalVariableGet(symbolPrefix + "PARTIAL_EXIT_TAKEN") == 1);
    }
    
    if(GlobalVariableCheck(symbolPrefix + "ORIGINAL_POSITION_SIZE")) {
        m_originalPositionSize = GlobalVariableGet(symbolPrefix + "ORIGINAL_POSITION_SIZE");
    }
        
    // Load last trade info
    if(GlobalVariableCheck(symbolPrefix + "LAST_TRADE_TICKET")) {
        m_lastTrade.ticket = (int)GlobalVariableGet(symbolPrefix + "LAST_TRADE_TICKET");
        m_lastTrade.direction = (ENUM_TRADE_SIGNAL)((int)GlobalVariableGet(symbolPrefix + "LAST_TRADE_TYPE"));
        m_lastTrade.lots = GlobalVariableGet(symbolPrefix + "LAST_TRADE_LOTS");
        m_lastTrade.openPrice = GlobalVariableGet(symbolPrefix + "LAST_TRADE_PRICE");
    }
        
    Logger.Debug(StringFormat(
        "Trade state loaded:" +
        "\nSymbol: %s" +
        "\nAwaiting Opposite: %s" +
        "\nLast Direction: %s" +
        "\nPartial Exit Taken: %s" +
        "\nOriginal Position Size: %.2f" +
        "\nLast Check Time: %s" +
        "\nLast Signal Time: %s" +
        "\nLast Exit Signal Time: %s",
        Symbol(),
        m_awaitingOppositeSignal ? "Yes" : "No",
        m_lastClosedDirection == SIGNAL_BUY ? "BUY" : "SELL",
        m_partialExitTaken ? "Yes" : "No",
        m_originalPositionSize,
        TimeToString(m_lastCheck),
        TimeToString(m_lastSignalTimestamp),
        TimeToString(m_lastExitSignalTime)
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



    ENUM_CLOSE_REASON StringToCloseReason(string reason) {
        if(reason == "SL") return CLOSE_SL;
        if(reason == "TP") return CLOSE_TP;
        if(reason == "EMERGENCY") return CLOSE_EMERGENCY;
        if(reason == "PROFIT_PROTECTION") return CLOSE_PROFIT_PROTECTION;
        if(StringFind(reason, "Exit Signal") >= 0) return CLOSE_EXIT_SIGNAL;  
        return CLOSE_MANUAL;
    }

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

    ~CTradeManager() {
    string symbolPrefix = GLOBAL_VAR_PREFIX + m_currentSymbol + "_";
    GlobalVariableDel(symbolPrefix + "LAST_EXIT_SIGNAL");
    GlobalVariableDel(symbolPrefix + "PARTIAL_EXIT_TAKEN");
    GlobalVariableDel(symbolPrefix + "ORIGINAL_POSITION_SIZE");
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
    if(!ValidateSymbol()) return;

    // Check if this is a new signal
    if(!IsNewExitSignal(signal)) {
        Logger.Info(StringFormat(
            "Skipping duplicate exit signal for %s - Same timestamp: %s",
            m_symbolInfo.GetSymbol(),
            signal.timestamp
        ));
        return;
    }

    Logger.Info(StringFormat(
        "Processing new exit signal for %s:" + 
        "\nExit Type: %s" +
        "\nPrice: %.5f" +
        "\nPattern: %s" +
        "\nTimestamp: %s",
        m_symbolInfo.GetSymbol(),
        signal.exitType == EXIT_BULLISH ? "BULLISH" : "BEARISH",
        signal.price,
        signal.pattern,
        signal.timestamp
    ));

    bool hasPosition = false;
    int totalOrders = OrdersTotal();
    
    if(totalOrders == 0) {
        Logger.Warning("No open positions to process exit signal");
        return;
    }

    Logger.Debug(StringFormat(
        "Checking positions for exit:" +
        "\nSymbol: %s" +
        "\nExit Type: %s" +
        "\nTotal Orders: %d",
        m_symbolInfo.GetSymbol(),
        signal.exitType == EXIT_BULLISH ? "BULLISH" : "BEARISH",
        totalOrders
    ));

    for(int i = totalOrders - 1; i >= 0; i--) {
        if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
            Logger.Error(StringFormat("Failed to select order at position %d", i));
            continue;
        }

        if(OrderSymbol() != m_symbolInfo.GetSymbol()) {
            continue;
        }

        hasPosition = true;
        
        // Check if exit signal matches position type
        bool matchingExit = (OrderType() == OP_BUY && signal.exitType == EXIT_BULLISH) ||
                           (OrderType() == OP_SELL && signal.exitType == EXIT_BEARISH);
        
        if(!matchingExit) {
            Logger.Debug(StringFormat(
                "Exit signal does not match position:" +
                "\nPosition: %s" +
                "\nExit Type: %s" +
                "\nTicket: %d",
                OrderType() == OP_BUY ? "BUY" : "SELL",
                signal.exitType == EXIT_BULLISH ? "BULLISH" : "BEARISH",
                OrderTicket()
            ));
            continue;
        }

        // Load and verify partial exit state
        bool partialExitTaken = LoadPartialExitState();
        double originalSize = LoadOriginalSize();

        Logger.Debug(StringFormat(
            "Position state:" +
            "\nTicket: %d" +
            "\nPartial Exit Taken: %s" +
            "\nOriginal Size: %.2f" +
            "\nCurrent Size: %.2f",
            OrderTicket(),
            partialExitTaken ? "YES" : "NO",
            originalSize,
            OrderLots()
        ));

        // First exit signal - partial exit (25%)
        if(!partialExitTaken) {
            double currentLots = OrderLots();
            if(currentLots <= 0) {
                Logger.Error("Invalid lot size for partial close");
                continue;
            }

            SaveOriginalSize(currentLots); // Save original size
            double partialLots = NormalizeDouble(currentLots * (PARTIAL_EXIT_PERCENT / 100.0), 2);
            
            // Validate partial lot size
            double minLot = MarketInfo(m_symbolInfo.GetSymbol(), MODE_MINLOT);
            if(partialLots < minLot) {
                Logger.Warning(StringFormat(
                    "Partial lot size (%.2f) below minimum (%.2f) - Using minimum",
                    partialLots, minLot
                ));
                partialLots = minLot;
            }

            Logger.Info(StringFormat(
                "Attempting partial exit:" +
                "\nTicket: %d" +
                "\nOriginal Size: %.2f" +
                "\nClosing Size: %.2f (%.1f%%)" +
                "\nWill Remain: %.2f (%.1f%%)",
                OrderTicket(),
                currentLots,
                partialLots,
                PARTIAL_EXIT_PERCENT,
                currentLots - partialLots,
                REMAINING_VOLUME_PERCENT
            ));
            
            if(ClosePartialPosition(OrderTicket(), partialLots, "Partial Exit Signal")) {
                SavePartialExitState(true);
                SaveSignalTimestamp(signal.timestamp);
                Logger.Trade(StringFormat(
                    "Partial exit executed successfully:" +
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
            } else {
                Logger.Error(StringFormat(
                    "Failed to execute partial exit:" +
                    "\nTicket: %d" +
                    "\nError: %d - %s",
                    OrderTicket(),
                    GetLastError(),
                    ErrorDescription(GetLastError())
                ));
            }
        }
        // Second exit signal - close remaining position (75%)
        else {
            Logger.Info(StringFormat(
                "Attempting to close remaining position:" +
                "\nTicket: %d" +
                "\nOriginal Size: %.2f" +
                "\nRemaining Size: %.2f",
                OrderTicket(),
                originalSize,
                OrderLots()
            ));

            if(ClosePosition(OrderTicket(), "Full Exit Signal")) {
                m_lastClosedDirection = OrderType() == OP_BUY ? SIGNAL_BUY : SIGNAL_SELL;
                
                // Reset partial exit state
                SavePartialExitState(false);
                SaveOriginalSize(0);
                SaveSignalTimestamp(signal.timestamp);
                
                Logger.Trade(StringFormat(
                    "Closed remaining position successfully:" +
                    "\nTicket: %d" +
                    "\nDirection: %s" +
                    "\nClose Price: %.5f" +
                    "\nAwaiting opposite signal: %s" +
                    "\nLast closed direction: %s",
                    OrderTicket(),
                    OrderType() == OP_BUY ? "BUY" : "SELL",
                    OrderType() == OP_BUY ? m_symbolInfo.GetBid() : m_symbolInfo.GetAsk(),
                    m_awaitingOppositeSignal ? "YES" : "NO",
                    m_lastClosedDirection == SIGNAL_BUY ? "BUY" : "SELL"
                ));
                SaveTradeState();
            } else {
                Logger.Error(StringFormat(
                    "Failed to close remaining position:" +
                    "\nTicket: %d" +
                    "\nError: %d - %s",
                    OrderTicket(),
                    GetLastError(),
                    ErrorDescription(GetLastError())
                ));
            }
        }
    }

    if(!hasPosition) {
        Logger.Warning(StringFormat(
            "No matching positions found for exit signal:" +
            "\nSymbol: %s" +
            "\nExit Type: %s",
            m_symbolInfo.GetSymbol(),
            signal.exitType == EXIT_BULLISH ? "BULLISH" : "BEARISH"
        ));
    }
}

bool CloseExistingPositions(ENUM_TRADE_SIGNAL newSignal) {
    if(!ValidateSymbol()) {
        Logger.Error("Symbol validation failed in CloseExistingPositions");
        return false;
    }

    bool allClosed = true;
    int total = OrdersTotal();
    int closedCount = 0;
    double totalProfit = 0;
    int maxAttempts = 3;
    RefreshRates(); 

    // Initial position check and logging
    Logger.Info(StringFormat(
        "CLOSING POSITIONS FOR REVERSAL" +
        "\n--------------------" +
        "\nSymbol: %s" +
        "\nNew Signal: %s" +
        "\nTotal Orders: %d",
        m_symbolInfo.GetSymbol(),
        newSignal == SIGNAL_BUY ? "BUY" : "SELL",
        total
    ));

    // First pass - analyze positions to be closed
    double totalLotsToClose = 0;
    double estimatedPL = 0;
    for(int i = total - 1; i >= 0; i--) {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
            if(OrderSymbol() == m_symbolInfo.GetSymbol()) {
                ENUM_TRADE_SIGNAL currentPos = (OrderType() == OP_BUY) ? SIGNAL_BUY : SIGNAL_SELL;
                if(currentPos != newSignal) {
                    totalLotsToClose += OrderLots();
                    estimatedPL += OrderProfit() + OrderSwap() + OrderCommission();
                }
            }
        }
    }

    Logger.Trade(StringFormat(
        "POSITION CLOSURE SUMMARY" +
        "\n--------------------" +
        "\nTotal Lots to Close: %.2f" +
        "\nEstimated P/L: %.2f",
        totalLotsToClose,
        estimatedPL
    ));


    // Main closure loop with retry mechanism
    for(int attempt = 0; attempt < maxAttempts; attempt++) {
        int retryDelay = (attempt == 0) ? 100 : 1000;  // 100ms first retry, 1s for subsequent

        bool anyFailed = false;
        total = OrdersTotal(); // Refresh total count
        
        for(int i = total - 1; i >= 0; i--) {
            if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
                if(OrderSymbol() == m_symbolInfo.GetSymbol()) {
                    ENUM_TRADE_SIGNAL currentPos = (OrderType() == OP_BUY) ? SIGNAL_BUY : SIGNAL_SELL;

                    if(currentPos != newSignal) {
                        double closePrice = OrderType() == OP_BUY ? 
                            m_symbolInfo.GetBid() : m_symbolInfo.GetAsk();

                        int ticket = OrderTicket();
                        double lots = OrderLots();
                        double openPrice = OrderOpenPrice();
                        
                        Logger.Trade(StringFormat(
                            "CLOSING INDIVIDUAL POSITION (Attempt %d/%d)" +
                            "\n--------------------" +
                            "\nTicket: %d" +
                            "\nDirection: %s" +
                            "\nLots: %.2f" +
                            "\nOpen Price: %.5f" +
                            "\nClose Price: %.5f" +
                            "\nProfit: %.2f" +
                            "\nSwap: %.2f" +
                            "\nCommission: %.2f",
                            attempt + 1, maxAttempts,
                            ticket,
                            OrderType() == OP_BUY ? "BUY" : "SELL",
                            lots,
                            openPrice,
                            closePrice,
                            OrderProfit(),
                            OrderSwap(),
                            OrderCommission()
                        ));

                        bool closed = ClosePosition(ticket, "Signal reversal");
                        
                        if(!closed) {
                            anyFailed = true;
                            Logger.Error(StringFormat(
                                "FAILED TO CLOSE POSITION" +
                                "\n--------------------" +
                                "\nTicket: %d" +
                                "\nAttempt: %d/%d" +
                                "\nError: %d" +
                                "\nDescription: %s",
                                ticket,
                                attempt + 1, maxAttempts,
                                GetLastError(),
                                ErrorDescription(GetLastError())
                            ));
                        } else {
                            closedCount++;
                            totalProfit += OrderProfit() + OrderSwap() + OrderCommission();
                            Logger.Trade(StringFormat(
                                "Position closed successfully:" +
                                "\nTicket: %d" +
                                "\nProfit: %.2f",
                                ticket,
                                OrderProfit() + OrderSwap() + OrderCommission()
                            ));
                        }
                    }
                }
            }
        }

        // If no failures in this attempt, break the retry loop
        if(!anyFailed) {
            Logger.Info("All positions closed successfully");
            break;
        }
        
        // If this wasn't the last attempt, wait before retrying
        if(attempt < maxAttempts - 1) {
            Logger.Warning(StringFormat(
                "Some positions failed to close. Retrying in %d ms...",
                retryDelay
            ));
            Sleep(retryDelay);
        }
    }

    // Final verification
    total = OrdersTotal();
    bool remainingPositions = false;
    for(int i = 0; i < total; i++) {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
            if(OrderSymbol() == m_symbolInfo.GetSymbol()) {
                remainingPositions = true;
                ENUM_TRADE_SIGNAL currentPos = (OrderType() == OP_BUY) ? SIGNAL_BUY : SIGNAL_SELL;
                Logger.Error(StringFormat(
                    "Position remains open after closure attempts:" +
                    "\nTicket: %d" +
                    "\nType: %s" +
                    "\nLots: %.2f",
                    OrderTicket(),
                    OrderType() == OP_BUY ? "BUY" : "SELL",
                    OrderLots()
                ));
            }
        }
    }

    if(remainingPositions) {
        allClosed = false;
    }

    // Final closure summary
    Logger.Trade(StringFormat(
        "POSITION CLOSURE SUMMARY" +
        "\n--------------------" +
        "\nSymbol: %s" +
        "\nPositions Closed: %d" +
        "\nAll Positions Closed: %s" +
        "\nTotal Profit: %.2f" +
        "\nRemaining Positions: %s",
        m_symbolInfo.GetSymbol(),
        closedCount,
        allClosed ? "YES" : "NO",
        totalProfit,
        remainingPositions ? "YES" : "NO"
    ));

    return allClosed;
}

bool ClosePartialPosition(int ticket, double lots, string reason = "") {
    if(!OrderSelect(ticket, SELECT_BY_TICKET)) {
        Logger.Error(StringFormat(
            "Failed to select order %d for partial close",
            ticket
        ));
        return false;
    }

    if(OrderSymbol() != m_symbolInfo.GetSymbol()) {
        Logger.Error(StringFormat(
            "Symbol mismatch in partial close - Expected: %s, Got: %s",
            m_symbolInfo.GetSymbol(), 
            OrderSymbol()
        ));
        return false;
    }

    // Validate lot size
    double currentLots = OrderLots();
    if(lots > currentLots) {
        Logger.Error(StringFormat(
            "Invalid lot size for partial close - Current: %.2f, Requested: %.2f",
            currentLots, 
            lots
        ));
        return false;
    }

    // Validate minimum lot size
    double minLot = MarketInfo(m_symbolInfo.GetSymbol(), MODE_MINLOT);
    if(lots < minLot) {
        Logger.Error(StringFormat(
            "Partial close lot size (%.2f) below minimum (%.2f)",
            lots, 
            minLot
        ));
        return false;
    }

    // Calculate close price based on position type
    double closePrice = OrderType() == OP_BUY ? 
        m_symbolInfo.GetBid() : m_symbolInfo.GetAsk();

    Logger.Info(StringFormat(
        "Attempting partial close:" +
        "\nTicket: %d" +
        "\nSymbol: %s" +
        "\nType: %s" +
        "\nCurrent Size: %.2f" +
        "\nClosing Size: %.2f" +
        "\nClose Price: %.5f" +
        "\nReason: %s",
        ticket,
        OrderSymbol(),
        OrderType() == OP_BUY ? "BUY" : "SELL",
        currentLots,
        lots,
        closePrice,
        reason
    ));

    bool success = OrderClose(ticket, lots, closePrice, m_slippage, clrRed);

    if(success) {
        Logger.Trade(StringFormat(
            "Partial close executed:" +
            "\nTicket: %d" +
            "\nClosed: %.2f lots" +
            "\nRemaining: %.2f lots" +
            "\nClose Price: %.5f" +
            "\nProfit: %.2f" +
            "\nReason: %s",
            ticket,
            lots,
            currentLots - lots,
            closePrice,
            OrderProfit(),
            reason
        ));
    } else {
        int error = GetLastError();
        Logger.Error(StringFormat(
            "Partial close failed:" +
            "\nTicket: %d" +
            "\nError: %d" +
            "\nDescription: %s",
            ticket,
            error,
            ErrorDescription(error)
        ));
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
        "\nSymbol: %s" +
        "\nAwaiting Opposite: %s" +
        "\nLast Closed Direction: %s" +
        "\nLots: %.2f" +
        "\nSL: %.5f" +
        "\nTP: %.5f",
        m_symbolInfo.GetSymbol(),
        m_awaitingOppositeSignal ? "Yes" : "No",
        m_lastClosedDirection == SIGNAL_BUY ? "BUY" : "SELL",
        lots,
        sl,
        tp
    ));

    if(!CanOpenNewPosition(SIGNAL_BUY)) {
        Logger.Warning(StringFormat(
            "Buy position rejected - Awaiting opposite signal after %s position stop loss",
            m_lastClosedDirection == SIGNAL_BUY ? "BUY" : "SELL"
        ));
        return false;
    }

    // First check if we already have a BUY position
    if(HasOpenPositionInDirection(SIGNAL_BUY)) {
        Logger.Warning(StringFormat(
            "Buy position already exists - skipping" +
            "\nSignal Price: %.5f" +
            "\nSignal Pattern: %s",
            signal.price,
            signal.pattern
        ));
        return false;
    }

    // Then check for opposite positions
    if(HasOpenPositionInDirection(SIGNAL_SELL)) {
        Logger.Info(StringFormat(
            "Found opposite (SELL) position - attempting to close" +
            "\nNew Signal: BUY" +
            "\nSignal Price: %.5f" +
            "\nSignal Pattern: %s",
            signal.price,
            signal.pattern
        ));
        
        if(!CloseExistingPositions(SIGNAL_BUY)) {
            Logger.Error("Failed to close existing SELL positions before BUY");
            return false;
        }
        
        // Add a small delay after closing positions
        Sleep(100);
        
        // Verify no positions remain
        if(HasOpenPosition()) {
            Logger.Error("Positions still exist after attempted close - aborting new BUY position");
            return false;
        }
    }

    // Validate current price and stop loss
    double currentPrice = m_symbolInfo.GetAsk();
    Logger.Info(StringFormat(
        "Validating BUY order parameters:" +
        "\nCurrent Ask: %.5f" +
        "\nSignal Price: %.5f" +
        "\nStop Loss: %.5f" +
        "\nTake Profit: %.5f",
        currentPrice,
        signal.price,
        sl,
        tp
    ));

    if(!m_symbolInfo.ValidateStopLoss(OP_BUY, currentPrice, sl)) {
        Logger.Error(StringFormat(
            "Invalid stop loss for buy order:" +
            "\nCurrent Price: %.5f" +
            "\nProposed SL: %.5f",
            currentPrice, sl));
        return false;
    }

    // Execute the buy order
    Logger.Info(StringFormat(
        "Executing BUY order:" +
        "\nLots: %.2f" +
        "\nPrice: %.5f" +
        "\nSL: %.5f" +
        "\nTP: %.5f" +
        "\nComment: %s",
        lots, signal.price, sl, tp, comment
    ));

    bool result = ExecuteMarketOrder(OP_BUY, lots, signal.price, sl, tp, comment, signal);
    
    if(result) {
        Logger.Info(StringFormat(
            "BUY position opened successfully:" +
            "\nLots: %.2f" +
            "\nEntry: %.5f" +
            "\nSL: %.5f" +
            "\nTP: %.5f",
            lots, signal.price, sl, tp
        ));
        SaveTradeState();
    } else {
        Logger.Error("Failed to open BUY position");
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
        "\nSymbol: %s" +
        "\nAwaiting Opposite: %s" +
        "\nLast Closed Direction: %s" +
        "\nLots: %.2f" +
        "\nSL: %.5f" +
        "\nTP: %.5f",
        m_symbolInfo.GetSymbol(),
        m_awaitingOppositeSignal ? "Yes" : "No",
        m_lastClosedDirection == SIGNAL_BUY ? "BUY" : "SELL",
        lots,
        sl,
        tp
    ));

    if(!CanOpenNewPosition(SIGNAL_SELL)) {
        Logger.Warning(StringFormat(
            "Sell position rejected - Awaiting opposite signal after %s position stop loss",
            m_lastClosedDirection == SIGNAL_BUY ? "BUY" : "SELL"
        ));
        return false;
    }

    // First check if we already have a SELL position
    if(HasOpenPositionInDirection(SIGNAL_SELL)) {
        Logger.Warning(StringFormat(
            "Sell position already exists - skipping" +
            "\nSignal Price: %.5f" +
            "\nSignal Pattern: %s",
            signal.price,
            signal.pattern
        ));
        return false;
    }

    // Then check for opposite positions
    if(HasOpenPositionInDirection(SIGNAL_BUY)) {
        Logger.Info(StringFormat(
            "Found opposite (BUY) position - attempting to close" +
            "\nNew Signal: SELL" +
            "\nSignal Price: %.5f" +
            "\nSignal Pattern: %s",
            signal.price,
            signal.pattern
        ));
        
        if(!CloseExistingPositions(SIGNAL_SELL)) {
            Logger.Error("Failed to close existing BUY positions before SELL");
            return false;
        }
        
        // Add a small delay after closing positions
        Sleep(100);
        
        // Verify no positions remain
        if(HasOpenPosition()) {
            Logger.Error("Positions still exist after attempted close - aborting new SELL position");
            return false;
        }
    }

    // Validate current price and stop loss
    double currentPrice = m_symbolInfo.GetBid();
    Logger.Info(StringFormat(
        "Validating SELL order parameters:" +
        "\nCurrent Bid: %.5f" +
        "\nSignal Price: %.5f" +
        "\nStop Loss: %.5f" +
        "\nTake Profit: %.5f",
        currentPrice,
        signal.price,
        sl,
        tp
    ));

    if(!m_symbolInfo.ValidateStopLoss(OP_SELL, currentPrice, sl)) {
        Logger.Error(StringFormat(
            "Invalid stop loss for sell order:" +
            "\nCurrent Price: %.5f" +
            "\nProposed SL: %.5f",
            currentPrice, sl));
        return false;
    }

    // Execute the sell order
    Logger.Info(StringFormat(
        "Executing SELL order:" +
        "\nLots: %.2f" +
        "\nPrice: %.5f" +
        "\nSL: %.5f" +
        "\nTP: %.5f" +
        "\nComment: %s",
        lots, signal.price, sl, tp, comment
    ));

    bool result = ExecuteMarketOrder(OP_SELL, lots, signal.price, sl, tp, comment, signal);
    
    if(result) {
        Logger.Info(StringFormat(
            "SELL position opened successfully:" +
            "\nLots: %.2f" +
            "\nEntry: %.5f" +
            "\nSL: %.5f" +
            "\nTP: %.5f",
            lots, signal.price, sl, tp
        ));
        SaveTradeState();
    } else {
        Logger.Error("Failed to open SELL position");
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