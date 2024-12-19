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
            Logger.Info("Opposite signal (SELL) received after BUY stop loss - allowing trade");
            return true;
        }
        if(m_lastClosedDirection == SIGNAL_SELL && newSignal == SIGNAL_BUY) {
            m_awaitingOppositeSignal = false;
            Logger.Info("Opposite signal (BUY) received after SELL stop loss - allowing trade");
            return true;
        }

        Logger.Warning(StringFormat(
            "Trade rejected - Awaiting %s signal after %s position stop loss",
            m_lastClosedDirection == SIGNAL_BUY ? "SELL" : "BUY",
            m_lastClosedDirection == SIGNAL_BUY ? "BUY" : "SELL"
        ));
        return false;
    }

    bool ValidateEntryPrice(double signalPrice, double currentPrice, int type) {
        if(signalPrice <= 0 || currentPrice <= 0) return false;

        double deviation = MathAbs(1 - (currentPrice / signalPrice)) * 100;

        // If price has moved too far from signal price, reject entry
        if(deviation > ENTRY_PRICE_TOLERANCE_PERCENT) {
            Logger.Warning(StringFormat(
                "Entry price deviation too high: %.2f%%. Signal: %.5f, Current: %.5f",
                deviation, signalPrice, currentPrice));
            return false;
        }

        // For buy orders, current price should not be significantly higher than signal
        // For sell orders, current price should not be significantly lower than signal
        if(type == OP_BUY && currentPrice > signalPrice * (1 + ENTRY_PRICE_TOLERANCE_PERCENT/100.0)) {
            Logger.Warning("Buy price too high compared to signal price");
            return false;
        }
        if(type == OP_SELL && currentPrice < signalPrice * (1 - ENTRY_PRICE_TOLERANCE_PERCENT/100.0)) {
            Logger.Warning("Sell price too low compared to signal price");
            return false;
        }

        return true;
    }

