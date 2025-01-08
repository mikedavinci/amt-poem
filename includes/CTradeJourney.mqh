//+------------------------------------------------------------------+
//|                                                 CTradeJourney.mqh   |
//|                                                      TradeJourney  |
//|                                          https://tradejourney.ai   |
//+------------------------------------------------------------------+
#property copyright "TradeJourney"
#property link      "https://tradejourney.ai"
#property strict

class CTradeJourney {
private:
    CSymbolInfo* m_symbolInfo;
    CTradeManager* m_tradeManager;
    CRiskManager* m_riskManager;
    CSessionManager* m_sessionManager;
    datetime m_lastCheck;
    datetime m_lastSignalTimestamp;
    string m_currentSymbol;
    datetime m_lastDebugTime;
    bool m_awaitingOppositeSignal;         
    ENUM_TRADE_SIGNAL m_lastClosedDirection;

    // Moving periodic checks to private method
void PerformPeriodicChecks() {
    static datetime lastPeriodicCheck = 0;
    datetime currentTime = TimeCurrent();
    
    // Only run checks and load values every 60 seconds
    if(currentTime - lastPeriodicCheck >= 60) {
        if(m_currentSymbol != Symbol()) return;  
        
        datetime lastCheck = LoadLastCheck();
        if(currentTime - lastCheck >= RISK_CHECK_INTERVAL) {
            if(!m_riskManager.IsMarginSafe()) {
                Logger.Warning("Margin level below safe threshold for " + m_currentSymbol);
            }
            
            string liquidity = m_sessionManager.GetLiquidityLevel();
            SaveLastCheck(currentTime);
        }
        
        lastPeriodicCheck = currentTime;
    }
}

bool IsTimeToCheck() {
    static datetime lastDebugOutput = 0;
    datetime currentTime = TimeCurrent();
    datetime lastSignalCheck = LoadLastSignal();

    // If no signal time saved, initialize it
    if(lastSignalCheck <= 0) {
        SaveLastSignal(currentTime);
        Logger.Info(StringFormat("[%s] Initialized signal check timer", m_currentSymbol));
        return false;
    }

    // Check if enough time has passed
    double timeDiff = double(currentTime - lastSignalCheck);  // Convert to double
    double timeLeft = double(SIGNAL_CHECK_INTERVAL) - timeDiff;  // Use double for calculation

    if(timeLeft > 0) {
        // Only log debug every 5 minutes for each symbol
        if(currentTime - lastDebugOutput >= 300) {
            Logger.Debug(StringFormat("[%s] Next signal check in %.1f minutes", 
                m_currentSymbol, 
                timeLeft/60.0));  // Convert to minutes with decimal precision
            lastDebugOutput = currentTime;
        }
        return false;
    }

    // Time to check - log this event
    Logger.Info(StringFormat("[%s] Performing signal check", m_currentSymbol));
    SaveLastSignal(currentTime);
    return true;
}

bool ValidateMarketConditions() {
    if(!m_symbolInfo) return false;

    // Determine if we're trading crypto or forex
    bool isCrypto = m_symbolInfo.IsCryptoPair();
    
    // Set parameters based on instrument type
    int volumePeriod = isCrypto ? CRYPTO_VOLUME_MA_PERIOD : FOREX_VOLUME_MA_PERIOD;
    double minVolumeRatio = isCrypto ? CRYPTO_MIN_VOLUME_RATIO : FOREX_MIN_VOLUME_RATIO;
    int trendFastMA = isCrypto ? CRYPTO_TREND_FAST_MA : FOREX_TREND_FAST_MA;
    int trendSlowMA = isCrypto ? CRYPTO_TREND_SLOW_MA : FOREX_TREND_SLOW_MA;
    double minTrendStrength = isCrypto ? CRYPTO_MIN_TREND_STRENGTH : FOREX_MIN_TREND_STRENGTH;
    int adxPeriod = isCrypto ? CRYPTO_ADX_PERIOD : FOREX_ADX_PERIOD;
    int minADX = isCrypto ? CRYPTO_MIN_ADX : FOREX_MIN_ADX;

    // Volume Analysis
    long currentVolume = iVolume(m_currentSymbol, PERIOD_CURRENT, 0);
    long volumeMA = 0;
    for(int i = 0; i < volumePeriod; i++) {
        volumeMA += iVolume(m_currentSymbol, PERIOD_CURRENT, i);
    }
    double volumeRatio = (double)currentVolume / ((double)volumeMA / volumePeriod);

    // Trend Strength Analysis
    double fastMA = iMA(m_currentSymbol, PERIOD_CURRENT, trendFastMA, 0, MODE_EMA, PRICE_CLOSE, 0);
    double slowMA = iMA(m_currentSymbol, PERIOD_CURRENT, trendSlowMA, 0, MODE_EMA, PRICE_CLOSE, 0);
    double trendStrength = MathAbs((fastMA - slowMA) / slowMA) * 100;

    // ADX Analysis
    double adx = iADX(m_currentSymbol, PERIOD_CURRENT, adxPeriod, PRICE_CLOSE, MODE_MAIN, 0);

    Logger.Debug(StringFormat(
        "Market Conditions (%s):" +
        "\nVolume Ratio: %.2f (Min: %.2f)" +
        "\nTrend Strength: %.2f%% (Min: %.2f%%)" +
        "\nADX: %.2f (Min: %.2f)" +
        "\nInstrument Type: %s",
        m_currentSymbol,
        volumeRatio,
        minVolumeRatio,
        trendStrength,
        minTrendStrength,
        adx,
        minADX,
        isCrypto ? "Crypto" : "Forex"
    ));

    // Final Validation
    bool volumeValid = volumeRatio >= minVolumeRatio;
    bool trendValid = trendStrength >= minTrendStrength && adx >= minADX;

    // Add specific logging for rejection reasons
    if(!volumeValid) {
        Logger.Warning(StringFormat(
            "Signal rejected - Insufficient volume (%.2f < %.2f)",
            volumeRatio, minVolumeRatio));
    }
    if(trendStrength < minTrendStrength) {
        Logger.Warning(StringFormat(
            "Signal rejected - Weak trend (%.2f%% < %.2f%%)",
            trendStrength, minTrendStrength));
    }
    if(adx < minADX) {
        Logger.Warning(StringFormat(
            "Signal rejected - Low ADX (%.2f < %.2f)",
            adx, minADX));
    }

    return volumeValid && trendValid;
}

public:
    CTradeJourney() {
        m_symbolInfo = NULL;
        m_tradeManager = NULL;
        m_riskManager = NULL;
        m_sessionManager = NULL;
        m_currentSymbol = Symbol();
        m_lastDebugTime = 0; 

    // Initialize flags
    m_awaitingOppositeSignal = false;
    m_lastClosedDirection = SIGNAL_NEUTRAL;

       // Initialize timestamps
    datetime currentTime = TimeCurrent();
     // Only initialize if not already set
    if(LoadLastCheck() <= 0) {
        SaveLastCheck(currentTime);
        Logger.Info(StringFormat("[%s] Initialized LastCheck to %s", 
            m_currentSymbol, TimeToString(currentTime)));
    }
    
    if(LoadLastSignal() <= 0) {
        SaveLastSignal(currentTime);
        Logger.Info(StringFormat("[%s] Initialized LastSignal to %s", 
            m_currentSymbol, TimeToString(currentTime)));
    }
}

