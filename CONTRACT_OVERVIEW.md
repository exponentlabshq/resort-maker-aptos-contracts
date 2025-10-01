# Resort Maker Smart Contracts Overview

## System Architecture

The Resort Maker dApp uses **three interconnected smart contracts** that work together to create a complete investment and rewards ecosystem on Aptos:

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Launchpad     │    │ Resort Registry │    │ Resort Staking  │
│                 │    │                 │    │                 │
│ • Create tokens │    │ • Manage        │    │ • Stake RESORT  │
│ • Mint RESORT   │◄──►│   properties    │◄──►│   tokens        │
│ • Mint TIME     │    │ • Track         │    │ • Earn TIME     │
│                 │    │   investments   │    │   rewards       │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Contract Responsibilities

### 1. Launchpad Contract (`launchpad.move`)

**Purpose**: Token creation and minting infrastructure

- Creates RESORT investment tokens ($1 each, 10M max supply)
- Creates TIME reward tokens (earned through staking)
- Handles token permissions and configurations
- Manages admin controls and fee collection

### 2. Resort Registry Contract (`resort_registry.move`)

**Purpose**: Property management and investment tracking

- Admin creates resort property listings
- Stores resort metadata (name, location, images, investment targets)
- Tracks total investment amounts per resort
- Records individual investor participation
- Maintains resort status (active/inactive)

### 3. Resort Staking Contract (`resort_staking.move`)

**Purpose**: Investment mechanism and rewards distribution

- Users stake RESORT tokens in specific resorts
- Calculates TIME token rewards (1 TIME per second per RESORT staked)
- Manages individual stake tracking with unique IDs
- Handles claiming rewards and unstaking
- Coordinates with registry to record investments

## Token Economics

### RESORT Token (Investment)

- **Symbol**: RESORT
- **Price**: $1 USD per token (fixed for hackathon)
- **Supply**: 10,000,000 maximum
- **Decimals**: 6 (1 RESORT = 1,000,000 smallest units)
- **Use**: Primary investment currency for resort properties

### TIME Token (Rewards)

- **Symbol**: TIME
- **Earning Rate**: 1 TIME per second per RESORT staked
- **Decimals**: 6 (1 TIME = 1,000,000 smallest units)
- **Use**: Rewards for staking, future booking discounts

## User Flow

### 1. Token Acquisition

```move
// User mints RESORT tokens through launchpad
launchpad::mint_fa(sender, resort_token_object, amount)
```

### 2. Resort Investment

```move
// User stakes RESORT in chosen resort
resort_staking::stake_in_resort(sender, resort_id, amount)
```

### 3. Earn Rewards

```move
// Automatic TIME accumulation, manual claiming
resort_staking::claim_rewards(sender)
```

### 4. Portfolio Management

```move
// View staking info and unstake when desired
resort_staking::unstake(sender, stake_id)
```

## Key Features

### Multi-Resort Investment

- Users can stake in multiple resorts simultaneously
- Each stake tracked with unique ID for precise management
- Portfolio diversification across different properties

### Real-Time Rewards

- TIME tokens accumulate every second automatically
- Rewards calculated based on stake amount and time duration
- Claim rewards anytime without unstaking principal

### Investment Tracking

- Cross-contract coordination between staking and registry
- Transparent tracking of total invested amounts per resort
- Individual investor records for future features

### Admin Controls

- Resort creation restricted to admin for quality control
- Token configuration management through launchpad
- Emergency controls for system maintenance

## Security Features

### Access Control

- Admin-only resort creation prevents spam
- User-owned stake management prevents unauthorized access
- Protected token transfers through Aptos framework

### Data Integrity

- Investment amounts recorded in both staking and registry contracts
- Immutable resort metadata once created
- Precise reward calculations with overflow protection

### Error Handling

- Comprehensive validation for all user inputs
- Clear error messages for debugging and user feedback
- Balance checks before all token operations

## Integration Points

### Frontend Integration

- TypeScript wrapper functions for all contract calls
- Real-time view functions for portfolio data
- Event listening for transaction confirmations

### Wallet Integration

- Seamless Aptos Connect integration
- Primary fungible store token management
- Gas-efficient transaction patterns

## Deployment Strategy

### Setup Sequence

1. Deploy all three contracts to Aptos testnet
2. Initialize launchpad with admin permissions
3. Create RESORT and TIME tokens via launchpad
4. Configure staking contract with token addresses
5. Create initial resort properties for demo
6. Set frontend environment variables

### Environment Configuration

```typescript
VITE_MODULE_ADDRESS=0x... // Deployed contract address
VITE_RESORT_TOKEN_ADDRESS=0x... // RESORT token object
VITE_TIME_TOKEN_ADDRESS=0x... // TIME token object
```

## Future Enhancements

### Post-Hackathon Features

- Dynamic token pricing based on supply/demand
- Semi-fungible NFTs for individual property ownership
- TIME token utility for booking discounts
- Governance features for community resort selection
- Cross-chain bridge integration for broader adoption

### Scalability Improvements

- Batch operations for multiple investments
- Optimized reward calculation algorithms
- Advanced staking strategies (lock periods, bonus rates)
- Integration with external property valuation oracles

---

_This contract system provides a complete foundation for the Resort Maker hackathon submission while maintaining simplicity and extensibility for future development._