// Private Methods for Trade Operations
    double GetCoordinatedStopDistance(double currentPrice, int orderType) {
        // Get ATR-based stop distance
        double atrValue = m_symbolInfo.GetATR();
        double multiplier = m_symbolInfo.IsCryptoPair() ?
            CRYPTO_ATR_MULTIPLIER : FOREX_ATR_MULTIPLIER;
        double atrStopDistance = atrValue * multiplier;

        // Calculate emergency stop distance
        double emergencyStopDistance;
        if(m_symbolInfo.IsCryptoPair()) {
            emergencyStopDistance = currentPrice * (CRYPTO_EMERGENCY_STOP_PERCENT / 100.0);
        } else {
            emergencyStopDistance = FOREX_EMERGENCY_PIPS * m_symbolInfo.GetPipSize();
        }

        // Get minimum stop distance
        double minStopDistance;
        if(m_symbolInfo.IsCryptoPair()) {
            minStopDistance = currentPrice * (CRYPTO_STOP_PERCENT / 100.0);
        } else {
            minStopDistance = FOREX_STOP_PIPS * m_symbolInfo.GetPipSize();
        }

        // Add detailed logging of all calculated stops
            Logger.Debug(StringFormat(
                "Stop Distance Calculations:" +
                "\nSymbol: %s" +
                "\nPrice: %.5f" +
                "\nATR Value: %.5f" +
                "\nATR Stop Distance: %.5f" +
                "\nEmergency Stop Distance: %.5f" +
                "\nMinimum Stop Distance: %.5f",
                m_symbolInfo.GetSymbol(),
                currentPrice,
                atrValue,
                atrStopDistance,
                emergencyStopDistance,
                minStopDistance
            ));

           // Use the most conservative stop and log which one was chosen
           double stopDistance = MathMin(atrStopDistance, emergencyStopDistance);
           string stopType;

           if(stopDistance == atrStopDistance) {
               stopType = "ATR";
           } else {
               stopType = "Emergency";
           }

           stopDistance = MathMax(stopDistance, minStopDistance);
           if(stopDistance == minStopDistance) {
               stopType = "Fixed";
           }

           Logger.Debug(StringFormat(
               "Final Stop Distance Selected:" +
               "\nType: %s" +
               "\nDistance: %.5f" +
               "\nFinal Stop Price: %.5f",
               stopType,
               stopDistance,
               orderType == OP_BUY ? currentPrice - stopDistance : currentPrice + stopDistance
           ));

           return stopDistance;
       }

    bool ExecuteMarketOrder(int type, double lots, double signalPrice, double sl,
                           double tp, string comment) {

     //Logger.Debug(StringFormat("ExecuteMarketOrder - Received comment: '%s'", comment));

        int ticket = -1;
        int attempts = 0;
        bool success = false;

        // Ensure comment is not NULL
            if(comment == NULL) comment = "";

            // Ensure the comment doesn't exceed the maximum length (31 characters)
            if(StringLen(comment) > 31) {
                comment = StringSubstr(comment, 0, 31);
            }

        while(attempts < m_maxRetries && !success) {
            if(attempts > 0) {
                RefreshRates();
                int delay = MathMin(INITIAL_RETRY_DELAY * (attempts + 1), MAX_RETRY_DELAY);
                Sleep(delay);
            }

            double currentPrice = (type == OP_BUY) ? m_symbolInfo.GetAsk() : m_symbolInfo.GetBid();

             // Log attempt details
                    //Logger.Debug(StringFormat(
                        // "Attempting order - Type: %s, Lots: %.2f, Price: %.5f, SL: %.5f, TP: %.5f, Comment: '%s'",
                        // type == OP_BUY ? "BUY" : "SELL", lots, currentPrice, sl, tp, comment
                    // ));

            // Validate entry price against signal price
            if(!ValidateEntryPrice(signalPrice, currentPrice, type)) {
                Logger.Error("Price moved too far from signal price");
                return false;
            }

            // Calculate ATR-based stop loss and emergency stops
            double stopDistance = GetCoordinatedStopDistance(currentPrice, type);
            double newStopLoss = type == OP_BUY ?
                currentPrice - stopDistance :
                currentPrice + stopDistance;

            // Use provided stop loss if it's more conservative
            if(sl > 0) {
                if(type == OP_BUY) {
                    newStopLoss = MathMin(sl, newStopLoss);
                } else {
                    newStopLoss = MathMax(sl, newStopLoss);
                }
            }

            // Validate final stop loss
            if(!m_symbolInfo.ValidateStopLoss(type, currentPrice, newStopLoss)) {
                Logger.Error(StringFormat(
                    "Invalid stop loss calculated - Price: %.5f, SL: %.5f",
                    currentPrice, newStopLoss));
                return false;
            }

             ticket = OrderSend(
                        m_symbolInfo.GetSymbol(),  // Symbol
                        type,                      // Operation type
                        lots,                      // Lot size
                        currentPrice,              // Price
                        m_slippage,               // Slippage
                        sl,                       // Stop Loss
                        tp,                       // Take Profit
                        comment,                  // Comment
                        0,                        // Magic Number
                        0,                        // Expiration
                        type == OP_BUY ? clrGreen : clrRed  // Color
                    );

             if(ticket > 0) {
                        success = true;
                        RecordTrade(ticket, type, lots, currentPrice, sl, tp, comment);
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
                            sl,
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
        bool stopHit = false;

        if(orderType == OP_BUY && (currentPrice < openPrice - emergencyDistance)) {
            stopHit = true;
        }
        if(orderType == OP_SELL && (currentPrice > openPrice + emergencyDistance)) {
            stopHit = true;
        }

        if(stopHit) {
            Logger.Warning(StringFormat(
                "Emergency stop triggered:" +
                "\nDirection: %s" +
                "\nOpen Price: %.5f" +
                "\nCurrent Price: %.5f" +
                "\nEmergency Distance: %.5f",
                orderType == OP_BUY ? "BUY" : "SELL",
                openPrice, currentPrice, emergencyDistance
            ));
        }
        return stopHit;
    }
    return false;
}

    bool CheckBreakevenCondition(double currentPrice, double openPrice,
                               double currentStop, int orderType) {
        // Don't move to breakeven if we're already there or beyond
        if(orderType == OP_BUY && currentStop >= openPrice) return false;
        if(orderType == OP_SELL && currentStop <= openPrice) return false;

        if(m_symbolInfo.IsCryptoPair()) {
            // For crypto, calculate based on percentage
            double profitPercent = MathAbs(currentPrice - openPrice) / openPrice * 100;
            return profitPercent >= CRYPTO_BREAKEVEN_PROFIT_PERCENT;
        } else {
            // For forex, calculate based on pips
            double profitInPips = orderType == OP_BUY ?
                (currentPrice - openPrice) / m_symbolInfo.GetPipSize() :
                (openPrice - currentPrice) / m_symbolInfo.GetPipSize();

            return profitInPips >= FOREX_BREAKEVEN_PROFIT_PIPS;
        }
    }

    void CheckTrailingStop() {
        if(!HasOpenPosition()) return;

        for(int i = OrdersTotal() - 1; i >= 0; i--) {
            if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
                if(OrderSymbol() == m_symbolInfo.GetSymbol()) {
                    double currentPrice = OrderType() == OP_BUY ?
                        m_symbolInfo.GetBid() : m_symbolInfo.GetAsk();

                    // First check emergency stop
                    if(CheckEmergencyStop(currentPrice, OrderOpenPrice(), OrderType())) {
                        ClosePosition(OrderTicket(), "EMERGENCY");
                        continue;
                    }

                    // Check breakeven condition
                    if(CheckBreakevenCondition(currentPrice, OrderOpenPrice(),
                       OrderStopLoss(), OrderType())) {
                        double breakevenStop = OrderOpenPrice();
                        if(m_symbolInfo.IsCryptoPair()) {
                            // Add buffer for crypto based on percentage
                            if(OrderType() == OP_BUY) {
                                breakevenStop *= (1 + CRYPTO_BREAKEVEN_BUFFER_PERCENT/100.0);
                            } else {
                                breakevenStop *= (1 - CRYPTO_BREAKEVEN_BUFFER_PERCENT/100.0);
                            }
                        } else {
                            // Add buffer for forex based on pips
                            if(OrderType() == OP_BUY) {
                                breakevenStop += m_symbolInfo.GetPipSize() * FOREX_BREAKEVEN_BUFFER_PIPS;
                            } else {
                                breakevenStop -= m_symbolInfo.GetPipSize() * FOREX_BREAKEVEN_BUFFER_PIPS;
                            }
                        }

                        ModifyPosition(OrderTicket(), breakevenStop);
                        continue;  // Skip trailing stop if we moved to breakeven
                    }

                    // Get coordinated stop distance for trailing
                    double stopDistance = GetCoordinatedStopDistance(currentPrice, OrderType());
                    double newStopLoss = OrderType() == OP_BUY ?
                        currentPrice - stopDistance :
                        currentPrice + stopDistance;

                    // Move stop loss if better than current
                    if(OrderType() == OP_BUY && newStopLoss > OrderStopLoss()) {
                        ModifyPosition(OrderTicket(), newStopLoss);
                    }
                    else if(OrderType() == OP_SELL &&
                            (OrderStopLoss() == 0 || newStopLoss < OrderStopLoss())) {
                        ModifyPosition(OrderTicket(), newStopLoss);
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
            return CLOSE_MANUAL;
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

    // Trade Execution Methods
    bool OpenBuyPosition(double lots, double sl, double tp = 0, string comment = "") {
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

        return ExecuteMarketOrder(OP_BUY, lots, price, sl, tp, comment);
    }

    bool OpenSellPosition(double lots, double sl, double tp = 0, string comment = "") {
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

        return ExecuteMarketOrder(OP_SELL, lots, price, sl, tp, comment);
    }

    bool ClosePosition(int ticket, string reason = "") {
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
        m_lastTrade.closePrice = closePrice;
        m_lastTrade.closeTime = TimeCurrent();
        m_lastTrade.closeReason = StringToCloseReason(reason);
        m_lastTrade.profit = OrderProfit() + OrderSwap() + OrderCommission();

        // Set awaiting flag for SL and trailing stop
        if(reason == "SL" || reason == "EMERGENCY" || StringFind(reason, "trailing") >= 0) {
            m_awaitingOppositeSignal = true;
            m_lastClosedDirection = currentDirection;
            Logger.Info(StringFormat(
                "Stop loss hit - Awaiting opposite signal:" +
                "\nClosed Direction: %s" +
                "\nEntry: %.5f" +
                "\nStop Loss: %.5f" +
                "\nClose Price: %.5f" +
                "\nP/L: %.2f",
                m_lastClosedDirection == SIGNAL_BUY ? "BUY" : "SELL",
                openPrice, stopLoss, closePrice,
                m_lastTrade.profit
            ));
        }
    } else {
        LogTradeError("Order close failed", GetLastError());
    }

    return success;
}

    // Position Modification Methods
        bool ModifyPosition(int ticket, double sl, double tp = 0) {
            if(!OrderSelect(ticket, SELECT_BY_TICKET)) {
                LogTradeError("Order select failed", GetLastError());
                return false;
            }

            // Get current position details
            double currentLots = OrderLots();
            double openPrice = OrderOpenPrice();
            double currentSL = OrderStopLoss();

            // Calculate current and proposed risk
            double currentRisk = m_riskManager.CalculatePositionRisk(currentLots, openPrice, currentSL);
            double proposedRisk = m_riskManager.CalculatePositionRisk(currentLots, openPrice, sl);
            double accountBalance = AccountBalance();

            // Log risk change details
            Logger.Debug(StringFormat(
                "Stop Loss Modification Risk Analysis:" +
                "\nTicket: %d" +
                "\nCurrent Risk: %.2f%%" +
                "\nProposed Risk: %.2f%%" +
                "\nCurrent SL: %.5f" +
                "\nProposed SL: %.5f" +
                "\nLots: %.2f",
                ticket,
                (currentRisk/accountBalance) * 100,
                (proposedRisk/accountBalance) * 100,
                currentSL,
                sl,
                currentLots
            ));

            // Validate new stop loss against risk parameters
            if(!m_riskManager.ValidatePositionRisk(currentLots, openPrice, sl)) {
                Logger.Warning(StringFormat(
                    "Stop loss modification rejected - Risk limits exceeded:" +
                    "\nTicket: %d" +
                    "\nCurrent Risk: %.2f%%" +
                    "\nRejected Risk: %.2f%%",
                    ticket,
                    (currentRisk/accountBalance) * 100,
                    (proposedRisk/accountBalance) * 100
                ));
                return false;
            }

            // Proceed with modification
            bool success = OrderModify(ticket, openPrice, sl, tp, 0);

            if(success) {
                double totalAccountRisk = m_riskManager.CalculateTotalAccountRisk();
                Logger.Info(StringFormat(
                    "Position modified successfully:" +
                    "\nTicket: %d" +
                    "\nOld SL: %.5f" +
                    "\nNew SL: %.5f" +
                    "\nNew Position Risk: %.2f%%" +
                    "\nTotal Account Risk: %.2f%%",
                    ticket,
                    currentSL,
                    sl,
                    (proposedRisk/accountBalance) * 100,
                    (totalAccountRisk/accountBalance) * 100
                ));
            } else {
                LogTradeError("Order modify failed", GetLastError());
            }

            return success;
        }

        // Position Information Methods
        bool HasOpenPosition() {
            int total = OrdersTotal();
            for(int i = 0; i < total; i++) {
                if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
                    if(OrderSymbol() == m_symbolInfo.GetSymbol()) {
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
                    if(OrderSymbol() == m_symbolInfo.GetSymbol()) {
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