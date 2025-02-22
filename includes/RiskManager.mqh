//+------------------------------------------------------------------+
//|                                                  RiskManager.mqh    |
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
//| Class for managing risk calculations and position sizing           |
//+------------------------------------------------------------------+
class CRiskManager {
private:
    CSymbolInfo*    m_symbolInfo;       // Symbol information
    double          m_riskPercent;      // Risk percentage per trade
    double          m_maxAccountRisk;   // Maximum total account risk
    double          m_marginBuffer;     // Margin safety buffer (percentage)


bool ValidateRiskLevels(double positionRisk, string context = "") {
    double accountBalance = AccountBalance();
    if(accountBalance <= 0) {
        Logger.Error("Invalid account balance");
        return false;
    }

    bool isEmergencyStop = (StringFind(context, "Emergency") >= 0);
    double riskPercent = (positionRisk / accountBalance) * 100;
    double totalRisk = CalculateTotalAccountRisk() + positionRisk;
    double totalRiskPercent = (totalRisk / accountBalance) * 100;

    Logger.Debug(StringFormat(
        "Risk Validation [%s]:" +
        "\nRisk Amount: %.2f" +
        "\nRisk Percent: %.2f%% (Limit: %.2f%%)" +
        "\nTotal Risk: %.2f" +
        "\nTotal Risk Percent: %.2f%% (Limit: %.2f%%)" +
        "\nEmergency Stop: %s",
        context,
        positionRisk,
        riskPercent, m_riskPercent,
        totalRisk,
        totalRiskPercent, m_maxAccountRisk,
        isEmergencyStop ? "Yes" : "No"
    ));

    if(riskPercent > m_riskPercent && !isEmergencyStop) {
        Logger.Warning(StringFormat(
            "Trade risk %.2f%% exceeds allowed risk per trade %.2f%%",
            riskPercent, m_riskPercent
        ));
        return false;
    }

    if(totalRiskPercent > m_maxAccountRisk) {
        Logger.Warning(StringFormat(
            "Total account risk %.2f%% exceeds maximum allowed %.2f%%",
            totalRiskPercent, m_maxAccountRisk
        ));
        return false;
    }

    return true;
}


public:
// Calculate monetary risk for a position
double CalculatePositionRisk(double lots, double entryPrice, double stopLoss, int orderType) {
    static datetime lastLog = 0;
    datetime currentTime = TimeCurrent();
    
    if(lots <= 0 || entryPrice <= 0 || stopLoss <= 0) return 0;
    
    double stopDistance = MathAbs(entryPrice - stopLoss);
    double riskAmount;
    
    if(m_symbolInfo.IsCryptoPair()) {
        riskAmount = stopDistance * lots * m_symbolInfo.GetContractSize();
    } else {
        double tickValue = MarketInfo(m_symbolInfo.GetSymbol(), MODE_TICKVALUE);
        double point = m_symbolInfo.GetPoint();
        
        if(point <= 0) {
            Logger.Error("Invalid point value");
            return 0;
        }
        
        riskAmount = (stopDistance / point) * tickValue * lots;
    }

    string stopLossType;
    if(orderType == OP_BUY) {
        stopLossType = "SL2 (BUY Stop)";
    } else {
        stopLossType = "SL2 (SELL Stop)";
    }
    
    // Log only every 60 seconds
    if(currentTime - lastLog >= 60) {
        Logger.Debug(StringFormat(
            "Risk Calculation:" +
            "\nDirection: %s" +
            "\nStop Type: %s" +
            "\nLots: %.2f" +
            "\nEntry: %.5f" +
            "\nStop Loss: %.5f" +
            "\nStop Distance: %.5f" +
            "\nRisk Amount: %.2f",
            orderType == OP_BUY ? "BUY" : "SELL",
            stopLossType,
            lots,
            entryPrice,
            stopLoss,
            stopDistance,
            riskAmount
        ));
        lastLog = currentTime;
    }
    
    return riskAmount;
}
    