    ~CTradeJourney() {
        Cleanup();
    }

     void CleanupGlobalVars() {
        // Delete saved timestamps for this symbol
        string symbolPrefix = GLOBAL_VAR_PREFIX + m_currentSymbol + "_";
        GlobalVariableDel(symbolPrefix + "LAST_CHECK");
        GlobalVariableDel(symbolPrefix + "LAST_SIGNAL");
        
        Logger.Debug(StringFormat("[%s] Cleaned up global variables", m_currentSymbol));
    }

    void Cleanup() {
        if(m_symbolInfo != NULL) {
            delete m_symbolInfo;
            m_symbolInfo = NULL;
        }

        if(m_tradeManager != NULL) {
            delete m_tradeManager;
            m_tradeManager = NULL;
        }

        if(m_riskManager != NULL) {
            delete m_riskManager;
            m_riskManager = NULL;
        }

        if(m_sessionManager != NULL) {
            delete m_sessionManager;
            m_sessionManager = NULL;
        }
    }

    void ClosePosition(int ticket, string reason = "") {
    if(m_currentSymbol != Symbol()) {
        Logger.Error(StringFormat(
            "Symbol mismatch in ClosePosition - Current: %s, MT4: %s",
            m_currentSymbol, Symbol()));
        return;
    }

    if(m_tradeManager != NULL) {
        m_tradeManager.ClosePosition(ticket, reason);
    }
}

    bool Initialize() {
        // Validate symbol hasn't changed
        if(m_currentSymbol != Symbol()) {
            Logger.Error("Symbol mismatch in initialization");
            return false;
        }

        Cleanup(); // Clean up any existing instances

        // Initialize symbol info
        m_symbolInfo = new CSymbolInfo(m_currentSymbol);
        if(m_symbolInfo == NULL) {
            Logger.Error("Failed to initialize SymbolInfo for " + m_currentSymbol);
            return false;
        }

        // Initialize risk manager
        m_riskManager = new CRiskManager(m_symbolInfo, RISK_PERCENT, MAX_ACCOUNT_RISK, MARGIN_BUFFER);
        if(m_riskManager == NULL) {
            Logger.Error("Failed to initialize RiskManager for " + m_currentSymbol);
            return false;
        }

        // Initialize trade manager
        m_tradeManager = new CTradeManager(m_symbolInfo, m_riskManager, DEFAULT_SLIPPAGE, MAX_RETRY_ATTEMPTS);
        if(m_tradeManager == NULL) {
            Logger.Error("Failed to initialize TradeManager for " + m_currentSymbol);
            return false;
        }

        // Initialize session manager
        m_sessionManager = new CSessionManager(m_symbolInfo,
                                           TRADE_ASIAN_SESSION,
                                           TRADE_LONDON_SESSION,
                                           TRADE_NEWYORK_SESSION,
                                           ALLOW_SESSION_OVERLAP);
        if(m_sessionManager == NULL) {
            Logger.Error("Failed to initialize SessionManager for " + m_currentSymbol);
            return false;
        }

        Logger.Info(StringFormat(
            "EA Initialized for %s with:" +
            "\nRisk: %.2f%%" +
            "\nMargin Buffer: %.2f%%" +
            "\nMax Account Risk: %.2f%%" +
            "\nProfit Protection: %s",
            m_currentSymbol,
            RISK_PERCENT,
            MARGIN_BUFFER,
            MAX_ACCOUNT_RISK        ));
        return true;
    }

