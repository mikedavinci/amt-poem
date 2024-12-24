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

    // Moving periodic checks to private method
    void PerformPeriodicChecks() {
        if(m_currentSymbol != Symbol()) return;  // Symbol validation
        
        static datetime lastCheck = 0;
        datetime currentTime = TimeCurrent();

        if(currentTime - lastCheck >= RISK_CHECK_INTERVAL) {
            if(!m_riskManager.IsMarginSafe()) {
                Logger.Warning("Margin level below safe threshold for " + m_currentSymbol);
            }

            string liquidity = m_sessionManager.GetLiquidityLevel();
            lastCheck = currentTime;
        }
    }

    bool IsTimeToCheck() {
        static datetime lastSignalCheck = 0;
        datetime currentTime = TimeCurrent();

        if(currentTime - lastSignalCheck < SIGNAL_CHECK_INTERVAL) {
            return false;
        }

        lastSignalCheck = currentTime;
        return true;
    }

public:
    CTradeJourney() {
        m_symbolInfo = NULL;
        m_tradeManager = NULL;
        m_riskManager = NULL;
        m_sessionManager = NULL;
        m_lastCheck = 0;
        m_lastSignalTimestamp = 0;
        m_currentSymbol = Symbol();
    }

    ~CTradeJourney() {
        Cleanup();
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
            MAX_ACCOUNT_RISK,
            ENABLE_PROFIT_PROTECTION ? "Enabled" : "Disabled"
        ));

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

        if(ENABLE_PROFIT_PROTECTION) {
            static datetime lastCheck = 0;
            if(TimeCurrent() - lastCheck >= PROFIT_CHECK_INTERVAL) {
                m_tradeManager.MonitorPositions();
                lastCheck = TimeCurrent();
            }
        }
    }

    void ProcessSignals() {
    if(m_currentSymbol != Symbol()) return;

    string response = FetchSignals();
    if(response == "") return;

    SignalData signal;
    if(ParseSignal(response, signal)) {
        if(ValidateSignal(signal)) {
            // Handle exit signals first
            if(signal.isExit) {
                m_tradeManager.ProcessExitSignal(signal);
            } else {
                // Regular signal processing
                signal.instrumentType = m_symbolInfo.IsCryptoPair() ?
                    INSTRUMENT_CRYPTO : INSTRUMENT_FOREX;
                ExecuteSignal(signal);
            }
        }
    }
}