    // Calculate maximum position value based on margin
    double CalculateMaxPositionValue() {
        double accountEquity = AccountEquity();
        double marginRequirement = m_symbolInfo.GetMarginPercent();

        // Validate margin requirement
        if(marginRequirement <= 0) {
            Logger.Error("Invalid margin requirement");
            return 0;
        }

        double safetyBuffer = 1 + (m_marginBuffer / 100.0);
        double freeMargin = AccountFreeMargin();

        // Log margin values for debugging
        //Logger.Debug(StringFormat(
            //"Margin Calculation:" +
            //"\nFree Margin: %.2f" +
            //"\nMargin Requirement: %.2f" +
            //"\nSafety Buffer: %.2f",
            //freeMargin, marginRequirement, safetyBuffer
       // ));

        return (freeMargin / (marginRequirement * safetyBuffer));
    }


    // Constructor
    CRiskManager(CSymbolInfo* symbolInfo, double riskPercent = DEFAULT_RISK_PERCENT,
                     double maxAccountRisk = DEFAULT_RISK_PERCENT * 3,
                     double marginBuffer = 50) {

            if(AccountBalance() <= 0) {
                Logger.Error("Invalid account balance - check account connection");
                ExpertRemove();
                return;
            }

            // Validate symbol info pointer
            if(symbolInfo == NULL) {
                Logger.Error("NULL symbol info passed to RiskManager");
                ExpertRemove(); 
                return;
            }

            // Validate risk parameters
            if(riskPercent <= 0 || riskPercent > 100) {
                Logger.Error(StringFormat("Invalid risk percent: %.2f, using default: %.2f",
                            riskPercent, DEFAULT_RISK_PERCENT));
                riskPercent = DEFAULT_RISK_PERCENT;
            }

            if(maxAccountRisk <= 0 || maxAccountRisk > 100) {
                Logger.Error(StringFormat("Invalid max account risk: %.2f, using default: %.2f",
                            maxAccountRisk, DEFAULT_RISK_PERCENT * 3));
                maxAccountRisk = DEFAULT_RISK_PERCENT * 3;
            }

            if(marginBuffer < 0) {
                Logger.Error(StringFormat("Invalid margin buffer: %.2f, using default: 50", marginBuffer));
                marginBuffer = 50;
            }

            // Initialize member variables
            m_symbolInfo = symbolInfo;
            m_riskPercent = riskPercent;
            m_maxAccountRisk = maxAccountRisk;
            m_marginBuffer = marginBuffer;

            // Log initialization
            Logger.Info(StringFormat(
                "RiskManager initialized:" +
                "\nSymbol: %s" +
                "\nRisk Percent: %.2f%%" +
                "\nMax Account Risk: %.2f%%" +
                "\nMargin Buffer: %.2f%%",
                m_symbolInfo.GetSymbol(),
                m_riskPercent,
                m_maxAccountRisk,
                m_marginBuffer
            ));
        }
    
// Calculate position size based on risk parameters
double CalculatePositionSize(double entryPrice, double stopLoss, int orderType) { 
      // Initial parameter validation with detailed logging
      if(entryPrice <= 0 || stopLoss <= 0) {
          Logger.Error(StringFormat("Invalid input parameters - Entry: %.5f, StopLoss: %.5f",
              entryPrice, stopLoss));
          return 0;
      }

      // Calculate risk amount based on account balance
      double accountBalance = AccountBalance();
      if(accountBalance <= 0) {
          Logger.Error(StringFormat("Invalid account balance: %.2f", accountBalance));
          return 0;
      }

      double maxRiskAmount = accountBalance * (m_riskPercent / 100.0);
      double stopDistance = MathAbs(entryPrice - stopLoss);

      //Logger.Debug(StringFormat(
         // "Initial Risk Calculation:" +
         // "\nAccount Balance: %.2f" +
         // "\nRisk Percent: %.2f%%" +
         // "\nMax Risk Amount: %.2f" +
         // "\nStop Distance: %.5f",
         // accountBalance, m_riskPercent, maxRiskAmount, stopDistance
     // ));

      double lotSize = 0;

      if(m_symbolInfo.IsCryptoPair()) {
          // Calculate crypto position size
          double contractSize = m_symbolInfo.GetContractSize();
          if(contractSize <= 0) {
              Logger.Error(StringFormat("Invalid contract size for crypto: %.2f", contractSize));
              return 0;
          }

          double oneUnitValue = entryPrice * contractSize;
          double riskPerLot = stopDistance * oneUnitValue;

          // Validation to prevent division by zero
          if(riskPerLot <= 0) {
              Logger.Error(StringFormat("Invalid risk per lot calculation for crypto - OneUnitValue: %.5f, StopDistance: %.5f",
                  oneUnitValue, stopDistance));
              return 0;
          }

          // Initial lot size based on risk
          lotSize = maxRiskAmount / riskPerLot;

          // Apply margin constraints
          double maxPositionValue = CalculateMaxPositionValue();
          if(maxPositionValue <= 0 || oneUnitValue <= 0) {
              Logger.Error(StringFormat("Invalid position value calculation - MaxValue: %.2f, UnitValue: %.5f",
                  maxPositionValue, oneUnitValue));
              return 0;
          }

          double maxLotsMargin = maxPositionValue / oneUnitValue;

          // Apply equity constraints
          double maxPositionEquity = AccountEquity() * (m_riskPercent * 2 / 100.0);
          double maxLotsEquity = maxPositionEquity / oneUnitValue;

         // Logger.Debug(StringFormat(
           //   "Crypto Position Size Constraints:" +
            //  "\nInitial Lot Size: %.4f" +
           //   "\nMargin Max Lots: %.4f" +
           //   "\nEquity Max Lots: %.4f",
           //   lotSize, maxLotsMargin, maxLotsEquity
       //   ));

          // Take the minimum of all constraints
          lotSize = MathMin(lotSize, maxLotsMargin);
          lotSize = MathMin(lotSize, maxLotsEquity);
      } else {
          // Calculate forex position size
          double pipValue = m_symbolInfo.GetPipValue();
          double pipSize = m_symbolInfo.GetPipSize();

          // Validate pip values
          if(pipSize <= 0) {
              Logger.Error(StringFormat("Invalid pip size: %.5f", pipSize));
              return 0;
          }

          if(pipValue <= 0) {
              Logger.Error(StringFormat("Invalid pip value: %.5f", pipValue));
              return 0;
          }

          double stopPips = stopDistance / pipSize;
          double riskPerLot = stopPips * pipValue;

        //  Logger.Debug(StringFormat(
          //    "Forex Position Size Calculation:" +
         //     "\nPip Value: %.5f" +
         //     "\nPip Size: %.5f" +
         //     "\nStop Distance: %.5f" +
         //     "\nStop Pips: %.2f" +
          //    "\nRisk Per Lot: %.2f",
         //     pipValue, pipSize, stopDistance, stopPips, riskPerLot
        //  ));

          // Validate risk per lot
          if(riskPerLot <= 0) {
              Logger.Error(StringFormat("Invalid risk per lot: %.5f (PipValue=%.5f, StopPips=%.5f)",
                  riskPerLot, pipValue, stopPips));
              return 0;
          }

          // Initial lot size based on risk
          lotSize = maxRiskAmount / riskPerLot;

          // Get contract size for margin calculations
          double contractSize = m_symbolInfo.GetContractSize();
          if(contractSize <= 0) {
              Logger.Error(StringFormat("Invalid contract size: %.2f", contractSize));
              return 0;
          }

          // Apply margin constraints
          double maxPositionValue = CalculateMaxPositionValue();
          if(maxPositionValue <= 0) {
              Logger.Error(StringFormat("Invalid max position value: %.2f", maxPositionValue));
              return 0;
          }

          double maxLotsMargin = maxPositionValue / (contractSize * entryPrice);

          // Apply equity constraints
          double maxLotsEquity = (AccountEquity() * (m_riskPercent * 2 / 100.0)) /
                               (contractSize * entryPrice);

       //   Logger.Debug(StringFormat(
        //      "Forex Position Size Constraints:" +
         //     "\nInitial Lot Size: %.4f" +
        //      "\nMargin Max Lots: %.4f" +
        //      "\nEquity Max Lots: %.4f",
         //     lotSize, maxLotsMargin, maxLotsEquity
        //  ));

          // Take the minimum of all constraints
          lotSize = MathMin(lotSize, maxLotsMargin);
          lotSize = MathMin(lotSize, maxLotsEquity);
      }

      // Apply broker constraints
      double minLot = MathMax(0.03, MarketInfo(m_symbolInfo.GetSymbol(), MODE_MINLOT));
      double maxLot = MarketInfo(m_symbolInfo.GetSymbol(), MODE_MAXLOT);
      double lotStep = MarketInfo(m_symbolInfo.GetSymbol(), MODE_LOTSTEP);

      // Validate broker constraints
      if(lotStep <= 0) {
          Logger.Error("Invalid lot step from broker");
          return minLot;  // Return minimum lot size as fallback
      }

      // Round to lot step
      lotSize = MathFloor(lotSize / lotStep) * lotStep;

      // Ensure within broker's limits
      double finalLotSize = MathMax(minLot, MathMin(maxLot, lotSize));

      Logger.Debug(StringFormat(
          "Final Lot Size Calculation:" +
          "\nRounded Lot Size: %.4f" +
          "\nMin Lot: %.4f" +
          "\nMax Lot: %.4f" +
          "\nLot Step: %.4f" +
          "\nFinal Size: %.4f",
          lotSize, minLot, maxLot, lotStep, finalLotSize
      ));

       // When validating the final position size
    if(!ValidatePositionRisk(finalLotSize, entryPrice, stopLoss, orderType)) {
        Logger.Warning("Final lot size exceeds risk parameters - reducing to minimum");
        return minLot;
    }

    return finalLotSize;
  }
    
    
    // Calculate total account risk from all open positions
double CalculateTotalAccountRisk() {
    static datetime lastDetailedLog = 0;
    datetime currentTime = TimeCurrent();
    
    double totalRisk = 0;
    int positions = 0;
    
    for(int i = 0; i < OrdersTotal(); i++) {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
            if(OrderSymbol() == m_symbolInfo.GetSymbol() && OrderStopLoss() != 0) {
                positions++;
                double posRisk = CalculatePositionRisk(OrderLots(), 
                                OrderOpenPrice(), OrderStopLoss(), OrderType());
                totalRisk += posRisk;
                
                // Log details only every 60 seconds
                if(currentTime - lastDetailedLog >= 60) {
                    Logger.Debug(StringFormat(
                        "Position Risk Details [%d/%d]:" +
                        "\nDirection: %s" +
                        "\nLots: %.2f" +
                        "\nRisk Amount: %.2f" +
                        "\nTotal Risk: %.2f",
                        positions,
                        OrdersTotal(),
                        OrderType() == OP_BUY ? "BUY" : "SELL",
                        OrderLots(),
                        posRisk,
                        totalRisk
                    ));
                    lastDetailedLog = currentTime;
                }
            }
        }
    }
    
