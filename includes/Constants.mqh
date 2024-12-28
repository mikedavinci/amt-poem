//+------------------------------------------------------------------+
//|                                                     Constants.mqh   |
//|                                                      TradeJourney  |
//|                                          https://tradejourney.ai   |
//+------------------------------------------------------------------+
#property copyright "TradeJourney"
#property link      "https://tradejourney.ai"
#property strict

// Error Code Constants
#define ERR_CUSTOM_START              65536
#define ERR_CUSTOM_ERROR             (ERR_CUSTOM_START + 1)
#define ERR_CUSTOM_CRITICAL          (ERR_CUSTOM_START + 2)

// Tolerance
#define ENTRY_PRICE_TOLERANCE_PERCENT 1.0  // 1.0% tolerance for entry price
#define FOREX_ENTRY_TOLERANCE_PERCENT   0.5   // Keep 0.5% for forex
#define BTC_ENTRY_TOLERANCE_PERCENT     2.5   // Allow 2.5% for BTC
#define ETH_ENTRY_TOLERANCE_PERCENT     2.5   // Allow 2.5% for ETH
#define LTC_ENTRY_TOLERANCE_PERCENT     2.5   // Allow 2.5% for LTC

// Forex Constants
#define FOREX_CONTRACT_SIZE          100000
#define FOREX_MARGIN_PERCENT         100.0
#define FOREX_DIGITS                 5
#define FOREX_MARGIN_INITIAL         100000

// Crypto Constants - Only for BTC, ETH, LTC
#define CRYPTO_DIGITS_BTC           5
#define CRYPTO_DIGITS_ETH           5
#define CRYPTO_DIGITS_LTC           5
#define CRYPTO_CONTRACT_SIZE_DEFAULT 1
#define CRYPTO_MARGIN_PERCENT_DEFAULT 0.003  // 0.3%
#define CRYPTO_CONTRACT_SIZE_LTC    100
#define CRYPTO_MARGIN_PERCENT_LTC   0.01     // 1.0%

// Risk Management Constants
#define DEFAULT_RISK_PERCENT        3.0  
#define MAX_POSITIONS_PER_SYMBOL    1
#define MAX_RETRY_ATTEMPTS          3
#define DEFAULT_SLIPPAGE           5
#define EMERGENCY_CLOSE_PERCENT    5

// Regular Stops
// #define FOREX_STOP_PIPS           80
 #define CRYPTO_STOP_PERCENT       3.0 // Risk per Tade for crypto

// Emergency Stops
#define FOREX_EMERGENCY_PIPS      80
#define CRYPTO_EMERGENCY_STOP_PERCENT 5.0

// ATR-based Stops
// #define ATR_PERIOD               14      // Period for ATR calculation
// #define FOREX_ATR_MULTIPLIER     2.0     // Multiplier for forex pairs
// #define CRYPTO_ATR_MULTIPLIER    2.5     // Higher multiplier for crypto due to volatility

// BREAKEVEN settings for Forex
// #define FOREX_BREAKEVEN_PROFIT_PIPS   20    // Pips of profit before breakeven
// #define FOREX_BREAKEVEN_BUFFER_PIPS   2     // Buffer pips above entry price

// BREAKEVEN settings for Crypto
// #define CRYPTO_BREAKEVEN_PROFIT_PERCENT 5.0  // Percentage of profit before breakeven (1%)
// #define CRYPTO_BREAKEVEN_BUFFER_PERCENT 0.5  // Buffer percentage above entry price (0.1%)

// Profit Protection Settings
#define PROFIT_CHECK_INTERVAL      300    // Check profit every 5 minutes
#define FOREX_PROFIT_PIPS_THRESHOLD 30
#define FOREX_PROFIT_LOCK_PIPS     10
#define CRYPTO_PROFIT_THRESHOLD    5.0
#define CRYPTO_PROFIT_LOCK_PERCENT 0.75

// Trading Session Hours (Server Time)
#define ASIAN_SESSION_START      22
#define ASIAN_SESSION_END        8
#define LONDON_SESSION_START     8
#define LONDON_SESSION_END       16
#define NEWYORK_SESSION_START    13
#define NEWYORK_SESSION_END      22

// API Settings
#define API_TIMEOUT             5000      // 5000ms (5 seconds) timeout for API calls
#define API_RETRY_INTERVAL      5000      // 5 second between retries
#define INITIAL_RETRY_DELAY     100       // 100ms initial delay
#define MAX_RETRY_DELAY         5000      // 5 seconds maximum delay
#define SIGNAL_CHECK_INTERVAL    1800    // Check signals every half hour (1800 seconds)
#define RISK_CHECK_INTERVAL        300    // Check risk every 5 minutes

#define GLOBAL_VAR_PREFIX "AMT_POEM_"
#define GLOBAL_LAST_CHECK GLOBAL_VAR_PREFIX + "LAST_CHECK"
#define GLOBAL_LAST_SIGNAL GLOBAL_VAR_PREFIX + "LAST_SIGNAL"
#define GLOBAL_AWAITING_OPPOSITE GLOBAL_VAR_PREFIX + "AWAITING_OPPOSITE"
#define GLOBAL_LAST_DIRECTION GLOBAL_VAR_PREFIX + "LAST_DIRECTION"
#define GLOBAL_LAST_TRADE_TICKET GLOBAL_VAR_PREFIX + "LAST_TRADE_TICKET"
#define GLOBAL_LAST_TRADE_TYPE GLOBAL_VAR_PREFIX + "LAST_TRADE_TYPE"
#define GLOBAL_LAST_TRADE_LOTS GLOBAL_VAR_PREFIX + "LAST_TRADE_LOTS"
#define GLOBAL_LAST_TRADE_PRICE GLOBAL_VAR_PREFIX + "LAST_TRADE_PRICE"