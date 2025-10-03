# Per-Resort Staking Implementation Summary

## Overview

Updated the staking system to support per-resort staking/unstaking with proper resort funding tracking. Users can now stake into individual resorts and unstake from them selectively or all at once.

## Key Changes

### 1. Data Structure Changes (`resort_staking.move`)

**Before:** Single global stake per user

```move
struct StakeInfo has store, drop {
    amount: u64,
    last_claim_time: u64,
    resort_id: u64,
}
```

**After:** Per-resort stakes per user

```move
struct StakeInfo has store, drop {
    amount: u64,
    last_claim_time: u64,
}

struct UserStakes has key {
    stakes: Table<u64, StakeInfo>,
}
```

### 2. Staking Flow

**User stakes into resort:**

1. `stake_in_resort(resort_id, amount)` - User stakes RESORT tokens
2. Tokens transferred to vault
3. User's stake record created/updated for that specific resort
4. `resort_registry::record_investment()` called
5. Resort's `current_investment` increased
6. Resort's investor tracking updated
7. `StakeEvent` emitted

### 3. Unstaking Flow

**User unstakes from resort:**

1. `unstake_from_resort(resort_id, amount)` - User unstakes specific amount from specific resort
2. Validates user has sufficient stake in that resort
3. Calculates and pays pending rewards (TIME tokens)
4. Updates user's stake (or removes if fully unstaked)
5. `resort_registry::remove_investment()` called
6. Resort's `current_investment` decreased
7. Resort's investor tracking updated
8. Tokens returned from vault to user
9. `UnstakeEvent` emitted

**User unstakes from all resorts:**

1. `unstake_all()` - Unstakes all stakes from all resorts
2. Iterates through all user's staked resorts
3. Calls `unstake_from_resort()` for each

## Entry Functions (Public API)

### Staking Module (`resort_staking.move`)

```move
// Admin functions
public entry fun set_resort_token(sender: &signer, resort_token: Object<Metadata>)
public entry fun set_time_token(sender: &signer, time_token: Object<Metadata>)

// User functions
public entry fun stake_in_resort(sender: &signer, resort_id: u64, amount: u64)
public entry fun unstake_from_resort(sender: &signer, resort_id: u64, amount: u64)
public entry fun unstake_all(sender: &signer)
public entry fun claim_rewards(sender: &signer)
```

### Resort Registry Module (`resort_registry.move`)

```move
// Admin functions
public entry fun create_resort(
    sender: &signer,
    name: String,
    location: String,
    description: String,
    image_uri: String,
    total_investment_needed: u64,
    minimum_investment: u64,
)

// Internal functions (called by staking module)
public fun record_investment(resort_id: u64, investor: address, amount: u64)
public fun remove_investment(resort_id: u64, investor: address, amount: u64)
```

## View Functions

### Staking Module

```move
#[view]
public fun get_user_total_staked(user: address): u64
// Returns total amount staked across all resorts

#[view]
public fun get_user_stake_in_resort(user: address, resort_id: u64): u64
// Returns amount staked in specific resort

#[view]
public fun get_pending_rewards(user: address): u64
// Returns total pending TIME token rewards across all stakes

#[view]
public fun get_pending_rewards_for_resort(user: address, resort_id: u64): u64
// Returns pending rewards for specific resort stake

#[view]
public fun get_total_staked(): u64
// Returns global total staked across all resorts

#[view]
public fun get_vault_address(): address
// Returns the resource account address holding staked tokens

#[view]
public fun get_user_staked_resorts(user: address): vector<u64>
// Returns list of all resort IDs user has staked in
```

### Resort Registry Module

```move
#[view]
public fun get_resort(resort_id: u64): (String, String, String, String, u64, u64, u64, bool)
// Returns: (name, location, description, image_uri, total_needed, min_investment, current_investment, is_active)

#[view]
public fun get_all_resort_ids(): vector<u64>
// Returns list of all resort IDs

#[view]
public fun get_investor_amount(resort_id: u64, investor: address): u64
// Returns specific investor's investment in a resort

#[view]
public fun get_resort_count(): u64
// Returns total number of resorts
```

## Events

### Staking Events

- `StakeEvent`: Emitted when user stakes into a resort
- `UnstakeEvent`: Emitted when user unstakes from a resort
- `ClaimRewardsEvent`: Emitted when user claims rewards

### Resort Registry Events

- `ResortCreatedEvent`: Emitted when new resort is created
- `ResortInvestmentEvent`: Emitted when investment is added to resort
- `ResortWithdrawalEvent`: Emitted when investment is removed from resort

## Error Handling

### Staking Errors

- `EINVALID_STAKE_AMOUNT`: Stake amount must be > 0
- `EINSUFFICIENT_BALANCE`: User doesn't have enough RESORT tokens
- `ENO_STAKE_FOUND`: No stake found for user
- `ERESORT_TOKEN_NOT_SET`: RESORT token not configured
- `ETIME_TOKEN_NOT_SET`: TIME token not configured
- `EINVALID_RESORT_ID`: Resort ID must be > 0

### Resort Registry Errors

- `EONLY_ADMIN_CAN_CREATE_RESORT`: Only admin can create resorts
- `ERESORT_NOT_FOUND`: Resort doesn't exist
- `EINVALID_INVESTMENT_AMOUNT`: Investment below minimum (first-time investors only)
- `ERESORT_NOT_ACTIVE`: Resort is not active for new investments
- `EINSUFFICIENT_INVESTMENT_BALANCE`: Trying to withdraw more than invested

## Key Features

### ✅ Per-Resort Staking

- Users can stake into multiple resorts simultaneously
- Each resort tracks individual stakes separately
- Rewards calculated independently per resort

### ✅ Flexible Unstaking

- Unstake specific amounts from specific resorts
- Unstake from all resorts at once
- Partial unstaking supported

### ✅ Resort Funding Tracking

- Resort's `current_investment` accurately reflects staked amounts
- Increases when users stake
- Decreases when users unstake
- Individual investor amounts tracked per resort

### ✅ Reward System

- TIME tokens earned based on staked amount × time
- Rate: 1 TIME token per second per RESORT token staked
- Rewards claimed across all stakes or automatically on unstake
- Last claim time tracked per resort

### ✅ Minimum Investment Logic

- Minimum investment only enforced for first-time investors in a resort
- Existing investors can add any amount to their stake
- Prevents small dust investments while allowing flexible additions

## Important Notes

1. **UserStakes Resource**: Each user gets a `UserStakes` resource on first stake, stored at their address
2. **Vault Address**: Staked tokens held in resource account at `create_resource_address(@launchpad_addr, b"resort_staking_v1")`
3. **Hackathon Optimization**: `get_user_resort_stakes_internal()` searches up to 1000 resort IDs. For production, maintain an explicit vector of staked resort IDs
4. **Reward Calculation**: Uses 6 decimal places for both RESORT and TIME tokens
5. **Admin Setup**: Admin must call `set_resort_token()` and `set_time_token()` after deploying contracts

## Testing Checklist

- [ ] Stake into single resort
- [ ] Stake into multiple resorts
- [ ] Add to existing stake in resort
- [ ] Unstake partial amount from resort
- [ ] Unstake full amount from resort
- [ ] Unstake from all resorts
- [ ] Claim rewards
- [ ] Verify resort `current_investment` updates correctly on stake
- [ ] Verify resort `current_investment` updates correctly on unstake
- [ ] Verify minimum investment enforced for new investors only
- [ ] Check all view functions return correct values
- [ ] Verify events are emitted correctly
