//+------------------------------------------------------------------+
//|                                                    SymbolInfo.mqh   |
//|                                                      TradeJourney  |
//|                                          https://tradejourney.ai   |
//+------------------------------------------------------------------+
#property copyright "TradeJourney"
#property link      "https://tradejourney.ai"
#property strict

#include "Constants.mqh"

// Symbol type enumeration
enum ENUM_SYMBOL_TYPE {
    SYMBOL_TYPE_FOREX,    // Standard forex pairs
    SYMBOL_TYPE_CRYPTO,   // Cryptocurrency pairs
    SYMBOL_TYPE_UNKNOWN   // Unknown instrument type
};

//+------------------------------------------------------------------+
//| Class for managing symbol-specific information and calculations     |
//+------------------------------------------------------------------+
class CSymbolInfo {
private:
    string          m_symbol;           // Symbol name
    ENUM_SYMBOL_TYPE m_symbolType;      // Symbol classification
    bool            m_isJPYPair;        // JPY pair flag
    int             m_digits;           // Price digits
    double          m_contractSize;     // Contract size
    double          m_marginPercent;    // Margin requirement
    double          m_pipSize;          // Size of one pip
    double          m_point;            // Point size
    
    // Initialize symbol properties
    void Initialize() {
        m_point = MarketInfo(m_symbol, MODE_POINT);
        DetermineSymbolType();
        SetSymbolProperties();
    }

    
    // Determine symbol type and characteristics
    void DetermineSymbolType() {
        // Check for specific crypto pairs
        if(StringFind(m_symbol, "BTC") >= 0) {
            m_symbolType = SYMBOL_TYPE_CRYPTO;
            m_digits = CRYPTO_DIGITS_BTC;
        }
        else if(StringFind(m_symbol, "ETH") >= 0) {
            m_symbolType = SYMBOL_TYPE_CRYPTO;
            m_digits = CRYPTO_DIGITS_ETH;
        }
        else if(StringFind(m_symbol, "LTC") >= 0) {
            m_symbolType = SYMBOL_TYPE_CRYPTO;
            m_digits = CRYPTO_DIGITS_LTC;
        }
        else if(StringFind(m_symbol, "XRP") >= 0) {
            m_symbolType = SYMBOL_TYPE_CRYPTO;
            m_digits = CRYPTO_DIGITS_XRP;
        }
        else {
            m_symbolType = SYMBOL_TYPE_FOREX;
            m_digits = FOREX_DIGITS;
        }
    }
    
    // Set symbol-specific properties
    void SetSymbolProperties() {
        // Set contract size and margin based on symbol type
        if(m_symbolType == SYMBOL_TYPE_CRYPTO) {
            if(StringFind(m_symbol, "LTC") >= 0) {
                m_contractSize = CRYPTO_CONTRACT_SIZE_LTC;
                m_marginPercent = CRYPTO_MARGIN_PERCENT_LTC;
            } else if(StringFind(m_symbol, "XRP") >= 0) {
                m_contractSize = CRYPTO_CONTRACT_SIZE_XRP;
                m_marginPercent = CRYPTO_MARGIN_PERCENT_XRP;
            } else {
                m_contractSize = CRYPTO_CONTRACT_SIZE_DEFAULT;
                m_marginPercent = CRYPTO_MARGIN_PERCENT_DEFAULT;
            }
            m_pipSize = m_point;  // For crypto, pip size equals point size
        } else {
            m_contractSize = FOREX_CONTRACT_SIZE;
            m_marginPercent = FOREX_MARGIN_PERCENT;
            m_pipSize = m_point * 10;  // For forex, pip size is typically 10 points

            // Check if it's a JPY pair
            m_isJPYPair = (StringFind(m_symbol, "JPY") >= 0);
            if(m_isJPYPair) {
                m_pipSize = m_point * 100;  // JPY pairs have different pip size
            }
        }
    }

public:
    // Constructor
    CSymbolInfo(string symbol) : m_symbol(symbol) {
        Initialize();
    }
    
