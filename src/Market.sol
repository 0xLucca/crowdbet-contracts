// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IPricingCurve.sol";
import "./MarketToken.sol";

/**
 * @title Market
 * @dev A prediction market contract for binary outcomes
 */
contract Market is ReentrancyGuard {
    // Market states
    enum MarketState { Active, TradingFrozen, Resolved, Cancelled }
    
    // Market tokens
    MarketToken public immutable yesToken;
    MarketToken public immutable noToken;
    
    // Market configuration
    uint256 marketId;
    string public question;
    uint256 public endTime;
    // Market resolution tracking
    bool public outcome; // true = YES wins, false = NO wins
    bool public isResolved; // Whether the market has been resolved
    
    // Fee configuration
    uint256 public immutable creatorFeePercentage; // Creator fee percentage in basis points (e.g., 100 = 1%)
    uint256 public immutable protocolFeeSharePercentage; // Protocol's share of creator fees in basis points
    address public immutable protocolFeeRecipient;
    address public immutable eventCreator;
    
    // Resolver and pricing
    address public resolver;
    IPricingCurve public pricingCurve;
    
    // Fee tracking
    uint256 public eventCreatorFees;
    bool public feesWithdrawn;
    
    // Supply tracking
    uint256 public yesSupply;
    uint256 public noSupply;
    
    // Initial virtual liquidity to maintain constant product formula
    uint256 private constant INITIAL_LIQUIDITY = 1000 * 1e18;
    
    // Events
    event TokensPurchased(address indexed buyer, bool isYes, uint256 amount, uint256 cost);
    event TokensSold(address indexed seller, bool isYes, uint256 amount, uint256 payout);
    event TradingFrozen();
    event MarketResolved(bool outcome);
    event FeesWithdrawn(address indexed eventCreator, uint256 amount);
    event TokensRedeemed(address indexed user, uint256 amount);
    
    // Errors
    error MarketNotActive();
    error MarketNotResolved();
    error MarketAlreadyResolved();
    error MarketTradingFrozen();
    error MarketNotFrozen();
    error InsufficientPayment();
    error InsufficientTokens();
    error UnauthorizedResolver();
    error FeesAlreadyWithdrawn();
    error NoFeesToWithdraw();
    
    /**
     * @dev Constructor to initialize the market
     * @param _marketId The market ID
     * @param _question The question being predicted
     * @param _endTime When the market ends
     * @param _creatorFeePercentage Creator fee percentage in basis points
     * @param _protocolFeeSharePercentage Protocol's share of creator fees in basis points
     * @param _protocolFeeRecipient Address to receive protocol fees
     * @param _eventCreator Address of the event creator
     * @param _resolver The resolver contract
     * @param _pricingCurve The pricing curve contract
     */
    constructor(
        uint256 _marketId,
        string memory _question,
        uint256 _endTime,
        uint256 _creatorFeePercentage,
        uint256 _protocolFeeSharePercentage,
        address _protocolFeeRecipient,
        address _eventCreator,
        address _resolver,
        IPricingCurve _pricingCurve
    ) {
        marketId = _marketId;
        question = _question;
        endTime = _endTime;
        creatorFeePercentage = _creatorFeePercentage;
        protocolFeeSharePercentage = _protocolFeeSharePercentage;
        protocolFeeRecipient = _protocolFeeRecipient;
        eventCreator = _eventCreator;
        resolver = _resolver;
        pricingCurve = _pricingCurve;
    // state is now computed, no assignment needed
        
        // Initialize with virtual liquidity to maintain constant product formula
        yesSupply = INITIAL_LIQUIDITY;
        noSupply = INITIAL_LIQUIDITY;
        
        // Create market tokens
        yesToken = new MarketToken(string(abi.encodePacked("YES-", _question)), "YES");
        noToken = new MarketToken(string(abi.encodePacked("NO-", _question)), "NO");
    }
    
    /**
     * @dev Buy prediction tokens
     * @param amount Amount of base tokens (ETH/USDT) to spend
     * @param buyYes Whether to buy YES tokens (true) or NO tokens (false)
     */
    function buyTokens(uint256 amount, bool buyYes) external payable nonReentrant {
        if (getMarketState() != MarketState.Active) {
            if (getMarketState() == MarketState.TradingFrozen) {
                revert MarketTradingFrozen();
            } else {
                revert MarketNotActive();
            }
        }
        
        // Ensure sufficient payment
        if (msg.value < amount) revert InsufficientPayment();
        
        // Calculate fees first to determine net input amount
        uint256 totalCreatorFee = (amount * creatorFeePercentage) / 10000;
        uint256 protocolFee = (totalCreatorFee * protocolFeeSharePercentage) / 10000;
        uint256 creatorFee = totalCreatorFee - protocolFee;
        
        // Amount after fees deduction - this is used for token calculation
        uint256 netAmount = amount - totalCreatorFee;
        
        // Calculate tokens received using net amount (amount after fees)
        uint256 tokensReceived = pricingCurve.calculateExactInput(yesSupply, noSupply, netAmount, buyYes);
        
        // Update supplies
        if (buyYes) {
            yesSupply += tokensReceived;
            MarketToken(address(yesToken)).mint(msg.sender, tokensReceived);
        } else {
            noSupply += tokensReceived;
            MarketToken(address(noToken)).mint(msg.sender, tokensReceived);
        }
        
        // Distribute fees
        eventCreatorFees += creatorFee;
        
        // Send protocol fee immediately
        if (protocolFee > 0) {
            (bool success,) = protocolFeeRecipient.call{value: protocolFee}("");
            require(success, "Protocol fee transfer failed");
        }
        
        // Refund excess
        if (msg.value > amount) {
            (bool success,) = msg.sender.call{value: msg.value - amount}("");
            require(success, "Refund failed");
        }
        
        emit TokensPurchased(msg.sender, buyYes, tokensReceived, amount);
    }
    
    /**
     * @dev Sell prediction tokens
     * @param amount Amount of tokens to sell
     * @param sellYes Whether to sell YES tokens (true) or NO tokens (false)
     */
    function sellTokens(uint256 amount, bool sellYes) external nonReentrant {
        if (getMarketState() != MarketState.Active) {
            if (getMarketState() == MarketState.TradingFrozen) {
                revert MarketTradingFrozen();
            } else {
                revert MarketNotActive();
            }
        }
        
        // Check token balance
        ERC20 tokenToSell = sellYes ? yesToken : noToken;
        if (tokenToSell.balanceOf(msg.sender) < amount) revert InsufficientTokens();
        
        uint256 payout = pricingCurve.calculateSellPrice(yesSupply, noSupply, amount, sellYes);
        
        // Calculate fees
        uint256 totalCreatorFee = (payout * creatorFeePercentage) / 10000;
        uint256 protocolFee = (totalCreatorFee * protocolFeeSharePercentage) / 10000;
        uint256 creatorFee = totalCreatorFee - protocolFee;
        
        uint256 netPayout = payout - totalCreatorFee;
        
        // Update supplies and burn tokens
        if (sellYes) {
            yesSupply -= amount;
            MarketToken(address(yesToken)).burn(msg.sender, amount);
        } else {
            noSupply -= amount;
            MarketToken(address(noToken)).burn(msg.sender, amount);
        }
        
        // Distribute fees
        eventCreatorFees += creatorFee;
        
        // Send protocol fee immediately
        if (protocolFee > 0) {
            (bool feeSuccess,) = protocolFeeRecipient.call{value: protocolFee}("");
            require(feeSuccess, "Protocol fee transfer failed");
        }
        
        // Send payout to seller
        (bool payoutSuccess,) = msg.sender.call{value: netPayout}("");
        require(payoutSuccess, "Payout failed");
        
        emit TokensSold(msg.sender, sellYes, amount, netPayout);
    }
    
    /**
     * @dev Resolve the market
     * @param _outcome The outcome of the market (true = YES wins, false = NO wins)
     */
    function resolveMarket(bool _outcome) external {
        if (getMarketState() == MarketState.Active) {
            revert MarketNotFrozen();
        }
        if (getMarketState() != MarketState.TradingFrozen) {
            revert MarketAlreadyResolved();
        }
        if(msg.sender != address(resolver)) {
            revert UnauthorizedResolver();
        }
        outcome = _outcome;
        isResolved = true;
        emit MarketResolved(_outcome);
    }
    
    /**
     * @dev Redeem winning tokens for collateral assets
     */
    function redeemTokens() external nonReentrant {
        if (getMarketState() != MarketState.Resolved) revert MarketNotResolved();
        
        ERC20 winningToken = outcome ? yesToken : noToken;
        uint256 amount = winningToken.balanceOf(msg.sender);
        if (amount == 0) revert InsufficientTokens();
        
        // Calculate redemption value accounting for virtual liquidity
        uint256 winningSupply = outcome ? yesSupply : noSupply;
        uint256 actualTokensInCirculation = winningSupply - INITIAL_LIQUIDITY;
        
        // Proportional redemption based on actual tokens vs virtual tokens
        uint256 redemptionValue;
        if (actualTokensInCirculation > 0) {
            // Proportional share of available ETH (excluding virtual liquidity backing)
            redemptionValue = (amount * actualTokensInCirculation) / winningSupply;
        } else {
            // Edge case: no real tokens in circulation, no redemption value
            redemptionValue = 0;
        }
        
        // Burn tokens
        MarketToken(address(winningToken)).burn(msg.sender, amount);
        
        if (redemptionValue > 0) {
            (bool success,) = msg.sender.call{value: redemptionValue}("");
            require(success, "Redemption failed");
        }
        
        emit TokensRedeemed(msg.sender, redemptionValue);
    }
    
    /**
     * @dev Withdraw accumulated fees (only for event creator after resolution)
     */
    function withdrawFees() external {
        if (msg.sender != eventCreator) revert UnauthorizedResolver();
        if (getMarketState() != MarketState.Resolved) revert MarketNotResolved();
        if (feesWithdrawn) revert FeesAlreadyWithdrawn();
        if (eventCreatorFees == 0) revert NoFeesToWithdraw();
        
        uint256 fees = eventCreatorFees;
        feesWithdrawn = true;
        
        (bool success,) = eventCreator.call{value: fees}("");
        require(success, "Fee withdrawal failed");
        
        emit FeesWithdrawn(eventCreator, fees);
    }
    
    /**
     * @dev Get current token prices
     * @param amount Amount of tokens to price
     * @param buyYes Whether pricing YES tokens
     * @return price The price for the given amount
     */
    function getPrice(uint256 amount, bool buyYes) external view returns (uint256 price) {
        return pricingCurve.calculateBuyPrice(yesSupply, noSupply, amount, buyYes);
    }
    
    /**
     * @dev Modifier to update market state based on current time
     */
    /**
     * @dev Returns the current market state based on time and resolution
     */
    function getMarketState() public view returns (MarketState) {
        if (outcomeSet()) {
            return MarketState.Resolved;
        }
        if (block.timestamp >= endTime) {
            return MarketState.TradingFrozen;
        }
        return MarketState.Active;
    }

    /**
     * @dev Returns true if the market has been resolved
     */
    function outcomeSet() internal view returns (bool) {
        return isResolved;
    }
    
    // Receive function to accept ETH
    receive() external payable {}
}