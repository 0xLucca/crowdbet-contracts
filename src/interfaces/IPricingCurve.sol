// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IPricingCurve
 * @dev Interface for different pricing curve implementations
 */
interface IPricingCurve {
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
    ) external pure returns (uint256 price);
    
    /**
     * @dev Calculates the price for selling tokens
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
    ) external pure returns (uint256 price);
    
    /**
     * @dev Gets the pricing curve type
     * @return curveType A string identifying the curve type
     */
    function getCurveType() external pure returns (string memory curveType);

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
    ) external pure returns (uint256 outputAmount);
}
