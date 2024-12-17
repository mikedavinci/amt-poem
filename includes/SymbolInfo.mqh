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
    double          m_atr;              // Current ATR value
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

    // method to calculate ATR
        void CalculateATR() {
            m_atr = iATR(_Symbol, PERIOD_CURRENT, ATR_PERIOD, 0);
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
            } else {
                m_contractSize = CRYPTO_CONTRACT_SIZE_DEFAULT;
                m_marginPercent = CRYPTO_MARGIN_PERCENT_DEFAULT;
            }
        } else {
            m_contractSize = FOREX_CONTRACT_SIZE;
            m_marginPercent = FOREX_MARGIN_PERCENT;
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
    double GetBid() const {
        return MarketInfo(m_symbol, MODE_BID);
    }
    
    double GetAsk() const {
        return MarketInfo(m_symbol, MODE_ASK);
    }
    
    double GetSpread() const {
        return NormalizePrice(GetAsk() - GetBid());
    }
    
    // Pip value calculations
    double GetPipValue(double lots = 1.0) const {
        double tickValue = MarketInfo(m_symbol, MODE_TICKVALUE);
        return m_isJPYPair ? (tickValue * 100 * lots) : (tickValue * 10 * lots);
    }
    
    // Convert price difference to pips
    double PriceToPips(double priceChange) const {
        return MathAbs(priceChange) / m_pipSize;
    }
    
    // Convert pips to price difference
    double PipsToPrice(double pips) const {
        return pips * m_pipSize;
    }
    
    // Get maximum allowed price deviation
    double GetMaxPriceDeviation() const {
        if(m_symbolType == SYMBOL_TYPE_CRYPTO) return 100.0;    // $100 for crypto
        if(m_isJPYPair) return 0.5;                            // 50 pips for JPY pairs
        return 0.005;                                          // 50 pips for regular forex
    }
    
    // Validate stop loss level
    bool ValidateStopLoss(int orderType, double entryPrice, double stopLoss) const {
        if(stopLoss <= 0) return false;
        
        double minDistance = MarketInfo(m_symbol, MODE_STOPLEVEL) * m_point;
        double actualDistance = MathAbs(entryPrice - stopLoss);
        
        if(actualDistance < minDistance) return false;
        
        if(orderType == OP_BUY && stopLoss >= entryPrice) return false;
        if(orderType == OP_SELL && stopLoss <= entryPrice) return false;
        
        return true;
    }
    
    // Calculate stop loss price
    double CalculateStopLoss(int orderType, double entryPrice) const {
        double stopDistance;
        
        if(m_symbolType == SYMBOL_TYPE_CRYPTO) {
            stopDistance = entryPrice * (CRYPTO_STOP_PERCENT / 100.0);
        } else {
            stopDistance = FOREX_STOP_PIPS * m_pipSize;
        }
        
        return NormalizePrice(orderType == OP_BUY ? 
               entryPrice - stopDistance : entryPrice + stopDistance);
    }

    // Add method to get ATR-based stop loss

        // Add these methods
         double GetATR() {
                CalculateATR();
                return m_atr;
            }

            double GetATRStopLoss(int orderType, double entryPrice) {
                    CalculateATR();

                    double multiplier = IsCryptoPair() ?
                        CRYPTO_ATR_MULTIPLIER : FOREX_ATR_MULTIPLIER;

                    double atrStopDistance = m_atr * multiplier;

                    // Calculate emergency stop distance
                    double emergencyStopDistance;
                    if(IsCryptoPair()) {
                        emergencyStopDistance = entryPrice * (CRYPTO_EMERGENCY_STOP_PERCENT / 100.0);
                    } else {
                        emergencyStopDistance = FOREX_EMERGENCY_PIPS * GetPipSize();
                    }

                    // ATR stop should not exceed emergency stop distance
                    double finalStopDistance = MathMin(atrStopDistance, emergencyStopDistance);

                    // Calculate and normalize stop loss price
                    double stopPrice;
                    if(orderType == OP_BUY) {
                        stopPrice = entryPrice - finalStopDistance;

                        // Apply minimum stop distance
                        double minStopDistance = IsCryptoPair() ?
                            entryPrice * (CRYPTO_STOP_PERCENT / 100.0) :
                            FOREX_STOP_PIPS * GetPipSize();

                        stopPrice = MathMin(stopPrice, entryPrice - minStopDistance);
                    } else {
                        stopPrice = entryPrice + finalStopDistance;

                        // Apply minimum stop distance
                        double minStopDistance = IsCryptoPair() ?
                            entryPrice * (CRYPTO_STOP_PERCENT / 100.0) :
                            FOREX_STOP_PIPS * GetPipSize();

                        stopPrice = MathMax(stopPrice, entryPrice + minStopDistance);
                    }

                    Logger.Debug(StringFormat(
                        "Stop Loss Calculation:" +
                        "\nATR Stop Distance: %.5f" +
                        "\nEmergency Stop Distance: %.5f" +
                        "\nFinal Stop Distance: %.5f" +
                        "\nFinal Stop Price: %.5f",
                        atrStopDistance,
                        emergencyStopDistance,
                        finalStopDistance,
                        stopPrice
                    ));

                    return NormalizePrice(stopPrice);
                }
};