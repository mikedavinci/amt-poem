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
#include "Logger.mqh"

//+------------------------------------------------------------------+
//| Class for managing trade operations and position tracking          |
//+------------------------------------------------------------------+
class CTradeManager {
private:
    CSymbolInfo*    m_symbolInfo;       // Symbol information
    TradeRecord     m_lastTrade;        // Last trade record
    int             m_slippage;         // Maximum allowed slippage
    int             m_maxRetries;       // Maximum retry attempts
    bool            m_isTradeAllowed;   // Trade permission flag
    bool            m_awaitingOppositeSignal;  // New flag for signal management
    ENUM_TRADE_SIGNAL m_lastClosedDirection;   // Track last closed position direction

    // New method to check if we can open position after stop loss/trailing stop
    bool CanOpenNewPosition(ENUM_TRADE_SIGNAL newSignal) {
        if(!m_awaitingOppositeSignal) return true;

        // If awaiting opposite signal, only allow if signal is opposite to last closed position
        if(m_lastClosedDirection == SIGNAL_BUY && newSignal == SIGNAL_SELL) {
            m_awaitingOppositeSignal = false;
            return true;
        }
        if(m_lastClosedDirection == SIGNAL_SELL && newSignal == SIGNAL_BUY) {
            m_awaitingOppositeSignal = false;
            return true;
        }

        Logger.Warning("Awaiting opposite signal before opening new position");
        return false;
    }
    
    // Private methods for trade operations
    bool ExecuteMarketOrder(int type, double lots, double price, double sl, 
                           double tp, string comment) {
        int ticket = -1;
        int attempts = 0;
        bool success = false;
        
        while(attempts < m_maxRetries && !success) {
            if(attempts > 0) {
                RefreshRates();
                Sleep(1000 * attempts); // Exponential backoff
            }
            
            price = (type == OP_BUY) ? m_symbolInfo.GetAsk() : m_symbolInfo.GetBid();
            
            ticket = OrderSend(
                m_symbolInfo.GetSymbol(),
                type,
                lots,
                price,
                m_slippage,
                sl,
                tp,
                comment,
                0,
                0,
                type == OP_BUY ? clrGreen : clrRed
            );
            
            if(ticket > 0) {
                success = true;
                RecordTrade(ticket, type, lots, price, sl, tp, comment);
            } else {
                int error = GetLastError();
                LogTradeError("Order execution failed", error);
                attempts++;
            }
        }
        
        return success;
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
        string errorDesc = ErrorDescription(errorCode);
        string message = StringFormat("%s: Error %d - %s", operation, errorCode, errorDesc);
        Logger.Error(message);
    }

public:
    // Constructor
    CTradeManager(CSymbolInfo* symbolInfo, int slippage = DEFAULT_SLIPPAGE,
                  int maxRetries = MAX_RETRY_ATTEMPTS) 
        : m_symbolInfo(symbolInfo),
          m_slippage(slippage),
          m_maxRetries(maxRetries) {
        m_isTradeAllowed = true;
    }
    
    // Trade execution methods
    bool OpenBuyPosition(double lots, double sl, double tp = 0, string comment = "") {
            if(!CanTrade()) return false;
            if(!CanOpenNewPosition(SIGNAL_BUY)) return false;

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
            if(!CanOpenNewPosition(SIGNAL_SELL)) return false;

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

            double lots = OrderLots();
            double price = OrderType() == OP_BUY ? m_symbolInfo.GetBid() : m_symbolInfo.GetAsk();

            bool success = OrderClose(ticket, lots, price, m_slippage, clrRed);
            if(success) {
                m_lastTrade.closePrice = price;
                m_lastTrade.closeTime = TimeCurrent();
                m_lastTrade.closeReason = StringToCloseReason(reason);
                m_lastTrade.profit = OrderProfit() + OrderSwap() + OrderCommission();

                // Set awaiting flag if closed by stop loss or trailing stop
                if(reason == "SL" || StringFind(reason, "trailing") >= 0) {
                    m_awaitingOppositeSignal = true;
                    m_lastClosedDirection = OrderType() == OP_BUY ? SIGNAL_BUY : SIGNAL_SELL;
                    Logger.Info("Position closed by stop/trailing stop - awaiting opposite signal");
                }
            } else {
                LogTradeError("Order close failed", GetLastError());
            }

            return success;
        }

     void CheckTrailingStop() {
            if(!HasOpenPosition()) return;

            for(int i = OrdersTotal() - 1; i >= 0; i--) {
                if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
                    if(OrderSymbol() == m_symbolInfo.GetSymbol()) {
                        double currentPrice = OrderType() == OP_BUY ?
                            m_symbolInfo.GetBid() : m_symbolInfo.GetAsk();

                        // Calculate trailing stop distance based on instrument type
                        double trailingDistance = m_symbolInfo.IsCryptoPair() ?
                            currentPrice * (CRYPTO_STOP_PERCENT / 100.0) :
                            FOREX_STOP_PIPS * m_symbolInfo.GetPipSize();

                        double newStopLoss = OrderType() == OP_BUY ?
                            currentPrice - trailingDistance :
                            currentPrice + trailingDistance;

                        // Move stop loss if price has moved enough
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
    
    bool ModifyPosition(int ticket, double sl, double tp = 0) {
        if(!OrderSelect(ticket, SELECT_BY_TICKET)) {
            LogTradeError("Order select failed", GetLastError());
            return false;
        }
        
        bool success = OrderModify(ticket, OrderOpenPrice(), sl, tp, 0);
        if(!success) {
            LogTradeError("Order modify failed", GetLastError());
        }
        
        return success;
    }
    
    // Position information methods
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
                    metrics.usedMargin += OrderMargin();
                }
            }
        }
        
        if(metrics.totalPositions > 0) {
            metrics.weightedPrice /= metrics.totalVolume;
        }
        
        return metrics;
    }
    
    // Trade permission control
    void EnableTrading() { m_isTradeAllowed = true; }
    void DisableTrading() { m_isTradeAllowed = false; }
    bool CanTrade() const { return m_isTradeAllowed && IsTradeAllowed(); }
    
    // Last trade information
    TradeRecord GetLastTrade() const { return m_lastTrade; }
    
private:
    // Helper method to convert string reason to enum
    ENUM_CLOSE_REASON StringToCloseReason(string reason) {
        if(reason == "SL") return CLOSE_SL;
        if(reason == "TP") return CLOSE_TP;
        if(reason == "EMERGENCY") return CLOSE_EMERGENCY;
        if(reason == "PROFIT_PROTECTION") return CLOSE_PROFIT_PROTECTION;
        return CLOSE_MANUAL;
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
};