    return totalRisk;
}

bool ValidatePositionRisk(double lots, double entryPrice, double stopLoss, int orderType) {
    // First log the validation attempt with proper formatting
    Logger.Debug(StringFormat(
        "Validating Position Risk:" +
        "\nOrder Type: %s" +
        "\nLots: %.2f" +
        "\nEntry Price: %.5f" +
        "\nStop Loss: %.5f",
        orderType == OP_BUY ? "BUY" : "SELL",
        lots,
        entryPrice,
        stopLoss
    ));

    if(lots <= 0 || entryPrice <= 0 || stopLoss <= 0) {
        Logger.Error(StringFormat(
            "Invalid risk parameters:" +
            "\nLots: %.2f" +
            "\nEntry Price: %.5f" +
            "\nStop Loss: %.5f",
            lots, entryPrice, stopLoss
        ));
        return false;
    }

    // Check if this is an emergency stop
    bool isEmergencyStop = false;
    double emergencyStopDistance;
    
    if(m_symbolInfo.IsCryptoPair()) {
        emergencyStopDistance = entryPrice * (CRYPTO_EMERGENCY_STOP_PERCENT / 100.0);
    } else {
        emergencyStopDistance = FOREX_EMERGENCY_PIPS * m_symbolInfo.GetPipSize();
    }

    double stopDistance = MathAbs(entryPrice - stopLoss);
    if(orderType == OP_BUY) {
        isEmergencyStop = stopLoss <= (entryPrice - emergencyStopDistance);
    } else {
        isEmergencyStop = stopLoss >= (entryPrice + emergencyStopDistance);
    }

    // Calculate and validate risk
    double positionRisk = CalculatePositionRisk(lots, entryPrice, stopLoss, orderType);
    
    Logger.Debug(StringFormat(
        "Risk Validation - %s:" +
        "\nStop Loss Type: %s" +
        "\nLots: %.2f" +
        "\nEntry Price: %.5f" +
        "\nStop Loss: %.5f" +
        "\nStop Distance: %.5f" +
        "\nRisk Amount: %.2f" +
        "\nEmergency Stop: %s",
        orderType == OP_BUY ? "BUY" : "SELL",
        isEmergencyStop ? "Emergency" : "Normal",
        lots,
        entryPrice,
        stopLoss,
        stopDistance,
        positionRisk,
        isEmergencyStop ? "Yes" : "No"
    ));

    // Validate against risk levels
    return ValidateRiskLevels(
        positionRisk, 
        isEmergencyStop ? "Emergency" : StringFormat("%s Position Risk", 
            orderType == OP_BUY ? "BUY" : "SELL")
    );
}

    bool ValidateNewPosition(double lots, double entryPrice, double stopLoss, int orderType) {
        // Count existing positions first
        int existingPositions = 0;
        for(int i = 0; i < OrdersTotal(); i++) {
            if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
                if(OrderSymbol() == m_symbolInfo.GetSymbol()) {
                    existingPositions++;
                }
            }
        }

        if(existingPositions >= MAX_POSITIONS_PER_SYMBOL) {
            Logger.Warning(StringFormat(
                "Maximum positions (%d) already reached for %s",
                MAX_POSITIONS_PER_SYMBOL,
                m_symbolInfo.GetSymbol()
            ));
            return false;
        }

        return ValidatePositionRisk(lots, entryPrice, stopLoss, orderType);
    }
    
    // Check margin level safety
    bool IsMarginSafe() {
        static datetime lastMarginLog = 0;
        datetime currentTime = TimeCurrent();
        
        double margin = AccountMargin();
        double equity = AccountEquity();

        if(margin <= 0) {
            return true;  // No margin used
        }

        double marginLevel = (equity / margin) * 100;
        bool isSafe = marginLevel >= (100 + m_marginBuffer);

        // Log status changes or every 5 minutes
        static bool lastSafeStatus = true;
        if(lastSafeStatus != isSafe || currentTime - lastMarginLog >= 300) {
            Logger.Debug(StringFormat(
                "[%s] Margin Status: %s (Level: %.2f%%, Required: %.2f%%)",
                m_symbolInfo.GetSymbol(),
                isSafe ? "Safe" : "UNSAFE",
                marginLevel,
                100 + m_marginBuffer
            ));
            lastMarginLog = currentTime;
            lastSafeStatus = isSafe;
        }

        return isSafe;
    }
    
    // Getters and setters
    double GetRiskPercent() const { return m_riskPercent; }
    void SetRiskPercent(double value) {
        if(value <= 0 || value > 100) {
            Logger.Error(StringFormat("Invalid risk percent: %.2f, keeping current: %.2f",
                        value, m_riskPercent));
            return;
        }
        m_riskPercent = value;
        Logger.Info(StringFormat("Risk percent updated to: %.2f%%", value));
    }
    
    double GetMaxAccountRisk() const { return m_maxAccountRisk; }
    void SetMaxAccountRisk(double value) {
        if(value <= 0 || value > 100) {
            Logger.Error(StringFormat("Invalid max account risk: %.2f, keeping current: %.2f",
                        value, m_maxAccountRisk));
            return;
        }
        m_maxAccountRisk = value;
        Logger.Info(StringFormat("Max account risk updated to: %.2f%%", value));
    }
    
    double GetMarginBuffer() const { return m_marginBuffer; }
    void SetMarginBuffer(double value) {
        if(value < 0) {
            Logger.Error(StringFormat("Invalid margin buffer: %.2f, keeping current: %.2f",
                        value, m_marginBuffer));
            return;
        }
        m_marginBuffer = value;
        Logger.Info(StringFormat("Margin buffer updated to: %.2f%%", value));
    }


};