    // Basic property getters
    string GetSymbol() const { return m_symbol; }
    bool IsCryptoPair() const { return m_symbolType == SYMBOL_TYPE_CRYPTO; }
    bool IsForexPair() const { return m_symbolType == SYMBOL_TYPE_FOREX; }
    bool IsJPYPair() const { return m_isJPYPair; }
    int GetDigits() const { return m_digits; }
    double GetContractSize() const { return m_contractSize; }
    double GetMarginPercent() const { return m_marginPercent; }
    double GetPipSize() const { return m_pipSize; }
    double GetPoint() const { return m_point; }
    
    // Price formatting and normalization
    string FormatPrice(double price) const {
        return DoubleToString(price, m_digits);
    }
    
    double NormalizePrice(double price) const {
        return NormalizeDouble(price, m_digits);
    }
    
    // Market data methods
    double GetBid() {
        return MarketInfo(m_symbol, MODE_BID);
    }

    double GetAsk() {
        return MarketInfo(m_symbol, MODE_ASK);
    }

    double GetSpread() {
        return NormalizePrice(GetAsk() - GetBid());
    }
    
    // Pip value calculations
    double GetPipValue(double lots = 1.0)  {
        double tickValue = MarketInfo(m_symbol, MODE_TICKVALUE);
        return m_isJPYPair ? (tickValue * 100 * lots) : (tickValue * 10 * lots);
    }
    
    // Convert price difference to pips
    double PriceToPips(double priceChange)  {
        return MathAbs(priceChange) / m_pipSize;
    }
    
    // Convert pips to price difference
    double PipsToPrice(double pips)  {
        return pips * m_pipSize;
    }
    
    
    // Validate stop loss level
    bool ValidateStopLoss(int orderType, double entryPrice, double stopLoss) {
        if(stopLoss <= 0) return false;
        
        double minDistance = MarketInfo(m_symbol, MODE_STOPLEVEL) * m_point;
        double actualDistance = MathAbs(entryPrice - stopLoss);
        
        // Check minimum broker distance
        if(actualDistance < minDistance) return false;
        
        // For BUY orders, stop loss must be below entry
        if(orderType == OP_BUY && stopLoss >= entryPrice) {
            Logger.Error("BUY stop loss (SL2) must be below entry price");
            return false;
        }
        // For SELL orders, stop loss must be above entry
        if(orderType == OP_SELL && stopLoss <= entryPrice) {
            Logger.Error("SELL stop loss (SL2) must be above entry price");
            return false;
        }
        
        return true;
    }
    
    // Calculate stop loss price
    //double CalculateStopLoss(int orderType, double entryPrice) const {
    //    double stopDistance;
        
    //    if(m_symbolType == SYMBOL_TYPE_CRYPTO) {
    //        stopDistance = entryPrice * (CRYPTO_STOP_PERCENT / 100.0);
    //    } else {
    //        stopDistance = FOREX_STOP_PIPS * m_pipSize;
    //    }
        
    //    return NormalizePrice(orderType == OP_BUY ? 
    //        entryPrice - stopDistance : entryPrice + stopDistance);
    //}

    // Calculate emergency stop distance
    double GetEmergencyStopDistance() {
        if(m_symbolType == SYMBOL_TYPE_CRYPTO) {
            return CRYPTO_EMERGENCY_STOP_PERCENT / 100.0;
        } else {
            return FOREX_EMERGENCY_PIPS * m_pipSize;
        }
    }

    // Check if stop loss is at emergency level
    bool IsEmergencyStopLevel(double entryPrice, double stopLoss, int orderType) {
        double emergencyDistance = GetEmergencyStopDistance();
        double actualDistance = MathAbs(entryPrice - stopLoss);
        
        if(orderType == OP_BUY) {
            return stopLoss <= (entryPrice - emergencyDistance);
        } else {
            return stopLoss >= (entryPrice + emergencyDistance);
        }
    }
};