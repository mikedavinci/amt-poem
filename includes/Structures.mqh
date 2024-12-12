//+------------------------------------------------------------------+
//|                                                    Structures.mqh   |
//|                                                      TradeJourney  |
//|                                          https://tradejourney.ai   |
//+------------------------------------------------------------------+
#property copyright "TradeJourney"
#property link      "https://tradejourney.ai"
#property strict

// Enum definitions
enum ENUM_TRADE_SIGNAL {
    SIGNAL_BUY,
    SIGNAL_SELL,
    SIGNAL_NEUTRAL
};

enum ENUM_SESSION_TYPE {
    SESSION_ASIAN,
    SESSION_LONDON,
    SESSION_NEWYORK,
    SESSION_OVERLAP
};

enum ENUM_CLOSE_REASON {
    CLOSE_SL,
    CLOSE_TP,
    CLOSE_MANUAL,
    CLOSE_EMERGENCY,
    CLOSE_PROFIT_PROTECTION
};

// Signal Data Structure
struct SignalData {
    string            ticker;        // Trading symbol
    ENUM_TRADE_SIGNAL signal;       // BUY, SELL, or NEUTRAL
    double            price;         // Signal price
    datetime          timestamp;     // Signal timestamp
    string            pattern;       // Trading pattern
    
    // Constructor
    SignalData() : ticker(""), signal(SIGNAL_NEUTRAL), price(0), timestamp(0), pattern("") {}
};

// Trade Record Structure
struct TradeRecord {
    int               ticket;        // Trade ticket number
    string            symbol;        // Trading symbol
    ENUM_TRADE_SIGNAL direction;    // Trade direction
    double            lots;          // Position size
    double            openPrice;     // Entry price
    double            closePrice;    // Exit price
    double            stopLoss;      // Stop loss price
    datetime          openTime;      // Entry time
    datetime          closeTime;     // Exit time
    ENUM_CLOSE_REASON closeReason;  // Reason for closure
    double            profit;        // Final P/L
    string            comment;       // Additional info
    
    // Constructor
    TradeRecord() : ticket(0), symbol(""), direction(SIGNAL_NEUTRAL), lots(0),
                    openPrice(0), closePrice(0), stopLoss(0), openTime(0),
                    closeTime(0), closeReason(CLOSE_MANUAL), profit(0), comment("") {}
};

// Position Metrics Structure
struct PositionMetrics {
    int      totalPositions;     // Number of open positions
    double   totalVolume;        // Total position size
    double   weightedPrice;      // Average entry price
    double   unrealizedPL;       // Current floating P/L
    double   usedMargin;         // Margin in use
    double   riskExposure;       // Current risk amount
    
    // Constructor
    PositionMetrics() : totalPositions(0), totalVolume(0), weightedPrice(0),
                        unrealizedPL(0), usedMargin(0), riskExposure(0) {}
};