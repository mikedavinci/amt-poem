//+------------------------------------------------------------------+
//|                                                       Logger.mqh    |
//|                                                      TradeJourney  |
//|                                          https://tradejourney.ai   |
//+------------------------------------------------------------------+
#property copyright "TradeJourney"
#property link      "https://tradejourney.ai"
#property strict

#include "Constants.mqh"

// Logging levels
enum ENUM_LOG_LEVEL {
    LOG_ERROR,      // Error messages
    LOG_WARNING,    // Warning messages
    LOG_INFO,       // Information messages
    LOG_DEBUG,      // Debug messages
    LOG_TRADE       // Trade-related messages
};

//+------------------------------------------------------------------+
//| Class for managing logging and debug output                        |
//+------------------------------------------------------------------+
class CLogger {
private:
    bool            m_debugMode;         // Debug mode flag
    bool            m_enablePapertrail;  // External logging flag
    string          m_systemName;        // System identifier
    string          m_papertrailHost;    // External logging endpoint
    
    // Format message with timestamp and symbol
    string FormatLogMessage(string message, string symbol = "") {
        string timeStr = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
        string symbolStr = (symbol == "") ? Symbol() : symbol;
        return StringFormat("%s | %s | %s", timeStr, symbolStr, message);
    }
    
    // Convert internal log level to API level
    string GetApiLogLevel(ENUM_LOG_LEVEL level) {
        switch(level) {
            case LOG_ERROR:   return "error";
            case LOG_WARNING: return "warn";
            case LOG_DEBUG:   return "debug";
            case LOG_TRADE:   return "info";
            default:          return "info";
        }
    }
    
    // Escape JSON special characters
    string EscapeJsonString(string str) {
        string result = str;
        StringReplace(result, "\"", "\\\"");
        StringReplace(result, "\n", "\\n");
        StringReplace(result, "\r", "\\r");
        StringReplace(result, "\t", "\\t");
        return result;
    }
    
    // Send log to external service
    void SendToPapertrail(string message, ENUM_LOG_LEVEL level, string symbol = "") {
        if(!m_enablePapertrail) return;
        
        // Format timestamp in ISO 8601
        datetime currentTime = TimeCurrent();
        string isoTimestamp = StringFormat(
            "%d-%02d-%02dT%02d:%02d:%02dZ",
            TimeYear(currentTime),
            TimeMonth(currentTime),
            TimeDay(currentTime),
            TimeHour(currentTime),
            TimeMinute(currentTime),
            TimeSeconds(currentTime)
        );
        
        // Build metadata object
        string metadata = StringFormat(
            "{\"system\":\"%s\",\"timestamp\":\"%s\",\"level\":\"%s\",\"account\":%d,\"symbol\":\"%s\"}",
            m_systemName,
            isoTimestamp,
            GetApiLogLevel(level),
            AccountNumber(),
            symbol == "" ? Symbol() : symbol
        );
        
        // Build payload
        string payload = StringFormat(
            "{\"message\":\"%s\",\"level\":\"%s\",\"metadata\":%s}",
            EscapeJsonString(message),
            GetApiLogLevel(level),
            metadata
        );
        
        // Prepare web request
        string headers = "Content-Type: application/json\r\n";
        char post[];
        ArrayResize(post, StringLen(payload));
        StringToCharArray(payload, post, 0, StringLen(payload));
        
        char result[];
        string resultHeaders;
        
        // Send request
        ResetLastError();
        int res = WebRequest(
            "POST",
            m_papertrailHost,
            headers,
            5000,
            post,
            result,
            resultHeaders
        );
        
        if(res == -1) {
            int error = GetLastError();
            if(error == 4060) {
                PrintError("Enable WebRequest for URL: " + m_papertrailHost);
                PrintError("Add URL to MetaTrader -> Tools -> Options -> Expert Advisors -> Allow WebRequest");
            } else {
                PrintError(StringFormat("Failed to send log. Error: %d", error));
            }
        }
    }
    
    // Print to MT4 terminal
    void PrintToTerminal(string message, ENUM_LOG_LEVEL level) {
        string prefix;
        color messageColor;
        
        switch(level) {
            case LOG_ERROR:
                prefix = "ERROR: ";
                messageColor = clrRed;
                break;
            case LOG_WARNING:
                prefix = "WARNING: ";
                messageColor = clrOrange;
                break;
            case LOG_DEBUG:
                if(!m_debugMode) return;
                prefix = "DEBUG: ";
                messageColor = clrGray;
                break;
            case LOG_TRADE:
                prefix = "TRADE: ";
                messageColor = clrBlue;
                break;
            default:
                prefix = "INFO: ";
                messageColor = clrBlack;
        }
        
        PrintFormat("%s%s", prefix, message);
    }

public:
    // Constructor
    CLogger(bool debugMode = false, 
            bool enablePapertrail = false,
            string systemName = "EA-TradeJourney",
            string papertrailHost = "")
        : m_debugMode(debugMode),
          m_enablePapertrail(enablePapertrail),
          m_systemName(systemName),
          m_papertrailHost(papertrailHost) {
    }
    
    // Logging methods
    void Error(string message, string symbol = "") {
        string formattedMessage = FormatLogMessage(message, symbol);
        PrintToTerminal(formattedMessage, LOG_ERROR);
        SendToPapertrail(formattedMessage, LOG_ERROR, symbol);
    }
    
    void Warning(string message, string symbol = "") {
        string formattedMessage = FormatLogMessage(message, symbol);
        PrintToTerminal(formattedMessage, LOG_WARNING);
        SendToPapertrail(formattedMessage, LOG_WARNING, symbol);
    }
    
    void Info(string message, string symbol = "") {
        string formattedMessage = FormatLogMessage(message, symbol);
        PrintToTerminal(formattedMessage, LOG_INFO);
        SendToPapertrail(formattedMessage, LOG_INFO, symbol);
    }
    
    void Debug(string message, string symbol = "") {
        if(!m_debugMode) return;
        string formattedMessage = FormatLogMessage(message, symbol);
        PrintToTerminal(formattedMessage, LOG_DEBUG);
        SendToPapertrail(formattedMessage, LOG_DEBUG, symbol);
    }
    
    void Trade(string message, string symbol = "") {
        string formattedMessage = FormatLogMessage(message, symbol);
        PrintToTerminal(formattedMessage, LOG_TRADE);
        SendToPapertrail(formattedMessage, LOG_TRADE, symbol);
    }
    
    // Configuration methods
    void EnableDebugMode(bool enable) { m_debugMode = enable; }
    void EnablePapertrail(bool enable) { m_enablePapertrail = enable; }
    void SetSystemName(string name) { m_systemName = name; }
    void SetPapertrailHost(string host) { m_papertrailHost = host; }
    
    // Print error direct to terminal (for internal use)
    void PrintError(string message) {
        PrintFormat("ERROR: %s", message);
    }
};

// Global logger instance
CLogger Logger;

// The Logger is implemented as a global instance to allow easy access from any part of the code:
// Usage example:
// Log different types of messages
// Logger.Error("Critical error occurred");
// Logger.Warning("Spread too high");
// Logger.Info("EA initialized successfully");
// Logger.Debug("Calculating position size...");
// Logger.Trade("Opening BUY position");

// Configure logger
// Logger.EnableDebugMode(true);
// Logger.EnablePapertrail(true);
// Logger.SetSystemName("MyEA");
// Logger.SetPapertrailHost("https://logs.papertrailapp.com/api/events");