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

        double riskPercent = (positionRisk / accountBalance) * 100;
        double totalRisk = CalculateTotalAccountRisk() + positionRisk;
        double totalRiskPercent = (totalRisk / accountBalance) * 100;

        Logger.Debug(StringFormat(
            "Risk Validation [%s]:" +
            "\nPosition Risk: %.2f%%" +
            "\nTotal Risk: %.2f%%" +
            "\nRisk Limit: %.2f%%" +
            "\nTotal Risk Limit: %.2f%%",
            context,
            riskPercent,
            totalRiskPercent,
            m_riskPercent,
            m_maxAccountRisk
        ));

        // Check position risk
        if(riskPercent > m_riskPercent) {
            Logger.Warning(StringFormat("[%s] Position risk %.2f%% exceeds limit %.2f%%",
                          context, riskPercent, m_riskPercent));
            return false;
        }

        // Check total account risk
        if(totalRiskPercent > m_maxAccountRisk) {
            Logger.Warning(StringFormat("[%s] Total account risk %.2f%% exceeds limit %.2f%%",
                          context, totalRiskPercent, m_maxAccountRisk));
            return false;
        }

        return true;
    }

public:
// Calculate monetary risk for a position
double CalculatePositionRisk(double lots, double entryPrice, double stopLoss, int orderType) {
    if(lots <= 0 || entryPrice <= 0 || stopLoss <= 0) return 0;
    
    double stopDistance = MathAbs(entryPrice - stopLoss);
    
    // Log risk calculation details
    Logger.Debug(StringFormat(
        "Calculating Position Risk:" +
        "\nDirection: %s" +
        "\nLots: %.2f" +
        "\nEntry: %.5f" +
        "\nStop Loss: %.5f" +
        "\nStop Distance: %.5f",
        orderType == OP_BUY ? "BUY" : "SELL",
        lots, entryPrice, stopLoss, stopDistance
    ));
    
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

            // Validate symbol info pointer
            if(symbolInfo == NULL) {
                Logger.Error("NULL symbol info passed to RiskManager");
                ExpertRemove();  // Stop the EA if symbol info is NULL
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
      double minLot = MarketInfo(m_symbolInfo.GetSymbol(), MODE_MINLOT);
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
    double totalRisk = 0;
    int positions = 0;
    
    for(int i = 0; i < OrdersTotal(); i++) {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
            if(OrderSymbol() == m_symbolInfo.GetSymbol() && OrderStopLoss() != 0) {
                positions++;
                double posRisk = CalculatePositionRisk(OrderLots(), 
                                OrderOpenPrice(), OrderStopLoss(), OrderType());
                totalRisk += posRisk;
                
                Logger.Debug(StringFormat(
                    "Position Risk Details [%d]:" +
                    "\nDirection: %s" +
                    "\nLots: %.2f" +
                    "\nRisk Amount: %.2f" +
                    "\nRunning Total: %.2f",
                    positions,
                    OrderType() == OP_BUY ? "BUY" : "SELL",
                    OrderLots(),
                    posRisk,
                    totalRisk
                ));
            }
        }
    }
    
    return totalRisk;
}


bool ValidatePositionRisk(double lots, double entryPrice, double stopLoss, int orderType) {
        if(lots <= 0 || entryPrice <= 0 || stopLoss <= 0) {
            Logger.Error(StringFormat(
                "Invalid risk parameters - Lots: %.2f, Entry: %.5f, SL: %.5f",
                lots, entryPrice, stopLoss
            ));
            return false;
        }

        double positionRisk = CalculatePositionRisk(lots, entryPrice, stopLoss, orderType);
        return ValidateRiskLevels(positionRisk, "Position Risk");
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
        double margin = AccountMargin();
        double equity = AccountEquity();

     //   Logger.Debug(StringFormat(
     //       "Margin Safety Check:" +
      //      "\nEquity: %.2f" +
      //      "\nMargin: %.2f" +
      //      "\nBuffer Required: %.2f%%",
     //       equity, margin, m_marginBuffer));

        if(margin <= 0) {
            Logger.Debug("No margin used - position is safe");
            return true;
        }

        double marginLevel = (equity / margin) * 100;
        bool isSafe = marginLevel >= (100 + m_marginBuffer);

       // Logger.Debug(StringFormat(
       //     "Margin Level: %.2f%% (Minimum required: %.2f%%) - %s",
       //     marginLevel, (100 + m_marginBuffer), isSafe ? "Safe" : "Unsafe"));

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
