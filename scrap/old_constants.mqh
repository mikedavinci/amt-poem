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
#define DEFAULT_RISK_PERCENT        5.0  
#define MAX_POSITIONS_PER_SYMBOL    1
#define MAX_RETRY_ATTEMPTS          3
#define DEFAULT_SLIPPAGE           5
#define EMERGENCY_CLOSE_PERCENT    5

// Regular Stops
// #define FOREX_STOP_PIPS           80
 #define CRYPTO_STOP_PERCENT       5.0 // Risk per Tade for crypto

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
#define SIGNAL_CHECK_INTERVAL    300    // Check signals every 5 min (300 seconds)
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

// Exit States
#define EXIT_STATE_NONE 0
#define EXIT_STATE_PARTIAL 1
#define EXIT_STATE_COMPLETE 2

// Global Variable Names
#define GV_PARTIAL_EXIT "_PARTIAL_EXIT"
#define GV_ORIGINAL_VOLUME "_ORIGINAL_VOLUME"

// Exit Volume Percentages
#define PARTIAL_EXIT_PERCENT 25.0
#define REMAINING_VOLUME_PERCENT 75.0

// Crypto Market Conditions (BTCUSD, ETHUSD, LTCUSD) 
#define CRYPTO_VOLUME_MA_PERIOD    20     // Volume Moving Average period
#define CRYPTO_MIN_VOLUME_RATIO    0.7    // Minimum ratio to average volume
#define CRYPTO_TREND_FAST_MA       13     // Fast MA for trend detection
#define CRYPTO_TREND_SLOW_MA       34     // Slow MA for trend detection
#define CRYPTO_MIN_TREND_STRENGTH  0.3    // Minimum trend strength percentage
#define CRYPTO_ADX_PERIOD         20     // ADX period for trend strength
#define CRYPTO_MIN_ADX            25     // Minimum ADX value for trend

// Forex Market Conditions
#define FOREX_VOLUME_MA_PERIOD     14     // Shorter for forex due to more consistent volume
#define FOREX_MIN_VOLUME_RATIO     0.8    // Forex needs higher volume confirmation
#define FOREX_TREND_FAST_MA        8      // Faster MA for forex
#define FOREX_TREND_SLOW_MA        21     // Standard slow MA for forex
#define FOREX_MIN_TREND_STRENGTH   0.15   // Lower due to forex having smaller moves
#define FOREX_ADX_PERIOD          14     // Standard forex ADX period
#define FOREX_MIN_ADX             20     // Standard minimum ADX for forex