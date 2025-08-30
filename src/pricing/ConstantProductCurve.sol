// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../interfaces/IPricingCurve.sol";

/**
 * @title ConstantProductCurve
 * @dev Implements constant product AMM pricing (x * y = k)
 */
contract ConstantProductCurve is IPricingCurve {
    uint256 private constant INITIAL_LIQUIDITY = 1000 * 1e18; // Initial liquidity for both sides
    
    /**
     * @dev Calculates the price for buying tokens
     * @param yesSupply Current supply of YES tokens
     * @param noSupply Current supply of NO tokens
     * @param amount Amount of tokens to buy
     * @param buyingYes Whether buying YES (true) or NO (false) tokens
     * @return price The price in wei for the purchase
     */
    function calculateBuyPrice(
        uint256 yesSupply,
        uint256 noSupply,
        uint256 amount,
        bool buyingYes
    ) external pure override returns (uint256 price) {
        // If no liquidity, use initial liquidity values
        if (yesSupply == 0 && noSupply == 0) {
            yesSupply = INITIAL_LIQUIDITY;
            noSupply = INITIAL_LIQUIDITY;
        }
        
        // For constant product curve, the price is the input needed for the output
        // Using the formula: inputAmount = currentReserve - (k / (currentReserve + amount))
        uint256 k = yesSupply * noSupply;
        
        if (buyingYes) {
            // Buying YES tokens: price is what we pay to get 'amount' YES tokens
            uint256 newYesSupply = yesSupply + amount;
            uint256 newNoSupply = k / newYesSupply;
            price = noSupply - newNoSupply;
        } else {
            // Buying NO tokens: price is what we pay to get 'amount' NO tokens
            uint256 newNoSupply = noSupply + amount;
            uint256 newYesSupply = k / newNoSupply;
            price = yesSupply - newYesSupply;
        }
    }
    
    /**
     * @dev Calculates the amount of tokens received for a given input amount using constant product formula
     * @param yesSupply Current supply of YES tokens
     * @param noSupply Current supply of NO tokens
     * @param inputAmount Amount of payment tokens to spend
     * @param buyingYes Whether buying YES (true) or NO (false) tokens
     * @return outputAmount The amount of YES or NO tokens received
     */
    function calculateExactInput(
        uint256 yesSupply,
        uint256 noSupply,
        uint256 inputAmount,
        bool buyingYes
    ) external pure override returns (uint256 outputAmount) {
        // If no liquidity, use initial liquidity values
        if (yesSupply == 0 && noSupply == 0) {
            yesSupply = INITIAL_LIQUIDITY;
            noSupply = INITIAL_LIQUIDITY;
        }
        
        // Constant product: x * y = k
        uint256 k = yesSupply * noSupply;
        
        if (buyingYes) {
            // Buying YES tokens: need to increase YES supply, decrease NO supply
            uint256 newNoSupply = noSupply - inputAmount;
            uint256 newYesSupply = k / newNoSupply;
            outputAmount = newYesSupply - yesSupply;
        } else {
            // Buying NO tokens: need to increase NO supply, decrease YES supply
            uint256 newYesSupply = yesSupply - inputAmount;
            uint256 newNoSupply = k / newYesSupply;
            outputAmount = newNoSupply - noSupply;
        }
    }
    
    /**
     * @dev Calculates the price for selling tokens using constant product formula
     * @param yesSupply Current supply of YES tokens
     * @param noSupply Current supply of NO tokens
     * @param amount Amount of tokens to sell
     * @param sellingYes Whether selling YES (true) or NO (false) tokens
     * @return price The price in wei for the sale
     */
    function calculateSellPrice(
        uint256 yesSupply,
        uint256 noSupply,
        uint256 amount,
        bool sellingYes
    ) external pure override returns (uint256 price) {
        require(yesSupply > 0 && noSupply > 0, "No liquidity available");
        
        // Constant product: x * y = k
        uint256 k = yesSupply * noSupply;
        
        if (sellingYes) {
            // Selling YES tokens: decrease YES supply, increase NO supply
            require(yesSupply >= amount, "Insufficient YES supply");
            uint256 newYesSupply = yesSupply - amount;
            require(newYesSupply > 0, "Cannot sell all supply");
            uint256 newNoSupply = k / newYesSupply;
            price = newNoSupply - noSupply;
        } else {
            // Selling NO tokens: decrease NO supply, increase YES supply
            require(noSupply >= amount, "Insufficient NO supply");
            uint256 newNoSupply = noSupply - amount;
            require(newNoSupply > 0, "Cannot sell all supply");
            uint256 newYesSupply = k / newNoSupply;
            price = newYesSupply - yesSupply;
        }
    }
    
    /**
     * @dev Gets the pricing curve type
     * @return curveType A string identifying the curve type
     */
    function getCurveType() external pure override returns (string memory curveType) {
        return "ConstantProduct";
    }
}