    void OnTick() {
        // Symbol validation
        if(m_currentSymbol != Symbol()) {
            Logger.Error("Symbol mismatch in OnTick");
            return;
        }

        // Skip if managers aren't initialized
        if(m_symbolInfo == NULL || m_tradeManager == NULL ||
           m_riskManager == NULL || m_sessionManager == NULL) {
            return;
        }

        // Check if trading is allowed
        if(!m_tradeManager.CanTrade()) {
            static datetime lastWarning = 0;
            if(TimeCurrent() - lastWarning >= 300) {
                lastWarning = TimeCurrent();
            }
            return;
        }

        // Check market session
        if(!m_sessionManager.IsMarketOpen()) {
            return;
        }

        PerformPeriodicChecks();

        if(IsTimeToCheck()) {
            ProcessSignals();
        }

        // if(ENABLE_PROFIT_PROTECTION) {
        //     static datetime lastCheck = 0;
        //     if(TimeCurrent() - lastCheck >= PROFIT_CHECK_INTERVAL) {
        //         m_tradeManager.MonitorPositions();
        //         lastCheck = TimeCurrent();
        //     }
        // }

        m_tradeManager.MonitorPositions();
      }

void ProcessSignals() {
    if(m_currentSymbol != Symbol()) return;

    // Log current trading state before processing new signals
    Logger.Info(StringFormat(
        "CURRENT TRADING STATE" +
        "\n--------------------" +
        "\nSymbol: %s" +
        "\nTime: %s" +
        "\nAwaiting Opposite Signal: %s" +
        "\nLast Trade Direction: %s" +
        "\nAllowed Next Direction: %s",
        m_currentSymbol,
        TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
        m_awaitingOppositeSignal ? "YES" : "NO",
        m_lastClosedDirection == SIGNAL_BUY ? "BUY" : 
            m_lastClosedDirection == SIGNAL_SELL ? "SELL" : "NONE",
        m_awaitingOppositeSignal ? 
            (m_lastClosedDirection == SIGNAL_BUY ? "SELL ONLY" : "BUY ONLY") : 
            "ANY DIRECTION"
    ));

    string response = FetchSignals();
    if(response == "") return;

    SignalData signal;
    Logger.Info("Starting signal processing...");
    
    if(ParseSignal(response, signal)) {
        Logger.Info(StringFormat(
            "NEW SIGNAL RECEIVED" +
            "\n--------------------" +
            "\nSymbol: %s" +
            "\nSignal Type: %s" +
            "\nPrice: %.5f" +
            "\nPattern: %s" +
            "\nIs Exit: %s" +
            "\nExit Type: %s" +
            "\nSL2: %.5f" +
            "\nTP1: %.5f" +
            "\nTP2: %.5f" +
            "\nTimestamp: %s",
            signal.ticker,
            signal.signal == SIGNAL_BUY ? "BUY" : 
                signal.signal == SIGNAL_SELL ? "SELL" : "NEUTRAL",
            signal.price,
            signal.pattern,
            signal.isExit ? "YES" : "NO",
            signal.isExit ? (signal.exitType == EXIT_BULLISH ? "BULLISH" : "BEARISH") : "N/A",
            signal.sl2,
            signal.tp1,
            signal.tp2,
            TimeToString(signal.timestamp, TIME_DATE|TIME_SECONDS)
        ));

        if(ValidateSignal(signal)) {
            signal.instrumentType = m_symbolInfo.IsCryptoPair() ?
                INSTRUMENT_CRYPTO : INSTRUMENT_FOREX;
                
            // Handle exit signals first - NO market condition validation
            if(signal.isExit) {
                Logger.Info(StringFormat(
                    "PROCESSING EXIT SIGNAL" +
                    "\n--------------------" +
                    "\nSymbol: %s" +
                    "\nExit Type: %s" +
                    "\nPrice: %.5f" +
                    "\nTP1: %.5f" +
                    "\nPattern: %s" +
                    "\nCurrent Direction: %s" +
                    "\nAwaiting Opposite: %s",
                    signal.ticker,
                    signal.exitType == EXIT_BULLISH ? "BULLISH" : "BEARISH",
                    signal.price,
                    signal.tp1,
                    signal.pattern,
                    m_lastClosedDirection == SIGNAL_BUY ? "BUY" : 
                        m_lastClosedDirection == SIGNAL_SELL ? "SELL" : "NONE",
                    m_awaitingOppositeSignal ? "YES" : "NO"
                ));

                if(signal.tp1 <= 0) {
                    Logger.Warning(StringFormat(
                        "Exit signal has no valid TP1 - Using price: %.5f",
                        signal.price
                    ));
                    signal.tp1 = signal.price;
                }

                if(m_tradeManager != NULL) {
                    m_tradeManager.ProcessExitSignal(signal);
                } else {
                    Logger.Error("Trade manager is NULL - cannot process exit signal");
                }
            } else {
                // For non-exit signals, first check if we need to close opposite positions
                if(m_tradeManager != NULL && m_tradeManager.HasOpenPosition()) {
                    ENUM_TRADE_SIGNAL currentDirection = SIGNAL_NEUTRAL;
                    
                    // Check current position direction using TradeManager's methods
                    if(m_tradeManager.HasOpenPositionInDirection(SIGNAL_BUY)) {
                        currentDirection = SIGNAL_BUY;
                    } else if(m_tradeManager.HasOpenPositionInDirection(SIGNAL_SELL)) {
                        currentDirection = SIGNAL_SELL;
                    }

                    bool isOppositeSignal = (currentDirection == SIGNAL_BUY && signal.signal == SIGNAL_SELL) ||
                                        (currentDirection == SIGNAL_SELL && signal.signal == SIGNAL_BUY);
                    
                    if(isOppositeSignal) {
                        Logger.Info(StringFormat(
                            "CLOSING OPPOSITE POSITION" +
                            "\n--------------------" +
                            "\nCurrent Direction: %s" +
                            "\nNew Signal: %s",
                            currentDirection == SIGNAL_BUY ? "BUY" : "SELL",
                            signal.signal == SIGNAL_BUY ? "BUY" : "SELL"
                        ));
                        
                        m_tradeManager.CloseExistingPositions(signal.signal);
                    }
                }

                // Only validate market conditions for new position opening
                if(!ValidateMarketConditions()) {
                    Logger.Info("Market conditions not valid for new position - skipping entry");
                    return;
                }

                // Entry signal processing
                string allowedDirection = m_awaitingOppositeSignal ? 
                    (m_lastClosedDirection == SIGNAL_BUY ? "SELL ONLY" : "BUY ONLY") : 
                    "ANY DIRECTION";

                Logger.Info(StringFormat(
                    "PROCESSING ENTRY SIGNAL" +
                    "\n--------------------" +
                    "\nSymbol: %s" +
                    "\nDirection: %s" +
                    "\nPrice: %.5f" +
                    "\nTP1: %.5f" +
                    "\nSL2: %.5f" +
                    "\nTP2: %.5f" +
                    "\nAllowed Direction: %s" +
                    "\nAwaiting Opposite: %s" +
                    "\nLast Direction: %s",
                    signal.ticker,
                    signal.signal == SIGNAL_BUY ? "BUY" : "SELL",
                    signal.price,
                    signal.tp1,
                    signal.sl2,
                    signal.tp2,
                    allowedDirection,
                    m_awaitingOppositeSignal ? "YES" : "NO",
                    m_lastClosedDirection == SIGNAL_BUY ? "BUY" : 
                        m_lastClosedDirection == SIGNAL_SELL ? "SELL" : "NONE"
                ));

                // Validate if signal matches allowed direction
                if(m_awaitingOppositeSignal) {
                    if((m_lastClosedDirection == SIGNAL_BUY && signal.signal == SIGNAL_SELL) ||
                       (m_lastClosedDirection == SIGNAL_SELL && signal.signal == SIGNAL_BUY)) {
                        Logger.Info("Signal matches required opposite direction - Executing");
                        ExecuteSignal(signal);
                    } else {
                        Logger.Warning(StringFormat(
                            "Signal rejected - Waiting for %s signal after %s position",
                            m_lastClosedDirection == SIGNAL_BUY ? "SELL" : "BUY",
                            m_lastClosedDirection == SIGNAL_BUY ? "BUY" : "SELL"
                        ));
                    }
                } else {
                    Logger.Info("No direction restrictions - Executing signal");
                    ExecuteSignal(signal);
                }
            }
        } else {
            Logger.Warning(StringFormat(
                "SIGNAL VALIDATION FAILED" +
                "\n--------------------" +
                "\nSymbol: %s" +
                "\nTimestamp: %s" +
                "\nLast Signal Time: %s" +
                "\nAwaiting Opposite: %s" +
                "\nLast Direction: %s",
                signal.ticker,
                TimeToString(signal.timestamp),
                TimeToString(m_lastSignalTimestamp),
                m_awaitingOppositeSignal ? "YES" : "NO",
                m_lastClosedDirection == SIGNAL_BUY ? "BUY" : 
                    m_lastClosedDirection == SIGNAL_SELL ? "SELL" : "NONE"
            ));
        }
    } else {
        Logger.Warning("Failed to parse signal from response");
    }
}

private:

