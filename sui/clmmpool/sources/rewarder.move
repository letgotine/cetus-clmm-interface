// Copyright (c) Cetus Technology Limited

/// `Rewarder` is the liquidity incentive module of `clmmpool`, which is commonly known as `farming`. In `clmmpool`,
/// liquidity is stored in a price range, so `clmmpool` uses a reward allocation method based on effective liquidity.
/// The allocation rules are roughly as follows:
///
/// 1. Each pool can configure multiple `Rewarders`, and each `Rewarder` releases rewards at a uniform speed according
/// to its configured release rate.
/// 2. During the time period when the liquidity price range contains the current price of the pool, the liquidity
/// position can participate in the reward distribution for this time period (if the pool itself is configured with
/// rewards), and the proportion of the distribution depends on the size of the liquidity value of the position.
/// Conversely, if the price range of a position does not include the current price of the pool during a certain period
/// of time, then this position will not receive any rewards during this period of time. This is similar to the
/// calculation of transaction fees.
module cetus_clmm::rewarder {
    use std::option::Option;
    use std::type_name::TypeName;
    use sui::bag::Bag;
    use sui::balance::Balance;
    use sui::object::{UID, ID};

    use cetus_clmm::config::{GlobalConfig, AdminCap};

    struct RewarderManager has store {
        rewarders: vector<Rewarder>,
        points_released: u128,
        points_growth_global: u128,
        last_updated_time: u64,
    }

    struct Rewarder has copy, drop, store {
        reward_coin: TypeName,
        emissions_per_second: u128,
        growth_global: u128,
    }

    struct RewarderGlobalVault has key, store {
        id: UID,
        balances: Bag
    }

    /// Emit when `RewarderManager` is initialized.
    struct RewarderInitEvent has copy, drop {
        global_vault_id: ID,
    }

    /// Emit when deposit reward.
    struct DepositEvent has copy, drop, store {
        reward_type: TypeName,
        deposit_amount: u64,
        after_amount: u64
    }

    /// Emit when withdraw reward.
    struct EmergentWithdrawEvent has copy, drop, store {
        reward_type: TypeName,
        withdraw_amount: u64,
        after_amount: u64
    }


    /// get the rewarders
    public fun rewarders(_manager: &RewarderManager): vector<Rewarder> {
        abort 0
    }

    /// get the reward_growth_globals
    public fun rewards_growth_global(_manager: &RewarderManager): vector<u128> {
        abort 0
    }

    /// get the points_released
    public fun points_released(_manager: &RewarderManager): u128 {
        abort 0
    }

    /// get the points_growth_global
    public fun points_growth_global(_manager: &RewarderManager): u128 {
        abort 0
    }

    /// get the last_updated_time
    public fun last_update_time(_manager: &RewarderManager): u64 {
        abort 0
    }

    /// get the rewarder coin Type.
    public fun reward_coin(_rewarder: &Rewarder): TypeName {
        abort 0
    }

    /// get the rewarder emissions_per_second.
    public fun emissions_per_second(_rewarder: &Rewarder): u128 {
        abort 0
    }

    /// get the rewarder growth_global.
    public fun growth_global(_rewarder: &Rewarder): u128 {
        abort 0
    }

    /// Get index of CoinType in `RewarderManager`, if not exists, return `None`
    public fun rewarder_index<CoinType>(_manager: &RewarderManager): Option<u64> {
        abort 0
    }

    /// Borrow `Rewarder` from `RewarderManager`
    public fun borrow_rewarder<CoinType>(_manager: &RewarderManager): &Rewarder {
        abort 0
    }

    
    /// Deposit Reward into `RewarderGlobalVault`
    /// Params
    ///     - `config`: GlobalConfig
    ///     - `vault`: RewarderGlobalVault
    ///     - `balance`: Balance of CoinType
    public fun deposit_reward<CoinType>(
        _config: &GlobalConfig,
        _vault: &mut RewarderGlobalVault,
        _balance: Balance<CoinType>
    ): u64 {
        abort 0
    }

    /// Withdraw reward Balance of CoinType from vault by the protocol `AdminCap`.
    /// This function is only used for emergency.
    /// Params
    ///     - config: GlobalConfig.
    ///     - amount: the amount of reward Balance to withdraw.
    ///     - vault: RewarderGlobalVault.
    public fun emergent_withdraw<CoinType>(
        _: &AdminCap,
        _config: &GlobalConfig,
        _vault: &mut RewarderGlobalVault,
        _amount: u64
    ): Balance<CoinType> {
        abort 0
    }

    /// Get the balances in vault.
    public fun balances(
        _vault: & RewarderGlobalVault
    ): &Bag {
        abort 0
    }

    /// Get the balance value of CoinType in vault.
    public fun balance_of<CoinType>(
        _vault: &RewarderGlobalVault
    ): u64 {
        abort 0
    }    
}
