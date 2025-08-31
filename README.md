# CrowdBet - Decentralized Prediction Markets

CrowdBet is a permissionless prediction market platform built with Solidity that enables anyone to create and trade on binary prediction markets. The platform uses a **Constant Product Market Maker (CPMM)** model with a **Complete Sets architecture** to ensure efficient price discovery and liquidity.

## 🏗️ Architecture Overview

### Core Components

1. **EventFactory**: Factory contract for creating prediction market events
2. **BinaryPredictionMarket**: Individual prediction market with CPMM mechanics
3. **FlareOracleResolver**: Oracle-based automatic resolution using Flare Network's FTSO v2
4. **FtsoV2Consumer**: Interface for consuming Flare oracle price feeds

### Complete Sets + CPMM Model

The platform implements a hybrid approach combining:

- **Complete Sets**: Every unit of collateral creates one YES token and one NO token
- **CPMM (Constant Product Market Maker)**: Uses `x * y = k` formula for token swaps
- **Automatic Arbitrage**: Prices self-correct through minting/burning mechanisms

This design ensures:
- ✅ Prices always sum to 1 (100% probability)
- ✅ No impermanent loss for liquidity providers
- ✅ Capital efficient trading
- ✅ Automatic liquidity through complete sets

## 🚀 Features

### For Event Creators
- **Permissionless Event Creation**: Anyone can create prediction markets
- **Flexible Configuration**: Set custom fees, durations, and seed collateral
- **Multiple Markets per Event**: Create complex events with multiple related questions
- **Manual or Oracle Resolution**: Choose between manual resolution or automatic oracle-based resolution

### For Traders
- **Buy YES/NO Tokens**: Purchase outcome tokens using ETH
- **Token Swapping**: Swap between YES and NO tokens anytime
- **Burn for Redemption**: Burn complete pairs (1 YES + 1 NO) to get 1 ETH back
- **Winning Token Redemption**: Redeem winning tokens 1:1 for ETH after resolution

### For Protocol
- **Fee Collection**: Configurable fees (up to 10%) split between resolver and protocol
- **Seed Collateral**: Initial liquidity to bootstrap trading
- **Emergency Controls**: Protocol admin controls for maximum fees

## 📊 Trading Mechanics

### Buying Tokens
When buying YES tokens with ETH:
1. Fee is deducted from ETH amount
2. Complete sets are minted (1 YES + 1 NO per remaining ETH)
3. Newly minted NO tokens are added to reserves
4. NO tokens are swapped for additional YES tokens via CPMM
5. User receives: minted YES + swapped YES tokens

### Price Discovery
- Token prices are determined by reserve ratios: `price_YES = reserveNO / (reserveYES + reserveNO)`
- Prices automatically adjust based on trading activity
- Arbitrage opportunities maintain price accuracy

### Resolution & Redemption
- Markets resolve to either YES or NO winning
- Winning token holders redeem 1:1 for ETH
- Losing tokens become worthless

## 🌐 Deployed Networks

| Network | Chain ID | Contract Address |
|---------|----------|------------------|
| Ethereum Sepolia | 11155111 | `0x6450031EC3DB3E802a753b03Ea7717F551AFACE7` |
| Lisk Sepolia | 4202 | `0x6450031EC3DB3E802a753b03Ea7717F551AFACE7` |
| Flare Coston2 | 114 | `0x00A5aa0d23fc66F5Fc07942c512Eb88485d6e583` |

## 🔧 Development Setup

### Prerequisites
- [Foundry](https://getfoundry.sh/)
- Git

### Installation
```bash
git clone https://github.com/your-repo/crowdbet-contracts
cd crowdbet-contracts
forge install
```

### Environment Setup
Copy the example environment file and configure:
```bash
cp env.example .env
# Edit .env with your configuration
```

Required environment variables:
```bash
PRIVATE_KEY=your_private_key
PROTOCOL_FEE_ADDRESS=protocol_fee_recipient_address
LOCAL_PRIVATE_KEY=local_development_key
LOCAL_PROTOCOL_FEE_ADDRESS=local_fee_address
NETWORK=network
```

### Testing
```bash
# Run all tests
forge test

# Run with verbosity
forge test -vvv

# Run specific test
forge test --match-test testCreateEvent
```

### Deployment
```bash
# Deploy to Sepolia
NETWORK=sepolia forge script script/DeployEventFactory.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast --verify

# Deploy to Coston2
NETWORK=coston2 forge script script/DeployEventFactory.s.sol --rpc-url $COSTON2_RPC_URL --broadcast

# Deploy to Lisk Sepolia
NETWORK=lisk forge script script/DeployEventFactory.s.sol --rpc-url $LISK_RPC_URL --broadcast
```

## 📋 Usage Examples

### Creating a Manual Resolution Event
```solidity
// Create market configuration
EventFactory.MarketConfig[] memory configs = new EventFactory.MarketConfig[](1);
configs[0] = EventFactory.MarketConfig({
    question: "Will ETH price be above $3000 by end of year?",
    duration: 30 days,
    fee: 500, // 5% fee in basis points
    seedCollateral: 1 ether
});

// Create event
(uint256 eventId, uint256[] memory marketIds) = eventFactory.createManualEvent{value: 1 ether}(
    "ETH Price Prediction",
    "Prediction market for ETH price at year end",
    configs
);
```

### Trading on a Market
```solidity
// Get market contract
BinaryPredictionMarket market = BinaryPredictionMarket(marketAddress);

// Buy YES tokens
market.buyYes{value: 0.1 ether}();

// Check balances
(uint256 yesBalance, uint256 noBalance) = market.getUserBalances(msg.sender);

// After resolution, redeem winning tokens
market.redeem();
```

### Oracle-Based Resolution (Flare Networks)
```solidity
// Create FlareOracleResolver for price-based resolution
FlareOracleResolver resolver = new FlareOracleResolver(
    oracleTokenId,    // e.g., FLR/USD feed ID
    marketAddress,    // Market to resolve
    3000,            // Threshold price
    ComparisonType.GreaterThan // YES wins if price > threshold
);

// Anyone can trigger resolution after market ends
resolver.resolve();
```

**Disclaimer**: This is experimental software. Use at your own risk. Always do your own research before trading on prediction markets.
