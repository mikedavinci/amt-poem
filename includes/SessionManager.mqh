//+------------------------------------------------------------------+
//|                                                SessionManager.mqh   |
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
//| Class for managing trading sessions and market hours               |
//+------------------------------------------------------------------+
class CSessionManager {
private:
    CSymbolInfo*    m_symbolInfo;       // Symbol information
    bool            m_tradeAsian;        // Allow trading in Asian session
    bool            m_tradeLondon;       // Allow trading in London session
    bool            m_tradeNewYork;      // Allow trading in NY session
    bool            m_allowOverlap;      // Allow trading during session overlaps
    static datetime s_lastSessionCheck;  // Static timestamp for session checks

    // Session time checking
    bool IsInSession(int startHour, int endHour) const {
        int currentHour = TimeHour(TimeCurrent());
        
        if(startHour < endHour) {
            return (currentHour >= startHour && currentHour < endHour);
        } else {
            return (currentHour >= startHour || currentHour < endHour);
        }
    }

public:
    // Constructor
    CSessionManager(CSymbolInfo* symbolInfo, 
                   bool tradeAsian = true,
                   bool tradeLondon = true,
                   bool tradeNewYork = true,
                   bool allowOverlap = true)
        : m_symbolInfo(symbolInfo),
          m_tradeAsian(tradeAsian),
          m_tradeLondon(tradeLondon),
          m_tradeNewYork(tradeNewYork),
          m_allowOverlap(allowOverlap) {
        if(s_lastSessionCheck == 0) s_lastSessionCheck = TimeCurrent();
    }
    
    // Check if market is currently open
    bool IsMarketOpen() {
        // Crypto markets trade 24/7
        if(m_symbolInfo.IsCryptoPair()) {
            return true;
        }
        
        // Check if it's weekend
        int dayOfWeek = TimeDayOfWeek(TimeCurrent());
        if(dayOfWeek == SATURDAY || dayOfWeek == SUNDAY) {
            datetime currentTime = TimeCurrent();
            if(currentTime - s_lastSessionCheck >= 300) { // Log every 5 minutes
                Logger.Debug("Market closed - Weekend");
                s_lastSessionCheck = currentTime;
            }
            return false;
        }
        
        // Check if current session is allowed
        return IsSessionActive();
    }
    
    // Check if current trading session is active
    bool IsSessionActive() {
        // Crypto pairs can trade in any session
        if(m_symbolInfo.IsCryptoPair()) {
            return true;
        }
        
        bool inAsianSession = IsInSession(ASIAN_SESSION_START, ASIAN_SESSION_END);
        bool inLondonSession = IsInSession(LONDON_SESSION_START, LONDON_SESSION_END);
        bool inNewYorkSession = IsInSession(NEWYORK_SESSION_START, NEWYORK_SESSION_END);
        
        // Check session overlaps
        bool inLondonNYOverlap = (inLondonSession && inNewYorkSession);
        bool inAsianLondonOverlap = (inAsianSession && inLondonSession);
        
        // Allow trading during overlaps if enabled
        if(m_allowOverlap && (inLondonNYOverlap || inAsianLondonOverlap)) {
            Logger.Debug("Trading allowed - Session overlap");
            return true;
        }
        
        // Check individual sessions
        if(inAsianSession && m_tradeAsian) {
            ValidateSessionPairs(ENUM_SESSION_TYPE::SESSION_ASIAN);
            return true;
        }
        if(inLondonSession && m_tradeLondon) {
            ValidateSessionPairs(ENUM_SESSION_TYPE::SESSION_LONDON);
            return true;
        }
        if(inNewYorkSession && m_tradeNewYork) {
            ValidateSessionPairs(ENUM_SESSION_TYPE::SESSION_NEWYORK);
            return true;
        }
        
        Logger.Debug("No active trading session");
        return false;
    }
    
    // Validate currency pairs for specific sessions
    void ValidateSessionPairs(ENUM_SESSION_TYPE session) {
        string symbol = m_symbolInfo.GetSymbol();
        
        if(session == SESSION_ASIAN && 
           StringFind(symbol, "JPY") >= 0 &&
           !IsInSession(ASIAN_SESSION_START, ASIAN_SESSION_END)) {
            Logger.Warning("Trading JPY pair outside Asian session");
        }
        
        if(session == SESSION_LONDON && 
           (StringFind(symbol, "GBP") >= 0 || StringFind(symbol, "EUR") >= 0) &&
           !IsInSession(LONDON_SESSION_START, LONDON_SESSION_END)) {
            Logger.Warning("Trading European pair outside London session");
        }
    }
    
    // Calculate session liquidity level
    string GetLiquidityLevel() {
        if(m_symbolInfo.IsCryptoPair()) return "Normal";
        
        if(IsInSession(LONDON_SESSION_START, LONDON_SESSION_END) &&
           IsInSession(NEWYORK_SESSION_START, NEWYORK_SESSION_END)) {
            return "High";  // London/NY overlap
        }
        
        if(IsInSession(ASIAN_SESSION_START, ASIAN_SESSION_END) &&
           IsInSession(LONDON_SESSION_START, LONDON_SESSION_END)) {
            return "High";  // Asian/London overlap
        }
        
        if(IsInSession(LONDON_SESSION_START, LONDON_SESSION_END)) {
            return "High";  // London session
        }
        
        if(IsInSession(NEWYORK_SESSION_START, NEWYORK_SESSION_END)) {
            return "Moderate";  // NY session
        }
        
        if(IsInSession(ASIAN_SESSION_START, ASIAN_SESSION_END)) {
            return "Moderate";  // Asian session
        }
        
        return "Low";  // Off-hours
    }
    
    // Session configuration methods
    void EnableAsianSession(bool enable) { m_tradeAsian = enable; }
    void EnableLondonSession(bool enable) { m_tradeLondon = enable; }
    void EnableNewYorkSession(bool enable) { m_tradeNewYork = enable; }
    void EnableSessionOverlap(bool enable) { m_allowOverlap = enable; }
};

// Initialize static members
datetime CSessionManager::s_lastSessionCheck = 0;