    // Add these helper functions
    void SaveLastCheck(datetime time) {
    string varName = GLOBAL_VAR_PREFIX + m_currentSymbol + "_LAST_CHECK";
    GlobalVariableSet(varName, (double)time);
    m_lastCheck = time;
    Logger.Debug(StringFormat("[%s] Saved LastCheck: %s", 
        m_currentSymbol, TimeToString(time)));
}

void SaveLastSignal(datetime time) {
    string varName = GLOBAL_VAR_PREFIX + m_currentSymbol + "_LAST_SIGNAL";
    GlobalVariableSet(varName, (double)time);
    m_lastSignalTimestamp = time;
    Logger.Debug(StringFormat("[%s] Saved LastSignal: %s", 
        m_currentSymbol, TimeToString(time)));
}

datetime LoadLastCheck() {
    string varName = GLOBAL_VAR_PREFIX + m_currentSymbol + "_LAST_CHECK";
    if(GlobalVariableCheck(varName)) {
        datetime time = (datetime)GlobalVariableGet(varName);
        static datetime lastDebugOutput = 0;
        datetime currentTime = TimeCurrent();
        
        // Only log every 60 seconds
        if(currentTime - lastDebugOutput >= 60) {
            Logger.Debug(StringFormat("[%s] Loaded LastCheck: %s", 
                m_currentSymbol, TimeToString(time)));
            lastDebugOutput = currentTime;
        }
        return time;
    }
    return 0;
}

datetime LoadLastSignal() {
    string varName = GLOBAL_VAR_PREFIX + m_currentSymbol + "_LAST_SIGNAL";
    if(GlobalVariableCheck(varName)) {
        return (datetime)GlobalVariableGet(varName);
    }
    return 0;  // No logging for simple loads
}

void ExecuteSignal(const SignalData& signal) {
    if(m_currentSymbol != Symbol() || m_currentSymbol != signal.ticker) {
        Logger.Error(StringFormat(
            "Symbol mismatch in ExecuteSignal - Current: %s, Signal: %s, MT4: %s",
            m_currentSymbol, signal.ticker, Symbol()));
        return;
    }

    string signalDirection;
    switch(signal.signal) {
        case SIGNAL_BUY:
            signalDirection = "BUY";
            Logger.Debug("Signal validated as BUY");
            break;
        case SIGNAL_SELL:
            signalDirection = "SELL";
            Logger.Debug("Signal validated as SELL");
            break;
        default:
            signalDirection = "NEUTRAL";
            Logger.Debug("Signal defaulted to NEUTRAL");
            break;
    }

    Logger.Debug(StringFormat("Signal details - Enum value: %d, Direction: %s, Price: %.5f",
                 signal.signal, signalDirection, signal.price));

    int orderType = (signal.signal == SIGNAL_BUY) ? OP_BUY : OP_SELL;
    double stopLoss;

    // Determine stop loss based on order type
    if(orderType == OP_BUY) {
        // For BUY positions, use sl2 as stop loss
        if(signal.sl2 > 0) {
            stopLoss = signal.sl2;
            Logger.Debug(StringFormat("BUY Position: Using SL2 for stop loss: %.5f", stopLoss));
            
            // Validate SL2 is below entry for BUY
            if(stopLoss >= signal.price) {
                Logger.Error(StringFormat(
                    "Invalid BUY stop loss (SL2) - Must be below entry price:" +
                    "\nEntry: %.5f" +
                    "\nStop Loss (SL2): %.5f",
                    signal.price, stopLoss));
                return;
            }
        } else {
            Logger.Error("BUY Signal missing SL2 value for stop loss");
            return;
        }
    } else {
        // For SELL positions, use sl2 as stop loss
        if(signal.sl2 > 0) {
            stopLoss = signal.sl2;
            Logger.Debug(StringFormat("SELL Position: Using SL2 for stop loss: %.5f", stopLoss));
            
            // Validate SL2 is above entry for SELL
            if(stopLoss <= signal.price) {
                Logger.Error(StringFormat(
                    "Invalid SELL stop loss (SL2) - Must be above entry price:" +
                    "\nEntry: %.5f" +
                    "\nStop Loss (SL2): %.5f",
                    signal.price, stopLoss));
                return;
            }
        } else {
            Logger.Error("SELL Signal missing SL2 value for stop loss");
            return;
        }
    }

    // Validate final stop loss value
    if(stopLoss <= 0) {
        Logger.Error(StringFormat("Invalid stop loss value: %.5f", stopLoss));
        return;
    }

    // Set risk percent based on instrument type
    double riskPercent = m_symbolInfo.IsCryptoPair() ?
        CRYPTO_STOP_PERCENT : DEFAULT_RISK_PERCENT;
    m_riskManager.SetRiskPercent(riskPercent);
    Logger.Debug(StringFormat("Using Risk Percent: %.2f%%", riskPercent));

    // Calculate position size
    double lots = m_riskManager.CalculatePositionSize(signal.price, stopLoss, orderType);
    Logger.Debug(StringFormat("Calculated Position Size: %.2f lots", lots));

    if(lots <= 0) {
        Logger.Error(StringFormat("Invalid position size calculated: %.2f", lots));
        return;
    }

    // Prepare trade comment
    string tradeComment = StringFormat("TJ:%s:%s", signalDirection, signal.pattern);
    tradeComment = StringSubstr(tradeComment, 0, 31);
    Logger.Debug(StringFormat("Trade comment prepared: '%s'", tradeComment));

    bool success = false;
    switch(signal.signal) {
        case SIGNAL_BUY:
            Logger.Debug(StringFormat(
                "Executing BUY order:" +
                "\nLots: %.2f" +
                "\nEntry: %.5f" +
                "\nStop Loss (SL2): %.5f" +
                "\nTake Profit: %.5f", 
                lots, signal.price, stopLoss, signal.tp1));
            success = m_tradeManager.OpenBuyPosition(lots, stopLoss, signal.tp1, tradeComment, signal);
            break;

        case SIGNAL_SELL:
            Logger.Debug(StringFormat(
                "Executing SELL order:" +
                "\nLots: %.2f" +
                "\nEntry: %.5f" +
                "\nStop Loss (TP2): %.5f" +
                "\nTake Profit: %.5f", 
                lots, signal.price, stopLoss, signal.tp1));
            success = m_tradeManager.OpenSellPosition(lots, stopLoss, signal.tp1, tradeComment, signal);
            break;

        default:
            Logger.Warning(StringFormat("Invalid signal type (%d) - No trade executed", signal.signal));
            return;
    }

    if(success) {
        m_lastSignalTimestamp = signal.timestamp;
        Logger.Trade(StringFormat(
            "Position successfully executed:" +
            "\nDirection: %s" +
            "\nLots: %.2f" +
            "\nEntry: %.5f" +
            "\nStop Loss: %.5f" +
            "\nTake Profit: %.5f" +
            "\nPattern: %s",
            signalDirection,
            lots,
            signal.price,
            stopLoss,
            signal.tp1,
            signal.pattern
        ));
    }
}