private:
    void ProcessExitSignal(const SignalData& signal) {
        if(m_currentSymbol != Symbol() || m_currentSymbol != signal.ticker) {
            Logger.Error(StringFormat(
                "Symbol mismatch in ProcessExitSignal - Current: %s, Signal: %s, MT4: %s",
                m_currentSymbol, signal.ticker, Symbol()));
            return;
        }

        for(int i = OrdersTotal() - 1; i >= 0; i--) {
            if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
                if(OrderSymbol() == m_currentSymbol) {
                    bool shouldClose = false;
                    
                    if(OrderType() == OP_BUY && signal.exitType == EXIT_BULLISH) {
                    Logger.Debug(StringFormat(
                        "Closing BUY position at TP: %.5f (Bullish Exit)",
                        signal.price));
                    ClosePosition(OrderTicket(), "Exit Signal: Bullish");
                    }
                    else if(OrderType() == OP_SELL && signal.exitType == EXIT_BEARISH) {
                    Logger.Debug(StringFormat(
                        "Closing SELL position at TP: %.5f (Bearish Exit)",
                        signal.price));
                    ClosePosition(OrderTicket(), "Exit Signal: Bearish");
                }
                    
                    if(shouldClose) {
                        m_tradeManager.ClosePosition(OrderTicket(), 
                            StringFormat("Exit Signal: %s", 
                                signal.exitType == EXIT_BEARISH ? "Bearish" : "Bullish"));
                    }
                }
            }
        }
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
        if(signal.sl2 > 0) {
            stopLoss = signal.sl2;
            Logger.Debug(StringFormat("Using SL2 from API: %.5f", stopLoss));
        } else {
            stopLoss = m_symbolInfo.CalculateStopLoss(orderType, signal.price);
            Logger.Debug(StringFormat("Using calculated Stop Loss: %.5f", stopLoss));
        }

        double riskPercent = m_symbolInfo.IsCryptoPair() ?
            CRYPTO_STOP_PERCENT : DEFAULT_RISK_PERCENT;
        m_riskManager.SetRiskPercent(riskPercent);
        Logger.Debug(StringFormat("Using Risk Percent: %.2f%%", riskPercent));

        double lots = m_riskManager.CalculatePositionSize(signal.price, stopLoss, orderType);
        Logger.Debug(StringFormat("Calculated Position Size: %.2f lots", lots));

        if(lots <= 0) {
            Logger.Error(StringFormat("Invalid position size calculated: %.2f", lots));
            return;
        }

        string tradeComment = StringFormat("TJ:%s:%s", signalDirection, signal.pattern);
        tradeComment = StringSubstr(tradeComment, 0, 31);
        Logger.Debug(StringFormat("Trade comment prepared: '%s'", tradeComment));

        bool success = false;

        switch(signal.signal) {
          case SIGNAL_BUY:
              Logger.Debug(StringFormat("Executing BUY order - Lots: %.2f, Stop Loss: %.5f, Take Profit: %.5f", 
                  lots, stopLoss, signal.tp1));
              success = m_tradeManager.OpenBuyPosition(lots, stopLoss, signal.tp1, tradeComment);
              break;

          case SIGNAL_SELL:
              Logger.Debug(StringFormat("Executing SELL order - Lots: %.2f, Stop Loss: %.5f, Take Profit: %.5f", 
                  lots, stopLoss, signal.tp1));
              success = m_tradeManager.OpenSellPosition(lots, stopLoss, signal.tp1, tradeComment);
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
                "\nPattern: %s" +
                "\nSignal Value: %d",
                signalDirection,
                lots,
                signal.price,
                stopLoss,
                signal.pattern,
                signal.signal
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

    string signalStr = response;
    
    // Remove array brackets if present
    if(StringGetCharacter(response, 0) == '[') {
        signalStr = StringSubstr(response, 1, StringLen(response) - 2);
    }
    
    Logger.Debug("Processing signal string: " + signalStr);

      // Extract sl2
    string sl2Search = "\"sl2\":";
    int sl2Pos = StringFind(signalStr, sl2Search);
    if(sl2Pos != -1) {
        int startValue = sl2Pos + StringLen(sl2Search);
        int endValue = StringFind(signalStr, ",", startValue);
        if(endValue != -1) {
            string sl2Str = StringSubstr(signalStr, startValue, endValue - startValue);
            signal.sl2 = StringToDouble(sl2Str);
            Logger.Debug(StringFormat("Extracted SL2: %.5f", signal.sl2));
        }
    }

    // Parse alert pattern and check for exit signals
    string alertSearch = "\"alert\":\"";
    int alertPos = StringFind(signalStr, alertSearch);
    if(alertPos != -1) {
        int startQuote = alertPos + StringLen(alertSearch);
        int endQuote = StringFind(signalStr, "\"", startQuote);
        if(endQuote != -1) {
            string alertValue = StringSubstr(signalStr, startQuote, endQuote - startQuote);
            
            // Check for exit signals
            if(StringFind(alertValue, "ExitsBearish Exit") >= 0) {
                signal.isExit = true;
                signal.exitType = EXIT_BEARISH;
                signal.tp1 = signal.price;  // Use current price as take profit
            }
            else if(StringFind(alertValue, "ExitsBullish Exit") >= 0) {
                signal.isExit = true;
                signal.exitType = EXIT_BULLISH;
                signal.tp1 = signal.price;  // Use current price as take profit
            }
            
            signal.pattern = alertValue;
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
          // Add + only for forex pairs, not for crypto
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
            Logger.Debug("Raw action value: " + actionValue);
            
            // Clean and compare action
            if(StringCompare(actionValue, "BUY") == 0) {
                signal.signal = SIGNAL_BUY;
                Logger.Debug("Action set to BUY");
            }
            else if(StringCompare(actionValue, "SELL") == 0) {
                signal.signal = SIGNAL_SELL;
                Logger.Debug("Action set to SELL");
            }
        }
    }

    // Extract price
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

    string timestampSearch = "\"timestamp\":\"";
    int timestampPos = StringFind(signalStr, timestampSearch);
    if(timestampPos != -1) {
        int startQuote = timestampPos + StringLen(timestampSearch);
        int endQuote = StringFind(signalStr, "\"", startQuote);
        if(endQuote != -1) {
            string timestampStr = StringSubstr(signalStr, startQuote, endQuote - startQuote);
            bool parseSuccess = false;
            signal.timestamp = ParseTimestamp(timestampStr, parseSuccess);
            Logger.Debug(StringFormat("Parsed timestamp: %s -> %s", 
                timestampStr, 
                TimeToString(signal.timestamp)));

            if(!parseSuccess) {
                Logger.Error("Failed to parse timestamp: " + timestampStr);
                return false;
            }
        }
    }

    // Extract pattern
    string patternSearch = "\"signalPattern\":\"";
    int patternPos = StringFind(signalStr, patternSearch);
    if(patternPos != -1) {
        int startQuote = patternPos + StringLen(patternSearch);
        int endQuote = StringFind(signalStr, "\"", startQuote);
        if(endQuote != -1) {
            signal.pattern = StringSubstr(signalStr, startQuote, endQuote - startQuote);
        }
    }

    // Log all extracted values
    Logger.Debug(StringFormat(
        "Final extracted values:" +
        "\nTicker: [%s]" +
        "\nAction: %s" +
        "\nPrice: %.5f" +
        "\nPattern: [%s]",
        signal.ticker,
        signal.signal == SIGNAL_BUY ? "BUY" : 
            signal.signal == SIGNAL_SELL ? "SELL" : "NEUTRAL",
        signal.price,
        signal.pattern
    ));

    // Validate the signal
    bool validSignal = (
        StringLen(signal.ticker) > 0 && 
        signal.price > 0 && 
        signal.signal != SIGNAL_NEUTRAL &&
        StringLen(signal.pattern) > 0
    );

    Logger.Debug(StringFormat("Signal validation result: %s", validSignal ? "Valid" : "Invalid"));
    
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
        if(m_currentSymbol != Symbol() || m_currentSymbol != signal.ticker) {
            Logger.Error(StringFormat(
                "Symbol mismatch in ValidateSignal - Current: %s, Signal: %s, MT4: %s",
                m_currentSymbol, signal.ticker, Symbol()));
            return false;
        }

        if(signal.timestamp == m_lastSignalTimestamp || signal.timestamp == 0) {
            Logger.Debug("Duplicate or invalid signal timestamp - skipping");
            return false;
        }

        if(signal.price <= 0) {
            Logger.Error("Invalid signal price");
            return false;
        }

        return true;
    }


    //+------------------------------------------------------------------+
