# Council Predictions - Foundry Project

Smart contract for The Council AI trading bots prediction market.

## Features

- ✅ Create predictions (PRICE, BOT_ROI, VOLUME, CUSTOM)
- ✅ Place bets (requires holding token)
- ✅ Bots can bet but **cannot bet on themselves** in BOT_ROI predictions
- ✅ Resolve predictions (by oracle)
- ✅ Support for ties (split payout)
- ✅ Claim winnings / refunds
- ✅ Platform fee (2.5%)
- ✅ Comprehensive view functions

## Setup

```bash
# Install dependencies
forge install OpenZeppelin/openzeppelin-contracts
forge install foundry-rs/forge-std

# Build
forge build

# Test
forge test -vvv

# Test with gas report
forge test --gas-report
```

## Environment Variables

Create a `.env` file:

```env
# Deployer
PRIVATE_KEY=0x...

# RPC
MONAD_RPC_URL=https://testnet-rpc.monad.xyz

# Bot wallets
BOT_CHAD_ADDRESS=0x...
BOT_QUANTUM_ADDRESS=0x...
BOT_SENSEI_ADDRESS=0x...
BOT_STERLING_ADDRESS=0x...
BOT_ORACLE_ADDRESS=0x...

# Oracle (backend resolver)
ORACLE_ADDRESS=0x...

# After deployment
PREDICTIONS_CONTRACT=0x...
TOKEN_ADDRESS=0x...
```

## Deployment

### Simple deployment (just contract)

```bash
source .env
forge script script/Deploy.s.sol:DeployCouncilPredictionsSimple \
  --rpc-url $MONAD_RPC_URL \
  --broadcast \
  --verify
```

### Full deployment (with bot registration)

```bash
source .env
forge script script/Deploy.s.sol:DeployCouncilPredictions \
  --rpc-url $MONAD_RPC_URL \
  --broadcast \
  --verify
```

### Register bots (after deployment)

```bash
source .env
forge script script/Deploy.s.sol:RegisterBots \
  --rpc-url $MONAD_RPC_URL \
  --broadcast
```

### Create test prediction

```bash
source .env
forge script script/Deploy.s.sol:CreateTestPrediction \
  --rpc-url $MONAD_RPC_URL \
  --broadcast
```

## Contract Functions

### Core

| Function | Description |
|----------|-------------|
| `createPrediction(token, question, type, duration, options)` | Create new prediction |
| `placeBet(predictionId, optionId)` | Place a bet (payable) |
| `resolvePrediction(id, winner)` | Resolve (oracle only) |
| `resolvePrediction(id, winner, isTie, tiedOptions)` | Resolve with tie |
| `claimWinnings(predictionId)` | Claim your winnings |
| `claimRefund(predictionId)` | Claim refund (if cancelled) |

### Bot Management

| Function | Description |
|----------|-------------|
| `registerBot(wallet, botId, optionId)` | Register a bot |
| `unregisterBot(wallet)` | Unregister a bot |
| `isBot(wallet)` | Check if address is bot |
| `getBotOptionId(wallet)` | Get bot's option ID |
| `canBotBetOnOption(bot, predictionId, optionId)` | Check if bot can bet on option |

### View Functions

| Function | Description |
|----------|-------------|
| `getPrediction(id)` | Get prediction + options |
| `getPredictionFull(id)` | Get full prediction view |
| `getLatestPredictions(count)` | Get latest N predictions |
| `getActivePredictions(offset, limit)` | Get active predictions |
| `getUserBet(user, predictionId)` | Get user's bet |
| `getUserBets(user)` | Get all user's bets |
| `getUserStats(user)` | Get user statistics |
| `getClaimablePredictions(user)` | Get claimable prediction IDs |
| `getAllOdds(predictionId)` | Get all odds |
| `canBet(user, predictionId)` | Check if user can bet |
| `canBetDetailed(user, predictionId)` | Check with reason |
| `getGlobalStats()` | Get global statistics |
| `getRegisteredBots()` | Get all registered bots |

## Bot Betting Rules

1. Bots are exempt from token holding requirement
2. In **BOT_ROI** predictions, bots **cannot bet on themselves**
3. In other prediction types (PRICE, VOLUME, CUSTOM), bots can bet freely

### Example

```
BOT_ROI Prediction: "Which bot wins this week?"
Options: [1: James, 2: Keone, 3: Portdev, 4: Harpal, 5: Mike]

Bot "James" (optionId=1) can bet on options 2,3,4,5 ✅
Bot "James" cannot bet on option 1 ❌ (himself)
```

## Tests

```bash
# Run all tests
forge test

# Run specific test
forge test --match-test test_BotCannotBetOnSelf -vvv

# Run with coverage
forge coverage
```

## Gas Estimates

| Function | Gas |
|----------|-----|
| createPrediction | ~250,000 |
| placeBet | ~150,000 |
| resolvePrediction | ~80,000 |
| claimWinnings | ~70,000 |

## Security Considerations

- ReentrancyGuard on all state-changing functions
- Custom errors for gas efficiency
- Oracle-only resolution
- Owner-only admin functions
- Bot self-bet prevention
# the-council-contracts