    string FetchSignals() {
        if(m_currentSymbol != Symbol()) {
            Logger.Error(StringFormat(
                "Symbol mismatch in FetchSignals - Current: %s, MT4: %s",
                m_currentSymbol, Symbol()));
            return "";
        }

        string symbolBase = m_currentSymbol;
        if(StringFind(symbolBase, "+") >= 0) {
            symbolBase = StringSubstr(symbolBase, 0, StringFind(symbolBase, "+"));
        }

        string url = StringFormat("%s?pairs=%s&tf=%s",
                                API_URL,
                                symbolBase,
                                TIMEFRAME);

        Logger.Debug(StringFormat("Fetching signals from URL: %s", url));

        string headers = "Content-Type: application/json\r\n";
        char post[];
        char result[];
        string resultHeaders;

        ResetLastError();
        int res = WebRequest(
            "GET",
            url,
            headers,
            API_TIMEOUT,
            post,
            result,
            resultHeaders
        );

        if(res == -1) {
            int error = GetLastError();
            if(error == 4060) {
                Logger.Error("Add URL to: Tools -> Options -> Expert Advisors -> Allow WebRequest");
                Logger.Error("URL to allow: " + url);
            } else {
                Logger.Error(StringFormat("Failed to fetch signals. Error: %d", error));
            }
            return "";
        }

        string response = CharArrayToString(result);
        Logger.Debug("API Response: " + response);

        if(StringLen(response) == 0) {
            Logger.Debug("No signals received");
            return "";
        }

        return response;
    }

//+------------------------------------------------------------------+
//| Parse signal from API response                                     |
//+------------------------------------------------------------------+

string ConvertToUpper(string text) {
    string result = text;
    StringToUpper(result);  // This modifies the string in place
    return result;
}

bool ParseSignal(string response, SignalData &signal) {
    // Initialize default values
    signal.signal = SIGNAL_NEUTRAL;
    signal.price = 0;
    signal.ticker = "";
    signal.pattern = "";
    signal.isExit = false;       
    signal.exitType = EXIT_NONE;   
    signal.tp1 = 0;

    string signalStr = response;
    
    // Remove array brackets if present
    if(StringGetCharacter(response, 0) == '[') {
        signalStr = StringSubstr(response, 1, StringLen(response) - 2);
    }
    
    Logger.Debug("Processing signal string: " + signalStr);

    // First check isExit in JSON
    string isExitSearch = "\"isExit\":";
    int isExitPos = StringFind(signalStr, isExitSearch);
    if(isExitPos != -1) {
        string isExitValue = StringSubstr(signalStr, 
            isExitPos + StringLen(isExitSearch), 
            5);  // Enough chars for "true" or "false"
        signal.isExit = (StringFind(isExitValue, "true") >= 0);
        
        if(signal.isExit) {
            // Check exitType
            string exitTypeSearch = "\"exitType\":\"";
            int exitTypePos = StringFind(signalStr, exitTypeSearch);
            if(exitTypePos != -1) {
                int startQuote = exitTypePos + StringLen(exitTypeSearch);
                int endQuote = StringFind(signalStr, "\"", startQuote);
                if(endQuote != -1) {
                    string exitTypeStr = StringSubstr(signalStr, startQuote, endQuote - startQuote);
                    if(StringCompare(exitTypeStr, "bullish", false) == 0) {
                        signal.exitType = EXIT_BULLISH;
                    }
                    else if(StringCompare(exitTypeStr, "bearish", false) == 0) {
                        signal.exitType = EXIT_BEARISH;
                    }
                }
            }
        }
    }

    // Extract sl2
    string sl2Search = "\"sl2\":";
    int sl2Pos = StringFind(signalStr, sl2Search);
    if(sl2Pos != -1) {
        int startValue = sl2Pos + StringLen(sl2Search);
        int endValue = StringFind(signalStr, ",", startValue);
        if(endValue != -1) {
            string sl2Str = StringSubstr(signalStr, startValue, endValue - startValue);
            StringReplace(sl2Str, "\"", ""); // Remove quotes if present
            signal.sl2 = StringToDouble(sl2Str);
            Logger.Debug(StringFormat("Extracted SL2: %.5f", signal.sl2));
        }
    }

    // Extract TP2 from JSON
    string tp2Search = "\"tp2\":";
    int tp2Pos = StringFind(signalStr, tp2Search);
    if(tp2Pos != -1) {
        int startValue = tp2Pos + StringLen(tp2Search);
        int endValue = StringFind(signalStr, ",", startValue);
        if(endValue != -1) {
            string tp2Str = StringSubstr(signalStr, startValue, endValue - startValue);
            StringReplace(tp2Str, "\"", ""); // Remove quotes if present
            signal.tp2 = StringToDouble(tp2Str);
            Logger.Debug(StringFormat("Extracted TP2: %.5f", signal.tp2));
        }
    }

    // Extract TP1 from JSON
    string tp1Search = "\"tp1\":";
    int tp1Pos = StringFind(signalStr, tp1Search);
    if(tp1Pos != -1) {
        int startValue = tp1Pos + StringLen(tp1Search);
        int endValue = StringFind(signalStr, ",", startValue);
        if(endValue != -1) {
            string tp1Str = StringSubstr(signalStr, startValue, endValue - startValue);
            StringReplace(tp1Str, "\"", ""); // Remove quotes if present
            signal.tp1 = StringToDouble(tp1Str);
            Logger.Debug(StringFormat("Extracted TP1: %.5f", signal.tp1));
        }
    }

    // Extract price and pattern first (needed for exit signals)
    string priceSearch = "\"price\":";
    int pricePos = StringFind(signalStr, priceSearch);
    if(pricePos != -1) {
        int startPrice = pricePos + StringLen(priceSearch);
        int endPrice = StringFind(signalStr, ",", startPrice);
        if(endPrice != -1) {
            string priceStr = StringSubstr(signalStr, startPrice, endPrice - startPrice);
            signal.price = StringToDouble(priceStr);
            Logger.Debug(StringFormat("Extracted price: %.5f", signal.price));
        }
    }

    // Extract pattern and check for exit signals
    string patternSearch = "\"signalPattern\":\"";
    int patternPos = StringFind(signalStr, patternSearch);
    if(patternPos != -1) {
        int startQuote = patternPos + StringLen(patternSearch);
        int endQuote = StringFind(signalStr, "\"", startQuote);
        if(endQuote != -1) {
            signal.pattern = StringSubstr(signalStr, startQuote, endQuote - startQuote);
            
            // Verify exit signals in pattern
            if(StringFind(signal.pattern, "ExitsBullish Exit") >= 0 || 
               StringFind(signal.pattern, "Exits Bullish Exit") >= 0) {
                signal.isExit = true;
                signal.exitType = EXIT_BULLISH;
                
                // Only set TP1 if not already set
                if(signal.tp1 == 0) {
                    signal.tp1 = signal.price;
                }
                
                Logger.Info(StringFormat(
                    "Bullish Exit Signal:" +
                    "\nPrice: %.5f" +
                    "\nTP1: %.5f" +
                    "\nPattern: %s",
                    signal.price,
                    signal.tp1,
                    signal.pattern
                ));
            }
            else if(StringFind(signal.pattern, "ExitsBearish Exit") >= 0 || 
                    StringFind(signal.pattern, "Exits Bearish Exit") >= 0) {
                signal.isExit = true;
                signal.exitType = EXIT_BEARISH;
                
                // Only set TP1 if not already set
                if(signal.tp1 == 0) {
                    signal.tp1 = signal.price;
                }
                
                Logger.Info(StringFormat(
                    "Bearish Exit Signal:" +
                    "\nPrice: %.5f" +
                    "\nTP1: %.5f" +
                    "\nPattern: %s",
                    signal.price,
                    signal.tp1,
                    signal.pattern
                ));
            }
        }
    }

    // Extract ticker
    string tickerSearch = "\"ticker\":\"";
    int tickerPos = StringFind(signalStr, tickerSearch);
    if(tickerPos != -1) {
        int startQuote = tickerPos + StringLen(tickerSearch);
        int endQuote = StringFind(signalStr, "\"", startQuote);
        if(endQuote != -1) {
            string baseTicker = StringSubstr(signalStr, startQuote, endQuote - startQuote);
            signal.ticker = (StringFind(baseTicker, "BTC") >= 0 || 
                           StringFind(baseTicker, "ETH") >= 0 ||
                           StringFind(baseTicker, "LTC") >= 0) ? 
                           baseTicker : baseTicker + "+";
        }
    }

    // Extract action
    string actionSearch = "\"action\":\"";
    int actionPos = StringFind(signalStr, actionSearch);
    if(actionPos != -1) {
        int startQuote = actionPos + StringLen(actionSearch);
        int endQuote = StringFind(signalStr, "\"", startQuote);
        if(endQuote != -1) {
            string actionValue = StringSubstr(signalStr, startQuote, endQuote - startQuote);
            if(StringCompare(actionValue, "BUY") == 0) {
                signal.signal = SIGNAL_BUY;
            }
            else if(StringCompare(actionValue, "SELL") == 0) {
                signal.signal = SIGNAL_SELL;
            }
        }
    }

    // Parse timestamp
    string timestampSearch = "\"timestamp\":\"";
    int timestampPos = StringFind(signalStr, timestampSearch);
    if(timestampPos != -1) {
        int startQuote = timestampPos + StringLen(timestampSearch);
        int endQuote = StringFind(signalStr, "\"", startQuote);
        if(endQuote != -1) {
            string timestampStr = StringSubstr(signalStr, startQuote, endQuote - startQuote);
            bool parseSuccess = false;
            signal.timestamp = ParseTimestamp(timestampStr, parseSuccess);
            
            if(!parseSuccess) {
                Logger.Error("Failed to parse timestamp: " + timestampStr);
                return false;
            }
        }
    }

    // Comprehensive logging of final signal state
    Logger.Info(StringFormat(
        "Signal parsing complete:" +
        "\nTicker: %s" +
        "\nIs Exit: %s" +
        "\nExit Type: %s" +
        "\nSignal Type: %s" +
        "\nPrice: %.5f" +
        "\nTP1: %.5f" +
        "\nSL2: %.5f" +
        "\nPattern: %s",
        signal.ticker,
        signal.isExit ? "Yes" : "No",
        signal.isExit ? (signal.exitType == EXIT_BULLISH ? "BULLISH" : "BEARISH") : "N/A",
        signal.signal == SIGNAL_BUY ? "BUY" : 
            signal.signal == SIGNAL_SELL ? "SELL" : "NEUTRAL",
        signal.price,
        signal.tp1,
        signal.sl2,
        signal.pattern
    ));

    // Validate the signal with exit consideration
    bool validSignal = (
        StringLen(signal.ticker) > 0 && 
        signal.price > 0 && 
        (signal.isExit || signal.signal != SIGNAL_NEUTRAL) &&  // Allow exit signals
        StringLen(signal.pattern) > 0 &&
        (signal.isExit ? signal.tp1 > 0 : true)  // Require TP1 for exit signals
    );

    return validSignal;
}

//+------------------------------------------------------------------+
//| Parse timestamp string to datetime                                 |
//+------------------------------------------------------------------+
datetime ParseTimestamp(string rawTimestamp, bool &success) {
    success = false;
    string timestampStr = rawTimestamp;
    
    // Clean the timestamp string
    StringReplace(timestampStr, "\"", ""); // Remove quotes
    timestampStr = StringTrimRight(StringTrimLeft(timestampStr));
    
    Logger.Debug("Parsing timestamp: " + timestampStr);
    
    // Extract date components
    int month = (int)StringToInteger(StringSubstr(timestampStr, 0, 2));
    int day = (int)StringToInteger(StringSubstr(timestampStr, 3, 2));
    int year = (int)StringToInteger(StringSubstr(timestampStr, 6, 4));
    
    // Extract time components
    int hour = (int)StringToInteger(StringSubstr(timestampStr, 11, 2));
    int minute = (int)StringToInteger(StringSubstr(timestampStr, 14, 2));
    int second = (int)StringToInteger(StringSubstr(timestampStr, 17, 2));
    
    // Handle AM/PM
    bool isPM = StringFind(timestampStr, "PM") >= 0;
    if(isPM && hour < 12) hour += 12;
    
    Logger.Debug(StringFormat(
        "Timestamp components: Y:%d M:%d D:%d H:%d M:%d S:%d PM:%s",
        year, month, day, hour, minute, second,
        isPM ? "Yes" : "No"
    ));
    
    // Create datetime string in MT4 format (YYYY.MM.DD HH:MM:SS)
    string formattedDateTime = StringFormat(
        "%04d.%02d.%02d %02d:%02d:%02d",
        year, month, day, hour, minute, second
    );
    
    // Convert to datetime
    datetime result = StringToTime(formattedDateTime);
    
    if(result > 0) {
        success = true;
        Logger.Debug(StringFormat(
            "Successfully parsed timestamp: %s -> %s",
            timestampStr,
            TimeToString(result, TIME_DATE|TIME_MINUTES|TIME_SECONDS)
        ));
    } else {
        Logger.Error(StringFormat(
            "Failed to parse timestamp: %s -> %s",
            timestampStr,
            formattedDateTime
        ));
    }
    
    return result;
}

bool ValidateSignal(const SignalData& signal) {
    Logger.Info(StringFormat(
        "Validating signal:" +
        "\nCurrent Symbol: %s" +
        "\nSignal Symbol: %s" +
        "\nMT4 Symbol: %s" +
        "\nSignal Timestamp: %s" +
        "\nLast Signal Time: %s" +
        "\nSignal Price: %.5f" +
        "\nIs Exit: %s",
        m_currentSymbol,
        signal.ticker,
        Symbol(),
        TimeToString(signal.timestamp),
        TimeToString(m_lastSignalTimestamp),
        signal.price,
        signal.isExit ? "Yes" : "No"
    ));

    if(m_currentSymbol != Symbol() || m_currentSymbol != signal.ticker) {
        Logger.Error(StringFormat(
            "Symbol mismatch in ValidateSignal - Current: %s, Signal: %s, MT4: %s",
            m_currentSymbol, signal.ticker, Symbol()));
        return false;
    }

    if(signal.timestamp == m_lastSignalTimestamp || signal.timestamp == 0) {
        Logger.Debug(StringFormat(
            "Signal timestamp validation failed:" +
            "\nSignal Time: %s" +
            "\nLast Signal: %s",
            TimeToString(signal.timestamp),
            TimeToString(m_lastSignalTimestamp)
        ));
        return false;
    }

    if(signal.price <= 0) {
        Logger.Error(StringFormat(
            "Invalid signal price: %.5f",
            signal.price));
        return false;
    }

    // For exit signals, validate TP values
    if(signal.isExit) {
        Logger.Info(StringFormat(
            "Validating exit signal values:" +
            "\nExit Type: %s" +
            "\nPrice: %.5f" +
            "\nTP1: %.5f",
            signal.exitType == EXIT_BULLISH ? "BULLISH" : "BEARISH",
            signal.price,
            signal.tp1
        ));
        
        // Make sure TP is set for exit signals
        if(signal.tp1 <= 0) {
            Logger.Error("Exit signal has invalid TP1 value");
            return false;
        }
    }

    Logger.Info("Signal validation passed");
    return true;
}

