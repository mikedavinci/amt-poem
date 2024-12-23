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
        // Symbol validation
        if(m_currentSymbol != Symbol()) {
            Logger.Error("Symbol mismatch in ProcessSignals");
            return;
        }

        string response = FetchSignals();
        if(response == "") return;

        SignalData signal;
        if(ParseSignal(response, signal)) {
            // Validate signal is for current symbol
            if(signal.ticker != m_currentSymbol) {
                Logger.Warning(StringFormat(
                    "Signal ticker mismatch - Expected: %s, Got: %s",
                    m_currentSymbol, signal.ticker));
                return;
            }

            if(ValidateSignal(signal)) {
                if(signal.isExitSignal) {
                    ProcessExitSignal(signal);
                } else {
                    signal.instrumentType = m_symbolInfo.IsCryptoPair() ?
                        INSTRUMENT_CRYPTO : INSTRUMENT_FOREX;
                    ExecuteSignal(signal);
                }
            }
        }
    }

    // Rest of your existing methods with added symbol validation...
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
                if(OrderSymbol() == signal.ticker) {
                    bool shouldClose = false;
                    
                    if(OrderType() == OP_BUY && signal.exitType == EXIT_BEARISH) {
                        shouldClose = true;
                        Logger.Debug("Closing BUY position on Bearish Exit signal");
                    }
                    else if(OrderType() == OP_SELL && signal.exitType == EXIT_BULLISH) {
                        shouldClose = true;
                        Logger.Debug("Closing SELL position on Bullish Exit signal");
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
        double stopLoss = m_symbolInfo.CalculateStopLoss(orderType, signal.price);
        Logger.Debug(StringFormat("Calculated Stop Loss: %.5f", stopLoss));

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
                Logger.Debug(StringFormat("Executing BUY order - Lots: %.2f, Stop Loss: %.5f", lots, stopLoss));
                success = m_tradeManager.OpenBuyPosition(lots, stopLoss, 0, tradeComment);
                break;

            case SIGNAL_SELL:
                Logger.Debug(StringFormat("Executing SELL order - Lots: %.2f, Stop Loss: %.5f", lots, stopLoss));
                success = m_tradeManager.OpenSellPosition(lots, stopLoss, 0, tradeComment);
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