//| Check and apply profit protection                                  |
//+------------------------------------------------------------------+
void CheckProfitProtection(const PositionMetrics &metrics) {
    if(m_currentSymbol != Symbol()) {
        Logger.Error(StringFormat(
            "Symbol mismatch in CheckProfitProtection - Current: %s, MT4: %s",
            m_currentSymbol, Symbol()));
        return;
    }

    if(metrics.totalPositions == 0) return;

    for(int i = OrdersTotal() - 1; i >= 0; i--) {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
            if(OrderSymbol() == m_currentSymbol && 
               StringFind(OrderComment(), "Exit Signal") == -1) { 
                double currentPrice = OrderType() == OP_BUY ?
                                    m_symbolInfo.GetBid() : m_symbolInfo.GetAsk();
                double openPrice = OrderOpenPrice();
                double stopLoss = OrderStopLoss();
                double tp1 = OrderTakeProfit();


                // Only manage stops and protection if not already at TP
                if(tp1 == 0) {
                    // Calculate profit thresholds
                    double profitThreshold;
                    double lockProfit;

                    if(m_symbolInfo.IsCryptoPair()) {
                        profitThreshold = openPrice * (CRYPTO_PROFIT_THRESHOLD / 100.0);
                        lockProfit = openPrice * (CRYPTO_PROFIT_LOCK_PERCENT / 100.0);
                    } else {
                        profitThreshold = FOREX_PROFIT_PIPS_THRESHOLD * m_symbolInfo.GetPipSize();
                        lockProfit = FOREX_PROFIT_LOCK_PIPS * m_symbolInfo.GetPipSize();
                    }

                    // Check if profit exceeds threshold for trailing
                    if(OrderType() == OP_BUY) {
                        if((currentPrice - openPrice) >= profitThreshold) {
                            double newStop = currentPrice - lockProfit;
                            if(stopLoss == 0 || newStop > stopLoss) {
                                m_tradeManager.ModifyPosition(OrderTicket(), newStop);
                            }
                        }
                    } else {
                        if((openPrice - currentPrice) >= profitThreshold) {
                            double newStop = currentPrice + lockProfit;
                            if(stopLoss == 0 || newStop < stopLoss) {
                                m_tradeManager.ModifyPosition(OrderTicket(), newStop);
                            }
                        }
                    }
                }
            }
        }
    }
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
            if(ENABLE_PROFIT_PROTECTION) {
                CheckProfitProtection(metrics);
            }

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