    void CloseAllPositions(string reason) {
        if(m_currentSymbol != Symbol()) {
            Logger.Error(StringFormat(
                "Symbol mismatch in CloseAllPositions - Current: %s, MT4: %s",
                m_currentSymbol, Symbol()));
            return;
        }

        for(int i = OrdersTotal() - 1; i >= 0; i--) {
            if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
                if(OrderSymbol() == m_currentSymbol) {
                    m_tradeManager.ClosePosition(OrderTicket(), reason);
                }
            }
        }
    }

    void MonitorPositions() {
        if(m_currentSymbol != Symbol()) {
            Logger.Error(StringFormat(
                "Symbol mismatch in MonitorPositions - Current: %s, MT4: %s",
                m_currentSymbol, Symbol()));
            return;
        }

        PositionMetrics metrics = m_tradeManager.GetPositionMetrics();

        if(metrics.totalPositions > 0) {
           // if(ENABLE_PROFIT_PROTECTION) {CheckProfitProtection(metrics);}

            Logger.Debug(StringFormat(
                "Position Status:" +
                "\nTotal Positions: %d" +
                "\nTotal Volume: %.2f" +
                "\nUnrealized P/L: %.2f",
                metrics.totalPositions,
                metrics.totalVolume,
                metrics.unrealizedPL
            ));
        }
    }
};