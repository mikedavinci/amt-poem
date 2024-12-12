//+------------------------------------------------------------------+
//|                                                      SymbolInfo.mqh |
//|                                           Copyright 2024, TradeJourney|
//|                                             https://www.tradejourney.ai|
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, TradeJourney"
#property link      "https://www.tradejourney.ai"
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| Symbol Type Enums                                                  |
//+------------------------------------------------------------------+
enum ENUM_SYMBOL_TYPE {
    SYMBOL_FOREX,    // Standard Forex pairs
    SYMBOL_CRYPTO,   // Cryptocurrency pairs
    SYMBOL_UNKNOWN   // Unknown instrument type
};

enum ENUM_CRYPTO_TYPE {
    CRYPTO_BTC,      // Bitcoin pairs
    CRYPTO_ETH,      // Ethereum pairs
    CRYPTO_LTC,      // Litecoin pairs
    CRYPTO_NONE      // Not a crypto pair
};

//+------------------------------------------------------------------+
//| Symbol Information Class                                           |
//+------------------------------------------------------------------+
class CSymbolInfo {
private:
    string          m_symbol;           // Symbol name
    ENUM_SYMBOL_TYPE m_symbolType;      // Symbol type
    ENUM_CRYPTO_TYPE m_cryptoType;      // Crypto type if applicable
    bool            m_isJPYPair;        // JPY pair flag
    int             m_digits;           // Price digits
    double          m_contractSize;     // Contract size
    double          m_marginPercent;    // Margin requirement

    // Initialize symbol type
    void InitializeSymbolType() {
        // Determine crypto type first
        if(StringFind(m_symbol, "BTC") >= 0) {
            m_cryptoType = CRYPTO_BTC;
            m_symbolType = SYMBOL_CRYPTO;
        }
        else if(StringFind(m_symbol, "ETH") >= 0) {
            m_cryptoType = CRYPTO_ETH;
            m_symbolType = SYMBOL_CRYPTO;
        }
        else if(StringFind(m_symbol, "LTC") >= 0) {
            m_cryptoType = CRYPTO_LTC;
            m_symbolType = SYMBOL_CRYPTO;
        }
        else {
            m_cryptoType = CRYPTO_NONE;
            m_symbolType = SYMBOL_FOREX;
        }

        // Check for JPY pair
        m_isJPYPair = (StringFind(m_symbol, "JPY") >= 0);
    }

public:
    // Constructor
    CSymbolInfo(string symbol) {
        m_symbol = symbol;
        InitializeSymbolType();
        
        // Set digits based on symbol type
        if(m_symbolType == SYMBOL_CRYPTO) {
            m_digits = CRYPTO_DIGITS;
        }
        else if(m_isJPYPair) {
            m_digits = 3;
        }
        else {
            m_digits = FOREX_DIGITS;
        }
        
        // Set contract size
        if(m_cryptoType == CRYPTO_LTC) {
            m_contractSize = CRYPTO_CONTRACT_SIZE_LTC;
        }
        else if(m_symbolType == SYMBOL_CRYPTO) {
            m_contractSize = CRYPTO_CONTRACT_SIZE_DEFAULT;
        }
        else {
            m_contractSize = FOREX_CONTRACT_SIZE;
        }
        
        // Set margin percentage
        if(m_cryptoType == CRYPTO_LTC) {
            m_marginPercent = CRYPTO_MARGIN_PERCENT_LTC;
        }
        else if(m_symbolType == SYMBOL_CRYPTO) {
            m_marginPercent = CRYPTO_MARGIN_PERCENT_DEFAULT;
        }
        else {
            m_marginPercent = FOREX_MARGIN_PERCENT;
        }
    }
    
    // Getters
    string GetSymbol() const { return m_symbol; }
    bool IsCryptoPair() const { return m_symbolType == SYMBOL_CRYPTO; }
    bool IsForexPair() const { return m_symbolType == SYMBOL_FOREX; }
    bool IsJPYPair() const { return m_isJPYPair; }
    int GetDigits() const { return m_digits; }
    double GetContractSize() const { return m_contractSize; }
    double GetMarginPercent() const { return m_marginPercent; }
    ENUM_SYMBOL_TYPE GetSymbolType() const { return m_symbolType; }
    ENUM_CRYPTO_TYPE GetCryptoType() const { return m_cryptoType; }
    
    // Market specific calculations
    double GetPipSize() const {
        return m_isJPYPair ? 0.01 : 0.0001;
    }
    
    double GetPipValue(double lots) const {
        double tickValue = MarketInfo(m_symbol, MODE_TICKVALUE);
        return m_isJPYPair ? (tickValue * 100 * lots) : (tickValue * 10 * lots);
    }
    
    double GetMaxPriceDeviation() const {
        if(m_symbolType == SYMBOL_CRYPTO) return 100.0;    // $100 for crypto
        if(m_isJPYPair) return 0.5;                       // 50 pips for JPY pairs
        return 0.005;                                     // 50 pips for regular forex
    }
    
    // Format price with correct digits
    string FormatPrice(double price) const {
        return DoubleToString(price, m_digits);
    }
    
    // Normalize price
    double NormalizePrice(double price) const {
        return NormalizeDouble(price, m_digits);
    }
};
