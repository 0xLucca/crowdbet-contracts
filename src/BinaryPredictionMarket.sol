// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract BinaryPredictionMarket {
    //TODO: BLOCK TRADING WHEN MARKET IS RESOLVED
    // --- Config / Global State ---
    address public immutable resolver;   // address that can resolve the market
    uint256 public immutable fee;        // fee in basis points (100 = 1%)
    string  public question;             // market question
    uint256 public endTime;              // when market ends
    
    bool    public resolved;
    bool    public yesWon;               // result when resolved == true
    
    // Vault (collateral locked to pay winner)
    uint256 public vault;                // in wei
    
    // Pool reserves (AMM CPMM)
    uint256 public reserveYES;           // x
    uint256 public reserveNO;            // y
    
    // User balances (internal ledger, not ERC20)
    mapping(address => uint256) public yesBalance;
    mapping(address => uint256) public noBalance;

    address immutable public protocolFeeRecipient;

    // --- Events ---
    event MarketCreated(string question, address resolver, uint256 fee, uint256 endTime);
    event Seeded(uint256 seed, uint256 x, uint256 y, uint256 vault);
    event BuyYes(address indexed user, uint256 collateralIn, uint256 yesMinted, uint256 yesFromSwap, uint256 newX, uint256 newY, uint256 newVault);
    event BuyNo(address indexed user, uint256 collateralIn, uint256 noMinted, uint256 noFromSwap, uint256 newX, uint256 newY, uint256 newVault);
    event Swap(address indexed user, bool noToYes, uint256 amountIn, uint256 amountOut, uint256 newX, uint256 newY);
    event BurnPairs(address indexed user, uint256 amount, uint256 newVault);
    event Resolved(bool yesWon);
    event Redeemed(address indexed user, bool yesSide, uint256 amount, uint256 newVault);
    
    modifier onlyResolver() {
        require(msg.sender == resolver, "Not resolver");
        _;
    }
    
    modifier notResolved() {
        require(!resolved, "Market resolved");
        _;
    }
    
    modifier marketActive() {
        require(block.timestamp < endTime, "Market ended");
        _;
    }
    
    constructor(
        string memory _question,
        address _resolver, 
        uint256 _fee,
        uint256 _duration,
        uint256 _seedCollateral,
        address _protocolFeeRecipient
    ) payable {
        require(_fee <= 1000, "Fee too high"); // Max 10%
        require(_resolver != address(0), "Invalid resolver");
        require(_duration > 0, "Invalid duration");
        require(msg.value >= _seedCollateral, "Insufficient seed");
        
        question = _question;
        resolver = _resolver;
        fee = _fee;
        endTime = block.timestamp + _duration;
        protocolFeeRecipient = _protocolFeeRecipient;

        // Initial seeding
        if (_seedCollateral > 0) {
            _seed(_seedCollateral);
        }
        
        emit MarketCreated(_question, _resolver, _fee, endTime);
    }
    
    /// @notice Seeds the market with initial liquidity
    function _seed(uint256 amount) internal {
        vault += amount;
        reserveYES += amount;
        reserveNO += amount;
        
        emit Seeded(amount, reserveYES, reserveNO, vault);
    }
    
    /// @notice Buy YES tokens by minting pairs and swapping NO to YES
    function buyYes() external payable notResolved marketActive {
        require(msg.value > 0, "Need ETH");
        
        uint256 collateralIn = msg.value;
        uint256 feeAmount = (collateralIn * fee) / 10000;
        uint256 netCollateral = collateralIn - feeAmount;
        
        // Mint complete pairs (1 YES + 1 NO per wei)
        vault += netCollateral;
        uint256 yesMinted = netCollateral;
        uint256 noMinted = netCollateral;
        
        // Add minted NO to reserves
        reserveNO += noMinted;
        
        // Swap NO for YES in the pool
        uint256 yesFromSwap = _swapNoForYes(noMinted);
        
        // User gets: minted YES + swapped YES
        yesBalance[msg.sender] += yesMinted + yesFromSwap;
        
        emit BuyYes(msg.sender, collateralIn, yesMinted, yesFromSwap, reserveYES, reserveNO, vault);
    }
    
    /// @notice Buy NO tokens by minting pairs and swapping YES to NO
    function buyNo() external payable notResolved marketActive {
        require(msg.value > 0, "Need ETH");
        
        uint256 collateralIn = msg.value;
        uint256 feeAmount = (collateralIn * fee) / 10000;
        uint256 netCollateral = collateralIn - feeAmount;
        
        // Mint complete pairs (1 YES + 1 NO per wei)
        vault += netCollateral;
        uint256 yesMinted = netCollateral;
        uint256 noMinted = netCollateral;
        
        // Add minted YES to reserves
        reserveYES += yesMinted;
        
        // Swap YES for NO in the pool
        uint256 noFromSwap = _swapYesForNo(yesMinted);
        
        // User gets: minted NO + swapped NO
        noBalance[msg.sender] += noMinted + noFromSwap;
        
        emit BuyNo(msg.sender, collateralIn, noMinted, noFromSwap, reserveYES, reserveNO, vault);
    }
    
    /// @notice Swap YES tokens for NO tokens
    function swapYesToNo(uint256 yesAmount) external notResolved marketActive {
        require(yesBalance[msg.sender] >= yesAmount, "Insufficient YES");
        require(yesAmount > 0, "Amount must be > 0");
        
        yesBalance[msg.sender] -= yesAmount;
        uint256 noOut = _swapYesForNo(yesAmount);
        noBalance[msg.sender] += noOut;
        
        emit Swap(msg.sender, false, yesAmount, noOut, reserveYES, reserveNO);
    }
    
    /// @notice Swap NO tokens for YES tokens
    function swapNoToYes(uint256 noAmount) external notResolved marketActive {
        require(noBalance[msg.sender] >= noAmount, "Insufficient NO");
        require(noAmount > 0, "Amount must be > 0");
        
        noBalance[msg.sender] -= noAmount;
        uint256 yesOut = _swapNoForYes(noAmount);
        yesBalance[msg.sender] += yesOut;
        
        emit Swap(msg.sender, true, noAmount, yesOut, reserveYES, reserveNO);
    }
    
    /// @notice Burn complete pairs (1 YES + 1 NO) to get 1 wei back
    function burnPairs(uint256 amount) external notResolved {
        require(amount > 0, "Amount must be > 0");
        require(yesBalance[msg.sender] >= amount, "Insufficient YES");
        require(noBalance[msg.sender] >= amount, "Insufficient NO");
        require(vault >= amount, "Insufficient vault");
        
        // Burn tokens
        yesBalance[msg.sender] -= amount;
        noBalance[msg.sender] -= amount;
        
        // Return collateral from vault
        vault -= amount;
        
        payable(msg.sender).transfer(amount);
        
        emit BurnPairs(msg.sender, amount, vault);
    }
    
    /// @notice Resolve the market (only resolver can call)
    function resolve(bool _yesWon) external onlyResolver {
        require(!resolved, "Already resolved");
        require(block.timestamp >= endTime, "Market not ended");
        
        resolved = true;
        yesWon = _yesWon;
        
        emit Resolved(_yesWon);
    }
    
    /// @notice Redeem winning tokens for ETH (1:1 ratio)
    function redeem() external {
        require(resolved, "Not resolved");
        
        uint256 winningTokens;
        if (yesWon) {
            winningTokens = yesBalance[msg.sender];
            yesBalance[msg.sender] = 0;
        } else {
            winningTokens = noBalance[msg.sender];
            noBalance[msg.sender] = 0;
        }
        
        require(winningTokens > 0, "No winning tokens");
        require(vault >= winningTokens, "Insufficient vault");
        
        vault -= winningTokens;
        payable(msg.sender).transfer(winningTokens);
        
        emit Redeemed(msg.sender, yesWon, winningTokens, vault);
    }
    
    // --- Internal AMM functions ---
    
    /// @dev Swap YES for NO using constant product formula
    function _swapYesForNo(uint256 yesIn) internal returns (uint256 noOut) {
        require(reserveYES > 0 && reserveNO > 0, "No liquidity");
        
        // x * y = k, so: noOut = y - k/(x + yesIn)
        uint256 k = reserveYES * reserveNO;
        uint256 newReserveYES = reserveYES + yesIn;
        uint256 newReserveNO = k / newReserveYES;
        
        noOut = reserveNO - newReserveNO;
        require(noOut > 0, "Insufficient output");
        
        reserveYES = newReserveYES;
        reserveNO = newReserveNO;
        
        return noOut;
    }
    
    /// @dev Swap NO for YES using constant product formula
    function _swapNoForYes(uint256 noIn) internal returns (uint256 yesOut) {
        require(reserveYES > 0 && reserveNO > 0, "No liquidity");
        
        // x * y = k, so: yesOut = x - k/(y + noIn)
        uint256 k = reserveYES * reserveNO;
        uint256 newReserveNO = reserveNO + noIn;
        uint256 newReserveYES = k / newReserveNO;
        
        yesOut = reserveYES - newReserveYES;
        require(yesOut > 0, "Insufficient output");
        
        reserveYES = newReserveYES;
        reserveNO = newReserveNO;
        
        return yesOut;
    }
    
    // --- View functions ---
    
    /// @notice Get current market state
    function getMarketInfo() external view returns (
        string memory _question,
        address _resolver,
        uint256 _fee,
        uint256 _endTime,
        bool _resolved,
        bool _yesWon,
        uint256 _vault,
        uint256 _reserveYES,
        uint256 _reserveNO
    ) {
        return (question, resolver, fee, endTime, resolved, yesWon, vault, reserveYES, reserveNO);
    }
    
    /// @notice Get user balances
    function getUserBalances(address user) external view returns (uint256 yes, uint256 no) {
        return (yesBalance[user], noBalance[user]);
    }
    
    /// @notice Calculate current implied probability (YES price)
    function getYesPrice() external view returns (uint256) {
        if (reserveYES == 0 || reserveNO == 0) return 0;
        // Price = opposite reserve / total reserves
        return (reserveNO * 1e18) / (reserveYES + reserveNO);
    }
    
    /// @notice Calculate how much YES you'd get for buying with ETH amount
    function previewBuyYes(uint256 ethAmount) external view returns (uint256 yesOut) {
        if (ethAmount == 0) return 0;
        
        uint256 feeAmount = (ethAmount * fee) / 10000;
        uint256 netAmount = ethAmount - feeAmount;
        
        if (reserveYES == 0 || reserveNO == 0) {
            return netAmount * 2; // If no liquidity, you get 2:1 (minted + no swap loss)
        }
        
        // Simulate: mint pairs, add NO to reserves, swap NO for YES
        uint256 newReserveNO = reserveNO + netAmount;
        uint256 k = reserveYES * reserveNO;
        uint256 newReserveYES = k / newReserveNO;
        uint256 yesFromSwap = reserveYES - newReserveYES;
        
        return netAmount + yesFromSwap; // minted + swapped
    }
    
    /// @notice Calculate how much NO you'd get for buying with ETH amount
    function previewBuyNo(uint256 ethAmount) external view returns (uint256 noOut) {
        if (ethAmount == 0) return 0;
        
        uint256 feeAmount = (ethAmount * fee) / 10000;
        uint256 netAmount = ethAmount - feeAmount;
        
        if (reserveYES == 0 || reserveNO == 0) {
            return netAmount * 2; // If no liquidity, you get 2:1
        }
        
        // Simulate: mint pairs, add YES to reserves, swap YES for NO
        uint256 newReserveYES = reserveYES + netAmount;
        uint256 k = reserveYES * reserveNO;
        uint256 newReserveNO = k / newReserveYES;
        uint256 noFromSwap = reserveNO - newReserveNO;
        
        return netAmount + noFromSwap; // minted + swapped
    }
    
    /// @notice Emergency function to allow resolver to withdraw fees
    function withdrawFees() external onlyResolver {
        uint256 balance = address(this).balance;
        uint256 feesAvailable = balance - vault;
        require(feesAvailable > 0, "No fees to withdraw");

        // Transfer half to the protocol fee recipient
        uint256 half = feesAvailable / 2;
        {
            (bool success, ) = payable(protocolFeeRecipient).call{value: half}("");
            require(success, "Transfer failed");
        }
        

        // Transfer the other half to the resolver
        {
            (bool success, ) = payable(resolver).call{value: half}("");
            require(success, "Transfer failed");
        }
    }
}