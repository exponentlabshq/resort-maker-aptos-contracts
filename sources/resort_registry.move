module launchpad_addr::resort_registry {
    use std::signer;
    use std::string::String;
    use std::vector;
    
    use aptos_std::table::{Self, Table};
    use aptos_framework::event;
    use aptos_framework::timestamp;


    /// Errors
    /// Only admin can create resort
    const EONLY_ADMIN_CAN_CREATE_RESORT: u64 = 1;
    /// Resort not found
    const ERESORT_NOT_FOUND: u64 = 2;
    /// Invalid investment amount
    const EINVALID_INVESTMENT_AMOUNT: u64 = 3;
    /// Resort not active
    const ERESORT_NOT_ACTIVE: u64 = 4;
    /// Insufficient investment balance
    const EINSUFFICIENT_INVESTMENT_BALANCE: u64 = 5;
    /// Only admin can update resort
    const EONLY_ADMIN_CAN_UPDATE_RESORT: u64 = 6;

    #[event]
    struct ResortCreatedEvent has store, drop {
        resort_id: u64,
        name: String,
        location: String,
        total_investment_needed: u64,
        minimum_investment: u64,
        creator: address,
        created_at: u64,
    }

    #[event]
    struct ResortInvestmentEvent has store, drop {
        resort_id: u64,
        investor: address,
        amount: u64,
        total_raised: u64,
        timestamp: u64,
    }

    #[event]
    struct ResortWithdrawalEvent has store, drop {
        resort_id: u64,
        investor: address,
        amount: u64,
        total_raised: u64,
        timestamp: u64,
    }

    #[event]
    struct ResortUpdatedEvent has store, drop {
        resort_id: u64,
        updated_by: address,
        timestamp: u64,
    }

    /// Resort data structure
    struct Resort has store {
        id: u64,
        name: String,
        location: String,
        description: String,
        image_uri: String,
        total_investment_needed: u64,
        minimum_investment: u64,
        current_investment: u64,
        is_active: bool,
        created_at: u64,
        creator: address,
        // Track individual investments
        investors: Table<address, u64>,
    }

    /// Global registry for all resorts
    struct ResortRegistry has key {
        resorts: Table<u64, Resort>,
        resort_count: u64,
        admin: address,
    }

    /// Initialize the registry
    fun init_module(sender: &signer) {
        move_to(sender, ResortRegistry {
            resorts: table::new(),
            resort_count: 0,
            admin: signer::address_of(sender),
        });
    }

    /// Create a new resort (admin only for hackathon simplicity)
    public entry fun create_resort(
        sender: &signer,
        name: String,
        location: String,
        description: String,
        image_uri: String,
        total_investment_needed: u64,
        minimum_investment: u64,
    ) acquires ResortRegistry {
        let sender_addr = signer::address_of(sender);
        let registry = borrow_global_mut<ResortRegistry>(@launchpad_addr);
        
        assert!(sender_addr == registry.admin, EONLY_ADMIN_CAN_CREATE_RESORT);
        
        let resort_id = registry.resort_count + 1;
        let new_resort = Resort {
            id: resort_id,
            name,
            location,
            description,
            image_uri,
            total_investment_needed,
            minimum_investment,
            current_investment: 0,
            is_active: true,
            created_at: timestamp::now_seconds(),
            creator: sender_addr,
            investors: table::new(),
        };

        table::add(&mut registry.resorts, resort_id, new_resort);
        registry.resort_count = resort_id;

        event::emit(ResortCreatedEvent {
            resort_id,
            name,
            location,
            total_investment_needed,
            minimum_investment,
            creator: sender_addr,
            created_at: timestamp::now_seconds(),
        });
    }

    /// Update resort details (admin only)
    /// Allows updating all editable fields at once
    public entry fun update_resort(
        sender: &signer,
        resort_id: u64,
        name: String,
        location: String,
        description: String,
        image_uri: String,
        total_investment_needed: u64,
        minimum_investment: u64,
    ) acquires ResortRegistry {
        let sender_addr = signer::address_of(sender);
        let registry = borrow_global_mut<ResortRegistry>(@launchpad_addr);
        
        assert!(sender_addr == registry.admin, EONLY_ADMIN_CAN_UPDATE_RESORT);
        assert!(table::contains(&registry.resorts, resort_id), ERESORT_NOT_FOUND);
        
        let resort = table::borrow_mut(&mut registry.resorts, resort_id);
        resort.name = name;
        resort.location = location;
        resort.description = description;
        resort.image_uri = image_uri;
        resort.total_investment_needed = total_investment_needed;
        resort.minimum_investment = minimum_investment;

        event::emit(ResortUpdatedEvent {
            resort_id,
            updated_by: sender_addr,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Update resort name (admin only)
    public entry fun update_resort_name(
        sender: &signer,
        resort_id: u64,
        name: String,
    ) acquires ResortRegistry {
        let sender_addr = signer::address_of(sender);
        let registry = borrow_global_mut<ResortRegistry>(@launchpad_addr);
        
        assert!(sender_addr == registry.admin, EONLY_ADMIN_CAN_UPDATE_RESORT);
        assert!(table::contains(&registry.resorts, resort_id), ERESORT_NOT_FOUND);
        
        let resort = table::borrow_mut(&mut registry.resorts, resort_id);
        resort.name = name;

        event::emit(ResortUpdatedEvent {
            resort_id,
            updated_by: sender_addr,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Update resort location (admin only)
    public entry fun update_resort_location(
        sender: &signer,
        resort_id: u64,
        location: String,
    ) acquires ResortRegistry {
        let sender_addr = signer::address_of(sender);
        let registry = borrow_global_mut<ResortRegistry>(@launchpad_addr);
        
        assert!(sender_addr == registry.admin, EONLY_ADMIN_CAN_UPDATE_RESORT);
        assert!(table::contains(&registry.resorts, resort_id), ERESORT_NOT_FOUND);
        
        let resort = table::borrow_mut(&mut registry.resorts, resort_id);
        resort.location = location;

        event::emit(ResortUpdatedEvent {
            resort_id,
            updated_by: sender_addr,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Update resort description (admin only)
    public entry fun update_resort_description(
        sender: &signer,
        resort_id: u64,
        description: String,
    ) acquires ResortRegistry {
        let sender_addr = signer::address_of(sender);
        let registry = borrow_global_mut<ResortRegistry>(@launchpad_addr);
        
        assert!(sender_addr == registry.admin, EONLY_ADMIN_CAN_UPDATE_RESORT);
        assert!(table::contains(&registry.resorts, resort_id), ERESORT_NOT_FOUND);
        
        let resort = table::borrow_mut(&mut registry.resorts, resort_id);
        resort.description = description;

        event::emit(ResortUpdatedEvent {
            resort_id,
            updated_by: sender_addr,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Update resort image URI (admin only)
    public entry fun update_resort_image(
        sender: &signer,
        resort_id: u64,
        image_uri: String,
    ) acquires ResortRegistry {
        let sender_addr = signer::address_of(sender);
        let registry = borrow_global_mut<ResortRegistry>(@launchpad_addr);
        
        assert!(sender_addr == registry.admin, EONLY_ADMIN_CAN_UPDATE_RESORT);
        assert!(table::contains(&registry.resorts, resort_id), ERESORT_NOT_FOUND);
        
        let resort = table::borrow_mut(&mut registry.resorts, resort_id);
        resort.image_uri = image_uri;

        event::emit(ResortUpdatedEvent {
            resort_id,
            updated_by: sender_addr,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Update resort investment parameters (admin only)
    public entry fun update_resort_investment_params(
        sender: &signer,
        resort_id: u64,
        total_investment_needed: u64,
        minimum_investment: u64,
    ) acquires ResortRegistry {
        let sender_addr = signer::address_of(sender);
        let registry = borrow_global_mut<ResortRegistry>(@launchpad_addr);
        
        assert!(sender_addr == registry.admin, EONLY_ADMIN_CAN_UPDATE_RESORT);
        assert!(table::contains(&registry.resorts, resort_id), ERESORT_NOT_FOUND);
        
        let resort = table::borrow_mut(&mut registry.resorts, resort_id);
        resort.total_investment_needed = total_investment_needed;
        resort.minimum_investment = minimum_investment;

        event::emit(ResortUpdatedEvent {
            resort_id,
            updated_by: sender_addr,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Toggle resort active status (admin only)
    public entry fun set_resort_active(
        sender: &signer,
        resort_id: u64,
        is_active: bool,
    ) acquires ResortRegistry {
        let sender_addr = signer::address_of(sender);
        let registry = borrow_global_mut<ResortRegistry>(@launchpad_addr);
        
        assert!(sender_addr == registry.admin, EONLY_ADMIN_CAN_UPDATE_RESORT);
        assert!(table::contains(&registry.resorts, resort_id), ERESORT_NOT_FOUND);
        
        let resort = table::borrow_mut(&mut registry.resorts, resort_id);
        resort.is_active = is_active;

        event::emit(ResortUpdatedEvent {
            resort_id,
            updated_by: sender_addr,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Record investment in a resort (called by staking module)
    public fun record_investment(
        resort_id: u64,
        investor: address,
        amount: u64,
    ) acquires ResortRegistry {
        let registry = borrow_global_mut<ResortRegistry>(@launchpad_addr);
        assert!(table::contains(&registry.resorts, resort_id), ERESORT_NOT_FOUND);
        
        let resort = table::borrow_mut(&mut registry.resorts, resort_id);
        assert!(resort.is_active, ERESORT_NOT_ACTIVE);
        
        // Only check minimum investment for first-time investors
        let is_new_investor = !table::contains(&resort.investors, investor);
        if (is_new_investor) {
            assert!(amount >= resort.minimum_investment, EINVALID_INVESTMENT_AMOUNT);
        };

        // Update resort investment tracking
        resort.current_investment = resort.current_investment + amount;
        
        // Update investor tracking
        if (is_new_investor) {
            table::add(&mut resort.investors, investor, amount);
        } else {
            let current_investment = table::borrow_mut(&mut resort.investors, investor);
            *current_investment = *current_investment + amount;
        };

        event::emit(ResortInvestmentEvent {
            resort_id,
            investor,
            amount,
            total_raised: resort.current_investment,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Remove investment from a resort (called by staking module on unstake)
    public fun remove_investment(
        resort_id: u64,
        investor: address,
        amount: u64,
    ) acquires ResortRegistry {
        let registry = borrow_global_mut<ResortRegistry>(@launchpad_addr);
        assert!(table::contains(&registry.resorts, resort_id), ERESORT_NOT_FOUND);
        
        let resort = table::borrow_mut(&mut registry.resorts, resort_id);
        
        // Verify investor has sufficient balance in this resort
        assert!(table::contains(&resort.investors, investor), EINSUFFICIENT_INVESTMENT_BALANCE);
        let investor_amount = table::borrow_mut(&mut resort.investors, investor);
        assert!(*investor_amount >= amount, EINSUFFICIENT_INVESTMENT_BALANCE);

        // Update investor tracking
        *investor_amount = *investor_amount - amount;
        
        // Update resort investment tracking
        resort.current_investment = resort.current_investment - amount;

        event::emit(ResortWithdrawalEvent {
            resort_id,
            investor,
            amount,
            total_raised: resort.current_investment,
            timestamp: timestamp::now_seconds(),
        });
    }

    #[view]
    public fun get_resort(resort_id: u64): (String, String, String, String, u64, u64, u64, bool) acquires ResortRegistry {
        let registry = borrow_global<ResortRegistry>(@launchpad_addr);
        assert!(table::contains(&registry.resorts, resort_id), ERESORT_NOT_FOUND);
        
        let resort = table::borrow(&registry.resorts, resort_id);
        (
            resort.name,
            resort.location,
            resort.description,
            resort.image_uri,
            resort.total_investment_needed,
            resort.minimum_investment,
            resort.current_investment,
            resort.is_active
        )
    }

    #[view]
    public fun get_all_resort_ids(): vector<u64> acquires ResortRegistry {
        let registry = borrow_global<ResortRegistry>(@launchpad_addr);
        let ids = vector::empty<u64>();
        let i = 1;
        while (i <= registry.resort_count) {
            vector::push_back(&mut ids, i);
            i = i + 1;
        };
        ids
    }

    #[view]
    public fun get_investor_amount(resort_id: u64, investor: address): u64 acquires ResortRegistry {
        let registry = borrow_global<ResortRegistry>(@launchpad_addr);
        assert!(table::contains(&registry.resorts, resort_id), ERESORT_NOT_FOUND);
        
        let resort = table::borrow(&registry.resorts, resort_id);
        if (table::contains(&resort.investors, investor)) {
            *table::borrow(&resort.investors, investor)
        } else {
            0
        }
    }

    #[view]
    public fun get_resort_count(): u64 acquires ResortRegistry {
        let registry = borrow_global<ResortRegistry>(@launchpad_addr);
        registry.resort_count
    }
}
