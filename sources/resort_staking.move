module launchpad_addr::resort_staking {
    use std::option::{Self, Option};
    use std::signer;
    
    use aptos_std::table::{Self, Table};
    use aptos_framework::event;
    use aptos_framework::fungible_asset::Metadata;
    use aptos_framework::object::Object;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;
    use aptos_framework::account::{Self, SignerCapability};
    
    use launchpad_addr::resort_registry;
    use launchpad_addr::launchpad;

    /// Errors
    /// Invalid stake amount
    const EINVALID_STAKE_AMOUNT: u64 = 1;
    /// Insufficient balance
    const EINSUFFICIENT_BALANCE: u64 = 2;
    /// No stake found
    const ENO_STAKE_FOUND: u64 = 3;
    /// Resort token not set
    const ERESORT_TOKEN_NOT_SET: u64 = 4;
    /// Time token not set
    const ETIME_TOKEN_NOT_SET: u64 = 5;
    /// Invalid resort ID
    const EINVALID_RESORT_ID: u64 = 6;

    /// Constants
    const TIME_REWARD_RATE_PER_SECOND: u64 = 1; // 1 TIME token per second per RESORT token staked
    const RESORT_TOKEN_DECIMALS: u8 = 6; // 1 RESORT = 1,000,000 smallest units
    const TIME_TOKEN_DECIMALS: u8 = 6; // 1 TIME = 1,000,000 smallest units

    #[event]
    struct StakeEvent has store, drop {
        staker: address,
        resort_id: u64,
        amount: u64,
        timestamp: u64,
    }

    #[event]
    struct UnstakeEvent has store, drop {
        staker: address,
        resort_id: u64,
        amount: u64,
        rewards_earned: u64,
        timestamp: u64,
    }

    #[event]
    struct ClaimRewardsEvent has store, drop {
        staker: address,
        rewards_claimed: u64,
        timestamp: u64,
    }

    /// Individual stake information
    struct StakeInfo has store, drop {
        amount: u64,
        last_claim_time: u64,
        resort_id: u64,
    }

    /// Global staking configuration and state
    struct StakingConfig has key {
        resort_token: Option<Object<Metadata>>,
        time_token: Option<Object<Metadata>>,
        total_staked: u64,
        // Simplified: user_address -> StakeInfo (one stake per user for hackathon)
        user_stakes: Table<address, StakeInfo>,
        admin: address,
        signer_cap: SignerCapability,
    }

    /// Initialize staking module
    fun init_module(sender: &signer) {
        // Create a resource account to hold staked tokens
        let (_resource_signer, signer_cap) = account::create_resource_account(sender, b"resort_staking_v1");
        
        move_to(sender, StakingConfig {
            resort_token: option::none(),
            time_token: option::none(),
            total_staked: 0,
            user_stakes: table::new(),
            admin: signer::address_of(sender),
            signer_cap,
        });
    }

    /// Set the RESORT token (admin only)
    public entry fun set_resort_token(
        sender: &signer,
        resort_token: Object<Metadata>,
    ) acquires StakingConfig {
        let sender_addr = signer::address_of(sender);
        let config = borrow_global_mut<StakingConfig>(@launchpad_addr);
        assert!(sender_addr == config.admin, ERESORT_TOKEN_NOT_SET);
        config.resort_token = option::some(resort_token);
    }

    /// Set the TIME token (admin only)
    public entry fun set_time_token(
        sender: &signer,
        time_token: Object<Metadata>,
    ) acquires StakingConfig {
        let sender_addr = signer::address_of(sender);
        let config = borrow_global_mut<StakingConfig>(@launchpad_addr);
        assert!(sender_addr == config.admin, ETIME_TOKEN_NOT_SET);
        config.time_token = option::some(time_token);
    }

    /// Stake RESORT tokens in a specific resort
    public entry fun stake_in_resort(
        sender: &signer,
        resort_id: u64,
        amount: u64,
    ) acquires StakingConfig {
        let sender_addr = signer::address_of(sender);
        let config = borrow_global_mut<StakingConfig>(@launchpad_addr);
        
        assert!(option::is_some(&config.resort_token), ERESORT_TOKEN_NOT_SET);
        assert!(amount > 0, EINVALID_STAKE_AMOUNT);

        let resort_token = *option::borrow(&config.resort_token);
        
        // Check if user has enough RESORT tokens
        let user_balance = primary_fungible_store::balance(sender_addr, resort_token);
        assert!(user_balance >= amount, EINSUFFICIENT_BALANCE);

        // Transfer RESORT tokens to the resource account vault
        let vault_addr = get_vault_address();
        primary_fungible_store::transfer(sender, resort_token, vault_addr, amount);

        // Create or update stake entry (accumulate if user already has a stake)
        let stake_info = if (table::contains(&config.user_stakes, sender_addr)) {
            let existing_stake = table::remove(&mut config.user_stakes, sender_addr);
            StakeInfo {
                amount: existing_stake.amount + amount, // Accumulate stakes
                last_claim_time: existing_stake.last_claim_time, // Keep original claim time
                resort_id, // Update to latest resort (or we could keep original)
            }
        } else {
            StakeInfo {
                amount,
                last_claim_time: timestamp::now_seconds(),
                resort_id,
            }
        };

        table::add(&mut config.user_stakes, sender_addr, stake_info);
        config.total_staked = config.total_staked + amount;

        // Record investment in resort registry
        resort_registry::record_investment(resort_id, sender_addr, amount);

        event::emit(StakeEvent {
            staker: sender_addr,
            resort_id,
            amount,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Claim TIME token rewards for all stakes
    public entry fun claim_rewards(sender: &signer) acquires StakingConfig {
        let sender_addr = signer::address_of(sender);
        let config = borrow_global_mut<StakingConfig>(@launchpad_addr);
        
        assert!(option::is_some(&config.time_token), ETIME_TOKEN_NOT_SET);
        assert!(table::contains(&config.user_stakes, sender_addr), ENO_STAKE_FOUND);

        let time_token = *option::borrow(&config.time_token);
        let current_time = timestamp::now_seconds();

        // Calculate rewards for user's stake
        let stake_info = table::borrow_mut(&mut config.user_stakes, sender_addr);
        let time_staked = current_time - stake_info.last_claim_time;
        let total_rewards = (stake_info.amount * time_staked * TIME_REWARD_RATE_PER_SECOND) / 1000000; // Adjust for decimals
        
        // Update last claim time
        stake_info.last_claim_time = current_time;

        if (total_rewards > 0) {
            // Mint TIME tokens to user using launchpad's mint capability
            launchpad::mint_to(time_token, sender_addr, total_rewards);
            
            event::emit(ClaimRewardsEvent {
                staker: sender_addr,
                rewards_claimed: total_rewards,
                timestamp: current_time,
            });
        };
    }

    /// Unstake all RESORT tokens
    public entry fun unstake(sender: &signer) acquires StakingConfig {
        let sender_addr = signer::address_of(sender);
        
        // Get module signer first to avoid borrow conflicts
        let module_signer = {
            let config = borrow_global<StakingConfig>(@launchpad_addr);
            account::create_signer_with_capability(&config.signer_cap)
        };
        
        let config = borrow_global_mut<StakingConfig>(@launchpad_addr);
        
        assert!(table::contains(&config.user_stakes, sender_addr), ENO_STAKE_FOUND);
        assert!(option::is_some(&config.resort_token), ERESORT_TOKEN_NOT_SET);
        assert!(option::is_some(&config.time_token), ETIME_TOKEN_NOT_SET);

        let stake_info = table::remove(&mut config.user_stakes, sender_addr);
        let resort_token = *option::borrow(&config.resort_token);
        let time_token = *option::borrow(&config.time_token);

        // Calculate final rewards before unstaking
        let current_time = timestamp::now_seconds();
        let time_staked = current_time - stake_info.last_claim_time;
        let final_rewards = (stake_info.amount * time_staked * TIME_REWARD_RATE_PER_SECOND) / 1000000;

        // Update total_staked
        config.total_staked = config.total_staked - stake_info.amount;

        // Return RESORT tokens to user from vault
        primary_fungible_store::transfer(
            &module_signer,
            resort_token,
            sender_addr,
            stake_info.amount
        );

        // Mint and transfer TIME token rewards
        if (final_rewards > 0) {
            launchpad::mint_to(time_token, sender_addr, final_rewards);
        };

        event::emit(UnstakeEvent {
            staker: sender_addr,
            resort_id: stake_info.resort_id,
            amount: stake_info.amount,
            rewards_earned: final_rewards,
            timestamp: current_time,
        });
    }

    #[view]
    public fun get_user_total_staked(user: address): u64 acquires StakingConfig {
        let config = borrow_global<StakingConfig>(@launchpad_addr);
        if (!table::contains(&config.user_stakes, user)) {
            return 0
        };

        let stake_info = table::borrow(&config.user_stakes, user);
        stake_info.amount
    }

    #[view]
    public fun get_pending_rewards(user: address): u64 acquires StakingConfig {
        let config = borrow_global<StakingConfig>(@launchpad_addr);
        if (!table::contains(&config.user_stakes, user)) {
            return 0
        };

        let stake_info = table::borrow(&config.user_stakes, user);
        let current_time = timestamp::now_seconds();
        let time_staked = current_time - stake_info.last_claim_time;
        let rewards = (stake_info.amount * time_staked * TIME_REWARD_RATE_PER_SECOND) / 1000000;
        rewards
    }

    #[view]
    public fun get_total_staked(): u64 acquires StakingConfig {
        let config = borrow_global<StakingConfig>(@launchpad_addr);
        config.total_staked
    }

    #[view]
    /// Get the resource account address where tokens are held
    public fun get_vault_address(): address {
        account::create_resource_address(&@launchpad_addr, b"resort_staking_v1")
    }

}
