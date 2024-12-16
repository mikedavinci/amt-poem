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
        } else {
            LogTradeError("Order close failed", GetLastError());
        }
        
        return success;
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

            for(int i = total - 1; i >= 0; i--) {
                if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
                    if(OrderSymbol() == m_symbolInfo.GetSymbol()) {
                        ENUM_TRADE_SIGNAL currentPos =
                            (OrderType() == OP_BUY) ? SIGNAL_BUY : SIGNAL_SELL;

                        // Close if signals are opposite
                        if(currentPos != newSignal) {
                            if(!ClosePosition(OrderTicket(), "Signal reversal")) {
                                allClosed = false;
                                Logger.Error("Failed to close position for reversal");
                            }
                        }
                    }
                }
            }
            return allClosed;
        }
};