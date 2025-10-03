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
    use std::vector;

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

    /// Individual stake information per resort
    struct StakeInfo has store, drop {
        amount: u64,
        last_claim_time: u64,
    }

    /// User stakes container - one per user address
    struct UserStakes has key {
        // resort_id -> StakeInfo
        stakes: Table<u64, StakeInfo>,
    }

    /// Global staking configuration and state
    struct StakingConfig has key {
        resort_token: Option<Object<Metadata>>,
        time_token: Option<Object<Metadata>>,
        total_staked: u64,
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
            admin: signer::address_of(sender),
            signer_cap,
        });
    }

    /// Initialize user stakes if not exists
    fun ensure_user_stakes_exist(user: &signer) {
        let user_addr = signer::address_of(user);
        if (!exists<UserStakes>(user_addr)) {
            move_to(user, UserStakes {
                stakes: table::new(),
            });
        };
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
    ) acquires StakingConfig, UserStakes {
        let sender_addr = signer::address_of(sender);
        let config = borrow_global_mut<StakingConfig>(@launchpad_addr);
        
        assert!(option::is_some(&config.resort_token), ERESORT_TOKEN_NOT_SET);
        assert!(amount > 0, EINVALID_STAKE_AMOUNT);
        assert!(resort_id > 0, EINVALID_RESORT_ID);

        let resort_token = *option::borrow(&config.resort_token);
        
        // Check if user has enough RESORT tokens
        let user_balance = primary_fungible_store::balance(sender_addr, resort_token);
        assert!(user_balance >= amount, EINSUFFICIENT_BALANCE);

        // Transfer RESORT tokens to the resource account vault
        let vault_addr = get_vault_address();
        primary_fungible_store::transfer(sender, resort_token, vault_addr, amount);

        // Ensure user stakes structure exists
        ensure_user_stakes_exist(sender);
        let user_stakes = borrow_global_mut<UserStakes>(sender_addr);

        // Create or update stake entry for this resort
        if (table::contains(&user_stakes.stakes, resort_id)) {
            let existing_stake = table::borrow_mut(&mut user_stakes.stakes, resort_id);
            existing_stake.amount = existing_stake.amount + amount;
            // Keep original last_claim_time when adding to existing stake
        } else {
            table::add(&mut user_stakes.stakes, resort_id, StakeInfo {
                amount,
                last_claim_time: timestamp::now_seconds(),
            });
        };

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
    public entry fun claim_rewards(sender: &signer) acquires StakingConfig, UserStakes {
        let sender_addr = signer::address_of(sender);
        let config = borrow_global<StakingConfig>(@launchpad_addr);
        
        assert!(option::is_some(&config.time_token), ETIME_TOKEN_NOT_SET);
        assert!(exists<UserStakes>(sender_addr), ENO_STAKE_FOUND);

        let user_stakes = borrow_global_mut<UserStakes>(sender_addr);
        let time_token = *option::borrow(&config.time_token);
        let current_time = timestamp::now_seconds();
        let total_rewards = 0u64;

        // Calculate rewards across all stakes
        let resort_ids = get_user_resort_stakes_internal(&user_stakes.stakes);
        let i = 0;
        let len = vector::length(&resort_ids);
        while (i < len) {
            let resort_id = *vector::borrow(&resort_ids, i);
            let stake_info = table::borrow_mut(&mut user_stakes.stakes, resort_id);
            let time_staked = current_time - stake_info.last_claim_time;
            let rewards = (stake_info.amount * time_staked * TIME_REWARD_RATE_PER_SECOND) / 1000000;
            total_rewards = total_rewards + rewards;
            stake_info.last_claim_time = current_time;
            i = i + 1;
        };

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

    /// Unstake RESORT tokens from a specific resort
    public entry fun unstake_from_resort(
        sender: &signer,
        resort_id: u64,
        amount: u64,
    ) acquires StakingConfig, UserStakes {
        let sender_addr = signer::address_of(sender);
        
        assert!(exists<UserStakes>(sender_addr), ENO_STAKE_FOUND);
        
        // Get module signer first to avoid borrow conflicts
        let module_signer = {
            let config = borrow_global<StakingConfig>(@launchpad_addr);
            account::create_signer_with_capability(&config.signer_cap)
        };
        
        let config = borrow_global_mut<StakingConfig>(@launchpad_addr);
        assert!(option::is_some(&config.resort_token), ERESORT_TOKEN_NOT_SET);
        assert!(option::is_some(&config.time_token), ETIME_TOKEN_NOT_SET);

        let user_stakes = borrow_global_mut<UserStakes>(sender_addr);
        assert!(table::contains(&user_stakes.stakes, resort_id), ENO_STAKE_FOUND);

        let stake_info = table::borrow_mut(&mut user_stakes.stakes, resort_id);
        assert!(stake_info.amount >= amount, EINSUFFICIENT_BALANCE);

        let resort_token = *option::borrow(&config.resort_token);
        let time_token = *option::borrow(&config.time_token);

        // Calculate rewards before unstaking
        let current_time = timestamp::now_seconds();
        let time_staked = current_time - stake_info.last_claim_time;
        let rewards = (stake_info.amount * time_staked * TIME_REWARD_RATE_PER_SECOND) / 1000000;

        // Update stake amount
        stake_info.amount = stake_info.amount - amount;
        stake_info.last_claim_time = current_time;

        // Remove stake entry if fully unstaked
        if (stake_info.amount == 0) {
            table::remove(&mut user_stakes.stakes, resort_id);
        };

        // Update total_staked
        config.total_staked = config.total_staked - amount;

        // Remove investment from resort registry
        resort_registry::remove_investment(resort_id, sender_addr, amount);

        // Return RESORT tokens to user from vault
        primary_fungible_store::transfer(
            &module_signer,
            resort_token,
            sender_addr,
            amount
        );

        // Mint and transfer TIME token rewards
        if (rewards > 0) {
            launchpad::mint_to(time_token, sender_addr, rewards);
        };

        event::emit(UnstakeEvent {
            staker: sender_addr,
            resort_id,
            amount,
            rewards_earned: rewards,
            timestamp: current_time,
        });
    }

    /// Unstake all RESORT tokens from all resorts
    public entry fun unstake_all(sender: &signer) acquires StakingConfig, UserStakes {
        let sender_addr = signer::address_of(sender);
        assert!(exists<UserStakes>(sender_addr), ENO_STAKE_FOUND);

        let user_stakes = borrow_global<UserStakes>(sender_addr);
        let resort_ids = get_user_resort_stakes_internal(&user_stakes.stakes);
        
        let i = 0;
        let len = vector::length(&resort_ids);
        while (i < len) {
            let resort_id = *vector::borrow(&resort_ids, i);
            let amount = {
                let user_stakes_ref = borrow_global<UserStakes>(sender_addr);
                let stake_info = table::borrow(&user_stakes_ref.stakes, resort_id);
                stake_info.amount
            };
            unstake_from_resort(sender, resort_id, amount);
            i = i + 1;
        };
    }

    #[view]
    public fun get_user_total_staked(user: address): u64 acquires UserStakes {
        if (!exists<UserStakes>(user)) {
            return 0
        };

        let user_stakes = borrow_global<UserStakes>(user);
        let total = 0u64;
        let resort_ids = get_user_resort_stakes_internal(&user_stakes.stakes);
        let i = 0;
        let len = vector::length(&resort_ids);
        while (i < len) {
            let resort_id = *vector::borrow(&resort_ids, i);
            let stake_info = table::borrow(&user_stakes.stakes, resort_id);
            total = total + stake_info.amount;
            i = i + 1;
        };
        total
    }

    #[view]
    public fun get_user_stake_in_resort(user: address, resort_id: u64): u64 acquires UserStakes {
        if (!exists<UserStakes>(user)) {
            return 0
        };

        let user_stakes = borrow_global<UserStakes>(user);
        if (!table::contains(&user_stakes.stakes, resort_id)) {
            return 0
        };

        let stake_info = table::borrow(&user_stakes.stakes, resort_id);
        stake_info.amount
    }

    #[view]
    public fun get_pending_rewards(user: address): u64 acquires UserStakes {
        if (!exists<UserStakes>(user)) {
            return 0
        };

        let user_stakes = borrow_global<UserStakes>(user);
        let current_time = timestamp::now_seconds();
        let total_rewards = 0u64;

        let resort_ids = get_user_resort_stakes_internal(&user_stakes.stakes);
        let i = 0;
        let len = vector::length(&resort_ids);
        while (i < len) {
            let resort_id = *vector::borrow(&resort_ids, i);
            let stake_info = table::borrow(&user_stakes.stakes, resort_id);
            let time_staked = current_time - stake_info.last_claim_time;
            let rewards = (stake_info.amount * time_staked * TIME_REWARD_RATE_PER_SECOND) / 1000000;
            total_rewards = total_rewards + rewards;
            i = i + 1;
        };
        total_rewards
    }

    #[view]
    public fun get_pending_rewards_for_resort(user: address, resort_id: u64): u64 acquires UserStakes {
        if (!exists<UserStakes>(user)) {
            return 0
        };

        let user_stakes = borrow_global<UserStakes>(user);
        if (!table::contains(&user_stakes.stakes, resort_id)) {
            return 0
        };

        let stake_info = table::borrow(&user_stakes.stakes, resort_id);
        let current_time = timestamp::now_seconds();
        let time_staked = current_time - stake_info.last_claim_time;
        let rewards = (stake_info.amount * time_staked * TIME_REWARD_RATE_PER_SECOND) / 1000000;
        rewards
    }

    /// Get all resort IDs that a user has staked in
    fun get_user_resort_stakes_internal(stakes: &Table<u64, StakeInfo>): vector<u64> {
        // Note: This is a simplified approach for hackathon
        // In production, you'd want to maintain a separate vector of resort_ids
        // For now, we'll limit the search to a reasonable number
        let resort_ids = vector::empty<u64>();
        let max_resort_id = 1000u64; // Assume max 1000 resorts
        let i = 1u64;
        while (i <= max_resort_id) {
            if (table::contains(stakes, i)) {
                vector::push_back(&mut resort_ids, i);
            };
            i = i + 1;
        };
        resort_ids
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

    #[view]
    /// Get all resort IDs that a user has staked in
    public fun get_user_staked_resorts(user: address): vector<u64> acquires UserStakes {
        if (!exists<UserStakes>(user)) {
            return vector::empty<u64>()
        };

        let user_stakes = borrow_global<UserStakes>(user);
        get_user_resort_stakes_internal(&user_stakes.stakes)
    }

}
