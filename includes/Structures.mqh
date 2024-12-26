//+------------------------------------------------------------------+
//|                                                    Structures.mqh   |
//|                                                      TradeJourney  |
//|                                          https://tradejourney.ai   |
//+------------------------------------------------------------------+
#property copyright "TradeJourney"
#property link      "https://tradejourney.ai"
#property strict

// Add new enum for instrument types
enum ENUM_INSTRUMENT_TYPE {
    INSTRUMENT_FOREX,
    INSTRUMENT_CRYPTO
};

enum ENUM_EXIT_TYPE {
    EXIT_NONE = 0,
    EXIT_BEARISH = 1,
    EXIT_BULLISH = 2
};


// Enum definitions
enum ENUM_TRADE_SIGNAL {
    SIGNAL_NEUTRAL = 0,
    SIGNAL_BUY = 1,
    SIGNAL_SELL = 2
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
    CLOSE_PROFIT_PROTECTION,
    CLOSE_EXIT_SIGNAL,        
    CLOSE_OPPOSITE_SIGNAL,
    CLOSE_BREAKEVEN
};

// Signal Data Structure
struct SignalData {
    string            ticker;         // Trading symbol
    ENUM_TRADE_SIGNAL signal;        // BUY, SELL, or NEUTRAL
    double            price;          // Signal price
    datetime          timestamp;      // Signal timestamp
    string            pattern;        // Trading pattern
    ENUM_INSTRUMENT_TYPE instrumentType; // Forex or Crypto
    ENUM_EXIT_TYPE   exitType;       // EXIT_BEARISH or EXIT_BULLISH
    bool             isExit;         // Exit signal flag
    double           sl2;            // Stop Loss 2 from API
    double           tp1;            // Take Profit 1 (from exit signals/current price)
    double           tp2;            // Take Profit 2 (from exit signals/current price)

    // Constructor
    SignalData() : ticker(""), signal(SIGNAL_NEUTRAL), price(0),
                   timestamp(0), pattern(""), 
                   instrumentType(INSTRUMENT_FOREX),
                   exitType(EXIT_NONE),
                   isExit(false),
                   sl2(0), tp1(0), tp2(0) {}
};

// Trade Record Structure
struct TradeRecord {
    int               ticket;         // Trade ticket number
    string            symbol;         // Trading symbol
    ENUM_TRADE_SIGNAL direction;     // Trade direction
    double            lots;           // Position size
    double            openPrice;      // Entry price
    double            closePrice;     // Exit price
    double            stopLoss;       // Stop loss price
    double            trailingStop;   // Current trailing stop level
    bool             trailingStopHit; // Flag for trailing stop hit
    datetime          openTime;       // Entry time
    datetime          closeTime;      // Exit time
    ENUM_CLOSE_REASON closeReason;   // Reason for closure
    double            profit;         // Final P/L
    string            comment;        // Additional info
    ENUM_INSTRUMENT_TYPE instrumentType; // Forex or Crypto

    // Constructor
    TradeRecord() : ticket(0), symbol(""), direction(SIGNAL_NEUTRAL), lots(0),
                    openPrice(0), closePrice(0), stopLoss(0), trailingStop(0),
                    trailingStopHit(false), openTime(0), closeTime(0),
                    closeReason(CLOSE_MANUAL), profit(0), comment(""),
                    instrumentType(INSTRUMENT_FOREX) {}
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