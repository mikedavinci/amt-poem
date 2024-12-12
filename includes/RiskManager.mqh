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
    
    // Calculate monetary risk for a position
    double CalculatePositionRisk(double lots, double entryPrice, double stopLoss) {
        if(lots <= 0 || entryPrice <= 0 || stopLoss <= 0) return 0;
        
        double stopDistance = MathAbs(entryPrice - stopLoss);
        
        if(m_symbolInfo.IsCryptoPair()) {
            // Crypto risk calculation
            return stopDistance * lots * m_symbolInfo.GetContractSize();
        } else {
            // Forex risk calculation
            double tickValue = MarketInfo(m_symbolInfo.GetSymbol(), MODE_TICKVALUE);
            double point = m_symbolInfo.GetPoint();
            return (stopDistance / point) * tickValue * lots;
        }
    }
    
    // Calculate maximum position value based on margin
    double CalculateMaxPositionValue() {
        double accountEquity = AccountEquity();
        double marginRequirement = m_symbolInfo.GetMarginPercent();
        double safetyBuffer = 1 + (m_marginBuffer / 100.0);
        
        return (AccountFreeMargin() / (marginRequirement * safetyBuffer));
    }

public:
    // Constructor
    CRiskManager(CSymbolInfo* symbolInfo, double riskPercent = DEFAULT_RISK_PERCENT,
                 double maxAccountRisk = DEFAULT_RISK_PERCENT * 3,
                 double marginBuffer = 50) 
        : m_symbolInfo(symbolInfo),
          m_riskPercent(riskPercent),
          m_maxAccountRisk(maxAccountRisk),
          m_marginBuffer(marginBuffer) {
    }
    
    // Calculate position size based on risk parameters
    double CalculatePositionSize(double entryPrice, double stopLoss) {
        if(entryPrice <= 0 || stopLoss <= 0) return 0;
        
        // Calculate risk amount based on account balance
        double accountBalance = AccountBalance();
        double maxRiskAmount = accountBalance * (m_riskPercent / 100.0);
        double stopDistance = MathAbs(entryPrice - stopLoss);
        
        double lotSize = 0;
        
        if(m_symbolInfo.IsCryptoPair()) {
            // Calculate crypto position size
            double oneUnitValue = entryPrice * m_symbolInfo.GetContractSize();
            double riskPerLot = stopDistance * oneUnitValue;
            
            // Initial lot size based on risk
            lotSize = maxRiskAmount / riskPerLot;
            
            // Apply margin constraints
            double maxPositionValue = CalculateMaxPositionValue();
            double maxLotsMargin = maxPositionValue / oneUnitValue;
            
            // Apply equity constraints
            double maxPositionEquity = AccountEquity() * (m_riskPercent * 2 / 100.0);
            double maxLotsEquity = maxPositionEquity / oneUnitValue;
            
            // Take the minimum of all constraints
            lotSize = MathMin(lotSize, maxLotsMargin);
            lotSize = MathMin(lotSize, maxLotsEquity);
        } else {
            // Calculate forex position size
            double pipValue = m_symbolInfo.GetPipValue();
            double pipSize = m_symbolInfo.GetPipSize();
            double stopPips = stopDistance / pipSize;
            
            // Calculate risk per standard lot
            double riskPerLot = stopPips * pipValue;
            
            // Initial lot size based on risk
            lotSize = maxRiskAmount / riskPerLot;
            
            // Apply margin constraints
            double maxLotsMargin = CalculateMaxPositionValue() / 
                                 (m_symbolInfo.GetContractSize() * entryPrice);
            
            // Apply equity constraints
            double maxLotsEquity = (AccountEquity() * (m_riskPercent * 2 / 100.0)) /
                                 (m_symbolInfo.GetContractSize() * entryPrice);
            
            // Take the minimum of all constraints
            lotSize = MathMin(lotSize, maxLotsMargin);
            lotSize = MathMin(lotSize, maxLotsEquity);
        }
        
        // Apply broker constraints
        double minLot = MarketInfo(m_symbolInfo.GetSymbol(), MODE_MINLOT);
        double maxLot = MarketInfo(m_symbolInfo.GetSymbol(), MODE_MAXLOT);
        double lotStep = MarketInfo(m_symbolInfo.GetSymbol(), MODE_LOTSTEP);
        
        // Round to lot step
        lotSize = MathFloor(lotSize / lotStep) * lotStep;
        
        // Ensure within broker's limits
        lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
        
        return lotSize;
    }
    
    // Validate risk levels for a potential position
    bool ValidatePositionRisk(double lots, double entryPrice, double stopLoss) {
        if(lots <= 0 || entryPrice <= 0 || stopLoss <= 0) return false;
        
        double positionRisk = CalculatePositionRisk(lots, entryPrice, stopLoss);
        double accountBalance = AccountBalance();
        double riskPercent = (positionRisk / accountBalance) * 100;
        
        // Check position risk
        if(riskPercent > m_riskPercent) {
            Logger.Warning(StringFormat("Position risk %.2f%% exceeds limit %.2f%%", 
                          riskPercent, m_riskPercent));
            return false;
        }
        
        // Check total account risk
        double totalRisk = CalculateTotalAccountRisk() + positionRisk;
        double totalRiskPercent = (totalRisk / accountBalance) * 100;
        
        if(totalRiskPercent > m_maxAccountRisk) {
            Logger.Warning(StringFormat("Total account risk %.2f%% exceeds limit %.2f%%", 
                          totalRiskPercent, m_maxAccountRisk));
            return false;
        }
        
        return true;
    }
    
    // Calculate total account risk from all open positions
    double CalculateTotalAccountRisk() {
        double totalRisk = 0;
        
        for(int i = 0; i < OrdersTotal(); i++) {
            if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
                if(OrderStopLoss() != 0) {
                    totalRisk += CalculatePositionRisk(OrderLots(), 
                                OrderOpenPrice(), OrderStopLoss());
                }
            }
        }
        
        return totalRisk;
    }
    
    // Check margin level safety
    bool IsMarginSafe() {
        if(AccountMargin() == 0) return true;
        
        double marginLevel = (AccountEquity() / AccountMargin()) * 100;
        return marginLevel >= (100 + m_marginBuffer);
    }
    
    // Getters and setters
    double GetRiskPercent() const { return m_riskPercent; }
    void SetRiskPercent(double value) { m_riskPercent = value; }
    
    double GetMaxAccountRisk() const { return m_maxAccountRisk; }
    void SetMaxAccountRisk(double value) { m_maxAccountRisk = value; }
    
    double GetMarginBuffer() const { return m_marginBuffer; }
    void SetMarginBuffer(double value) { m_marginBuffer = value; }
};