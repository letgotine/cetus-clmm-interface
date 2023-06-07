// Copyright (c) Cetus Technology Limited

/// Concentrated Liquidity Market Maker (CLMM) is a new generation of automated market maker (AMM) aiming to improve
/// decentralized exchanges' capital efficiency and provide attractive yield opportunities for liquidity providers.
/// Different from the constant product market maker that only allows liquidity to be distributed uniformly across the
/// full price curve (0, `positive infinity`), CLMM allows liquidity providers to add their liquidity into specified price ranges.
/// The price in a CLMM pool is discrete, rather than continuous. The liquidity allocated into a specific price range
/// by a user is called a liquidity position.
///
/// "Pool" is the core module of Clmm protocol, which defines the trading pairs of "clmmpool".
/// All operations related to trading and liquidity are completed by this module.
module cetus_clmm::pool {
    use sui::object::{UID, ID};
    use sui::balance::{Balance};
    use std::string::String;
    use std::type_name::TypeName;
    use std::vector;
    use sui::tx_context::TxContext;
    use sui::clock::Clock;
    use sui::package::Publisher;

    use integer_mate::i32::I32;

    use cetus_clmm::config::GlobalConfig;
    use cetus_clmm::partner::Partner;
    use cetus_clmm::position::{Position, PositionManager, PositionInfo};
    use cetus_clmm::tick::{Tick, TickManager};
    use cetus_clmm::rewarder::{RewarderManager, RewarderGlobalVault};
    // === Struct ===

    /// One-Time-Witness for the module.
    struct POOL has drop {}

    /// The clmmpool
    struct Pool<phantom CoinTypeA, phantom CoinTypeB> has key, store {
        id: UID,

        coin_a: Balance<CoinTypeA>,
        coin_b: Balance<CoinTypeB>,

        /// The tick spacing
        tick_spacing: u32,

        /// The numerator of fee rate, the denominator is 1_000_000.
        fee_rate: u64,

        /// The liquidity of current tick index
        liquidity: u128,

        /// The current sqrt price
        current_sqrt_price: u128,

        /// The current tick index
        current_tick_index: I32,

        /// The global fee growth of coin a,b as Q64.64
        fee_growth_global_a: u128,
        fee_growth_global_b: u128,

        /// The amounts of coin a,b owend to protocol
        fee_protocol_coin_a: u64,
        fee_protocol_coin_b: u64,

        /// The tick manager
        tick_manager: TickManager,

        /// The rewarder manager
        rewarder_manager: RewarderManager,

        /// The position manager
        position_manager: PositionManager,

        /// is the pool pause
        is_pause: bool,

        /// The pool index
        index: u64,

        /// The url for pool and postion
        url: String,
    }

    /// The swap result
    struct SwapResult has copy, drop {
        amount_in: u64,
        amount_out: u64,
        fee_amount: u64,
        ref_fee_amount: u64,
        steps: u64,
    }


    /// Flash loan resource for swap.
    /// There is no way in Move to pass calldata and make dynamic calls, but a resource can be used for this purpose.
    /// To make the execution into a single transaction, the flash loan function must return a resource
    /// that cannot be copied, cannot be saved, cannot be dropped, or cloned.
    struct FlashSwapReceipt<phantom CoinTypeA, phantom CoinTypeB> {
        pool_id: ID,
        a2b: bool,
        partner_id: ID,
        pay_amount: u64,
        ref_fee_amount: u64
    }

    /// Flash loan resource for add_liquidity
    struct AddLiquidityReceipt<phantom CoinTypeA, phantom CoinTypeB> {
        pool_id: ID,
        amount_a: u64,
        amount_b: u64
    }

    /// The calculated swap result
    struct CalculatedSwapResult has copy, drop, store {
        amount_in: u64,
        amount_out: u64,
        fee_amount: u64,
        fee_rate: u64,
        after_sqrt_price: u128,
        is_exceed: bool,
        step_results: vector<SwapStepResult>
    }

    /// The step swap result
    struct SwapStepResult has copy, drop, store {
        current_sqrt_price: u128,
        target_sqrt_price: u128,
        current_liquidity: u128,
        amount_in: u64,
        amount_out: u64,
        fee_amount: u64,
        remainder_amount: u64
    }

    // === Events ===

    /// Emited when a position was opened.
    struct OpenPositionEvent has copy, drop, store {
        pool: ID,
        tick_lower: I32,
        tick_upper: I32,
        position: ID,
    }

    /// Emited when a position was closed.
    struct ClosePositionEvent has copy, drop, store {
        pool: ID,
        position: ID,
    }

    /// Emited when add liquidity for a position.
    struct AddLiquidityEvent has copy, drop, store {
        pool: ID,
        position: ID,
        tick_lower: I32,
        tick_upper: I32,
        liquidity: u128,
        after_liquidity: u128,
        amount_a: u64,
        amount_b: u64,
    }

    /// Emited when remove liquidity from a position.
    struct RemoveLiquidityEvent has copy, drop, store {
        pool: ID,
        position: ID,
        tick_lower: I32,
        tick_upper: I32,
        liquidity: u128,
        after_liquidity: u128,
        amount_a: u64,
        amount_b: u64,
    }

    /// Emited when swap in a clmmpool.
    struct SwapEvent has copy, drop, store {
        atob: bool,
        pool: ID,
        partner: ID,
        amount_in: u64,
        amount_out: u64,
        ref_amount: u64,
        fee_amount: u64,
        vault_a_amount: u64,
        vault_b_amount: u64,
        before_sqrt_price: u128,
        after_sqrt_price: u128,
        steps: u64,
    }

    /// Emited when the porotocol manager collect protocol fee from clmmpool.
    struct CollectProtocolFeeEvent has copy, drop, store {
        pool: ID,
        amount_a: u64,
        amount_b: u64
    }

    /// Emited when user collect liquidity fee from a position.
    struct CollectFeeEvent has copy, drop, store {
        position: ID,
        pool: ID,
        amount_a: u64,
        amount_b: u64
    }

    /// Emited when the clmmpool's liqudity fee rate had updated.
    struct UpdateFeeRateEvent has copy, drop, store {
        pool: ID,
        old_fee_rate: u64,
        new_fee_rate: u64
    }

    /// Emited when the rewarder's emission per second had updated.
    struct UpdateEmissionEvent has copy, drop, store {
        pool: ID,
        rewarder_type: TypeName,
        emissions_per_second: u128,
    }

    /// Emited when a rewarder append to clmmpool.
    struct AddRewarderEvent has copy, drop, store {
        pool: ID,
        rewarder_type: TypeName,
    }

    /// Emited when collect reward from clmmpool's rewarder.
    struct CollectRewardEvent has copy, drop, store {
        position: ID,
        pool: ID,
        amount: u64,
    }

    /// Set display for pool.
    public fun set_display<CoinTypeA, CoinTypeB>(
        _config: &GlobalConfig,
        _publisher: &Publisher,
        _name: String,
        _description: String,
        _url: String,
        _link: String,
        _website: String,
        _creator: String,
        _ctx: &mut TxContext
    ) {
        abort 0
    }

    // === Public Functions ===
    public fun open_position<CoinTypeA, CoinTypeB>(
        _config: &GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _tick_lower: u32,
        _tick_upper: u32,
        _ctx: &mut TxContext
    ): Position {
        abort 0
    }

    public fun add_liquidity<CoinTypeA, CoinTypeB>(
        _config: &GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _position_nft: &mut Position,
        _delta_liquidity: u128,
        _clock: &Clock,
    ): AddLiquidityReceipt<CoinTypeA, CoinTypeB> {
        abort 0
    }

    public fun add_liquidity_fix_coin<CoinTypeA, CoinTypeB>(
        _config: &GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _position_nft: &mut Position,
        _amount: u64,
        _fix_amount_a: bool,
        _clock: &Clock
    ): AddLiquidityReceipt<CoinTypeA, CoinTypeB> {
        abort 0
    }

    public fun add_liquidity_pay_amount<CoinTypeA, CoinTypeB>(
        _receipt: &AddLiquidityReceipt<CoinTypeA, CoinTypeB>
    ): (u64, u64) {
        abort 0
    }

    public fun repay_add_liquidity<CoinTypeA, CoinTypeB>(
        _config: &GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _balance_a: Balance<CoinTypeA>,
        _balance_b: Balance<CoinTypeB>,
        _receipt: AddLiquidityReceipt<CoinTypeA, CoinTypeB>
    ) {
        abort 0
    }

    public fun remove_liquidity<CoinTypeA, CoinTypeB>(
        _config: &GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _position_nft: &mut Position,
        _delta_liquidity: u128,
        _clock: &Clock,
    ): (Balance<CoinTypeA>, Balance<CoinTypeB>) {
        abort 0
    }

    public fun close_position<CoinTypeA, CoinTypeB>(
        _config: &GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _position_nft: Position,
    ) {
        abort 0
    }

    /// Collect the fee from position.
    public fun collect_fee<CoinTypeA, CoinTypeB>(
        _config: &GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _position_nft: &Position,
        _recalculate: bool,
    ): (Balance<CoinTypeA>, Balance<CoinTypeB>) {
        abort 0
    }

    /// Collect rewarder
    public fun collect_reward<CoinTypeA, CoinTypeB, CoinTypeC>(
        _config: &GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _position_nft: &Position,
        _vault: &mut RewarderGlobalVault,
        _recalculate: bool,
        _clock: &Clock
    ): Balance<CoinTypeC> {
        abort 0
    }


    /// Calculate the positions's rewards and update it and return its.
    /// Params
    ///     - `config` The global config of clmm package.
    ///     - `pool` The clmm pool object.
    ///     - `position_id` The object id of position's NFT.
    ///     - `recalcuate` A flag
    ///     - `clock` The `Clock` object.
    /// Returns
    ///    - `reward_amounts` A list that contains the pending rewards for each `Rewarder`.
    public fun calculate_and_update_rewards<CoinTypeA, CoinTypeB>(
        _config: &GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _position_id: ID,
        _clock: &Clock
    ): vector<u64> {
        abort 0
    }

    /// Calculate and update the position's rewards and return one of which reward type is `CoinTypeC`.
    /// Params
    ///     - `config` The global config of clmm package.
    ///     - `pool` The clmm pool object.
    ///     - `position_id` The object id of position's NFT.
    ///     - `clock` The `Clock` object.
    /// Returns
    ///     - `reward_amount` The pending reward amount.
    ///
    public fun calculate_and_update_reward<CoinTypeA, CoinTypeB, CoinTypeC>(
        _config: &GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _position_id: ID,
        _clock: &Clock
    ): u64 {
        abort 0
    }

    /// Calculate and update the position's point and return it.
    /// Params
    ///     - `config` The global config of clmm package.
    ///     - `pool` The clmm pool object.
    ///     - `position_id` The object id of position's NFT.
    ///     - `clock` The `Clock` object.
    /// Returns
    ///     - `point` The current point of `position`..
    public fun calculate_and_update_points<CoinTypeA, CoinTypeB>(
        _config: &GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _position_id: ID,
        _clock: &Clock
    ): u128 {
        abort 0
    }

    /// Calculate and update the position's fee and return it.
    /// Params
    ///     - `config` The global config of clmm package.
    ///     - `pool` The clmm pool object.
    ///     - `position_id` The object id of position's NFT.
    /// Returns
    ///     - `fee_a` The fee amount of `CoinTypeA`
    ///     - `fee_b` The fee amount of `CoinTypeB`
    public fun calculate_and_update_fee<CoinTypeA, CoinTypeB>(
        _config: &GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _position_id: ID,
    ): (u64, u64) {
        abort 0
    }

    /// Flash swap
    /// Params
    ///     - `config` The global config of clmm package.
    ///     - `pool` The clmm pool object.
    ///     - `a2b` One flag, if true, indicates that coin of `CoinTypeA` is exchanged with the coin of `CoinTypeB`,
    /// otherwise it indicates that the coin of `CoinTypeB` is exchanged with the coin of `CoinTypeA`.
    ///     - `by_amount_in` A flag, if set to true, indicates that the next `amount` parameter specifies
    /// the input amount, otherwise it specifies the output amount.
    ///     - `amount` The amount that indicates input or output.
    ///     - `sqrt_price_limit` Price limit, if the swap causes the price to it value, the swap will stop here and return
    ///     - `clock`
    public fun flash_swap<CoinTypeA, CoinTypeB>(
        _config: &GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _a2b: bool,
        _by_amount_in: bool,
        _amount: u64,
        _sqrt_price_limit: u128,
        _clock: &Clock,
    ): (Balance<CoinTypeA>, Balance<CoinTypeB>, FlashSwapReceipt<CoinTypeA, CoinTypeB>) {
        abort 0
    }

    /// Repay for flash swap
    /// Params
    ///     - `config` The global config of clmm package.
    ///     - `pool` The clmm pool object.
    ///     - `coin_a` The object of `CoinTypeA` will pay for flash_swap,
    /// if `a2b` is true the value need equal `receipt.pay_amount` else it need with zero value.
    ///     - `coin_b` The object of `CoinTypeB` will pay for flash_swap,
    /// if `a2b` is false the value need equal `receipt.pay_amount` else it need with zero value.
    ///     - `receipt` The receipt which will be destory.
    /// Returns
    ///     Null
    public fun repay_flash_swap<CoinTypeA, CoinTypeB>(
        _config: &GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _coin_a: Balance<CoinTypeA>,
        _coin_b: Balance<CoinTypeB>,
        _receipt: FlashSwapReceipt<CoinTypeA, CoinTypeB>
    ) {
        abort 0
    }

    /// Flash swap with partner, like flash swap but there has a partner object for receive ref fee.
    public fun flash_swap_with_partner<CoinTypeA, CoinTypeB>(
        _config: &GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _partner: &Partner,
        _a2b: bool,
        _by_amount_in: bool,
        _amount: u64,
        _sqrt_price_limit: u128,
        _clock: &Clock,
    ): (Balance<CoinTypeA>, Balance<CoinTypeB>, FlashSwapReceipt<CoinTypeA, CoinTypeB>) {
        abort 0
    }

    /// Repay for flash swap with partner for receive ref fee.
    public fun repay_flash_swap_with_partner<CoinTypeA, CoinTypeB>(
        _config: &GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _partner: &mut Partner,
        _coin_a: Balance<CoinTypeA>,
        _coin_b: Balance<CoinTypeB>,
        _receipt: FlashSwapReceipt<CoinTypeA, CoinTypeB>
    ) {
        abort 0
    }


    /// Collect the protocol fee by the protocol_feee_claim_authority
    /// Params
    ///     - `config` The global config of clmm package.
    ///     - `pool` The clmm pool object.
    ///     - `ctx` The TxContext
    /// Returns
    ///     - `protocol_fee_a` The protocol fee balance object of `CoinTypeA`
    ///     - `protocol_fee_b` The protocol fee balance object of `CoinTypeB`
    public fun collect_protocol_fee<CoinTypeA, CoinTypeB>(
        _config: &GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _ctx: &TxContext,
    ): (Balance<CoinTypeA>, Balance<CoinTypeB>) {
        abort 0
    }

    /// Initialize a `Rewarder` to `Pool` with a reward type of `CoinTypeC`.
    /// Only one `Rewarder` per `CoinType` can exist in `Pool`.
    /// Params
    ///     - `config` The global config of clmm package
    ///     - `pool` The clmm pool object
    ///     - `ctx` The TxContext
    /// Returns
    ///     Null
    public fun initialize_rewarder<CoinTypeA, CoinTypeB, CoinTypeC>(
        _config: &GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _ctx: &TxContext
    ) {
        abort 0
    }

    /// Update the rewarder emission speed to start the rewarder to generate.
    /// Params
    ///     - `config` The global config of clmm package
    ///     - `pool` The clmm pool object
    ///     - `vault` The `RewarderGlobalVault` object which stores all the rewards to be distributed by Rewarders.
    ///     - `emissions_per_second` The parameter represents the number of rewards released per second,
    /// which is a fixed-point number with a total of 128 bits, with the decimal part occupying 64 bits.
    /// If a value of 0 is passed in, it indicates that the Rewarder's reward release will be paused.
    ///     - `clock` The `Clock` object
    ///     - `ctx` The TxContext
    /// Returns
    ///     Null
    public fun update_emission<CoinTypeA, CoinTypeB, CoinTypeC>(
        _config: &GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _vault: &RewarderGlobalVault,
        _emissions_per_second: u128,
        _clock: &Clock,
        _ctx: &TxContext
    ) {
        abort 0
    }

    /// Update the position nft image url. Just take effect on the new position
    /// Params
    ///     - `config` The global config of clmm package
    ///     - `pool` The clmm pool object
    ///     - `url` The new position nft image url
    ///     - `ctx` The TxContext
    /// Returns
    ///     Null
    public fun update_position_url<CoinTypeA, CoinTypeB>(
        _config: &GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _url: String,
        _ctx: &TxContext
    ) {
        abort 0
    }

    /// Update pool fee rate
    /// Params
    ///     - `config` The global config of clmm package
    ///     - `pool` The clmm pool object
    ///     - `fee_rate` The pool new fee rate
    ///     - `ctx` The TxContext
    /// Returns
    ///     Null
    public fun update_fee_rate<CoinTypeA, CoinTypeB>(
        _config: &GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _fee_rate: u64,
        _ctx: &TxContext
    ) {
        abort 0
    }

    /// Pause the pool.
    /// For special cases, `pause` is used to pause the `Pool`. When a `Pool` is paused, all operations except for
    /// `unpause` are disabled.
    /// Params
    ///     - `config` The global config of clmm package
    ///     - `pool` The clmm pool object
    ///     - `ctx` The TxContext
    /// Returns
    ///     Null
    public fun pause<CoinTypeA, CoinTypeB>(
        _config: &GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _ctx: &TxContext
    ) {
        abort 0
    }

    /// Unpause the pool.
    /// Params
    ///     - `config` The global config of clmm package
    ///     - `pool` The clmm pool object
    ///     - `ctx` The TxContext
    /// Returns
    ///     Null
    public fun unpause<CoinTypeA, CoinTypeB>(
        _config: &GlobalConfig,
        _pool: &mut Pool<CoinTypeA, CoinTypeB>,
        _ctx: &TxContext
    ) {
        abort 0
    }

    /// Get the coin amount by liquidity
    public fun get_amount_by_liquidity(
        _tick_lower: I32,
        _tick_upper: I32,
        _current_tick_index: I32,
        _current_sqrt_price: u128,
        _liquidity: u128,
        _round_up: bool
    ): (u64, u64) {
        abort 0
    }

    /// Get the liquidity by amount
    public fun get_liquidity_from_amount(
        _lower_index: I32,
        _upper_index: I32,
        _current_tick_index: I32,
        _current_sqrt_price: u128,
        _amount: u64,
        _is_fixed_a: bool
    ): (u128, u64, u64) {
        abort 0
    }

    public fun get_fee_in_tick_range<CoinTypeA, CoinTypeB>(
        _pool: &Pool<CoinTypeA, CoinTypeB>,
        _tick_lower_index: I32,
        _tick_upper_index: I32,
    ): (u128, u128) {
        abort 0
    }

    public fun get_rewards_in_tick_range<CoinTypeA, CoinTypeB>(
        _pool: &Pool<CoinTypeA, CoinTypeB>,
        _tick_lower_index: I32,
        _tick_upper_index: I32,
    ): vector<u128> {
        abort 0
    }

    public fun get_points_in_tick_range<CoinTypeA, CoinTypeB>(
        _pool: &Pool<CoinTypeA, CoinTypeB>,
        _tick_lower_index: I32,
        _tick_upper_index: I32,
    ): u128 {
        abort 0
    }

    public fun get_fee_rewards_points_in_tick_range<CoinTypeA, CoinTypeB>(
        _pool: &Pool<CoinTypeA, CoinTypeB>,
        _tick_lower_index: I32,
        _tick_upper_index: I32,
    ): (u128, u128, vector<u128>, u128) {
        abort 0
    }

    public fun fetch_ticks<CoinTypeA, CoinTypeB>(
        _pool: &Pool<CoinTypeA, CoinTypeB>,
        _start: vector<u32>,
        _limit: u64
    ): vector<Tick> {
        abort 0
    }

    public fun fetch_positions<CoinTypeA, CoinTypeB>(_pool: &Pool<CoinTypeA, CoinTypeB>, _start: vector<ID>, _limit: u64
    ): vector<PositionInfo> {
        abort 0
    }

    // Calculate Swap Result
    public fun calculate_swap_result<CoinTypeA, CoinTypeB>(
        _pool: &Pool<CoinTypeA, CoinTypeB>,
        _a2b: bool,
        _by_amount_in: bool,
        _amount: u64,
    ): CalculatedSwapResult {
        abort 0
    }


    public fun balances<CoinTypeA, CoinTypeB>(
        _pool: &Pool<CoinTypeA, CoinTypeB>
    ): (&Balance<CoinTypeA>, &Balance<CoinTypeB>) {
        abort 0
    }

    public fun tick_spacing<CoinTypeA, CoinTypeB>(_pool: &Pool<CoinTypeA, CoinTypeB>): u32 {
        abort 0
    }

    public fun fee_rate<CoinTypeA, CoinTypeB>(_pool: &Pool<CoinTypeA, CoinTypeB>): u64 {
        abort 0
    }

    public fun liquidity<CoinTypeA, CoinTypeB>(_pool: &Pool<CoinTypeA, CoinTypeB>): u128 {
        abort 0
    }

    public fun current_sqrt_price<CoinTypeA, CoinTypeB>(_pool: &Pool<CoinTypeA, CoinTypeB>): u128 {
        abort 0
    }

    public fun current_tick_index<CoinTypeA, CoinTypeB>(_pool: &Pool<CoinTypeA, CoinTypeB>): I32 {
        abort 0
    }

    public fun fees_growth_global<CoinTypeA, CoinTypeB>(_pool: &Pool<CoinTypeA, CoinTypeB>): (u128, u128) {
        abort 0
    }

    public fun protocol_fee<CoinTypeA, CoinTypeB>(_pool: &Pool<CoinTypeA, CoinTypeB>): (u64, u64) {
        abort 0
    }

    public fun tick_manager<CoinTypeA, CoinTypeB>(_pool: &Pool<CoinTypeA, CoinTypeB>): &TickManager {
        abort 0
    }

    public fun position_manager<CoinTypeA, CoinTypeB>(
        _pool: &Pool<CoinTypeA, CoinTypeB>
    ): &PositionManager {
        abort 0
    }

    public fun rewarder_manager<CoinTypeA, CoinTypeB>(_pool: &Pool<CoinTypeA, CoinTypeB>): &RewarderManager {
        abort 0
    }

    public fun is_pause<CoinTypeA, CoinTypeB>(_pool: &Pool<CoinTypeA, CoinTypeB>): bool {
        abort 0
    }

    public fun index<CoinTypeA, CoinTypeB>(_pool: &Pool<CoinTypeA, CoinTypeB>): u64 {
        abort 0
    }

    public fun url<CoinTypeA, CoinTypeB>(_pool: &Pool<CoinTypeA, CoinTypeB>): String {
        abort 0
    }

    public fun borrow_tick<CoinTypeA, CoinTypeB>(_pool: &Pool<CoinTypeA, CoinTypeB>, _tick_idx: I32): &Tick {
        abort 0
    }

    public fun borrow_position_info<CoinTypeA, CoinTypeB>(
        _pool: &Pool<CoinTypeA, CoinTypeB>,
        _position_id: ID
    ): &PositionInfo {
        abort 0
    }

    /// Get the swap pay amount
    public fun swap_pay_amount<CoinTypeA, CoinTypeB>(_receipt: &FlashSwapReceipt<CoinTypeA, CoinTypeB>): u64 {
        abort 0
    }

    /// Get the ref fee amount
    public fun ref_fee_amount<CoinTypeA, CoinTypeB>(_receipt: &FlashSwapReceipt<CoinTypeA, CoinTypeB>): u64 {
        abort 0
    }

    /// Get the fee from position
    public fun get_position_fee<CoinTypeA, CoinTypeB>(
        _pool: &Pool<CoinTypeA, CoinTypeB>,
        _position_id: ID
    ): (u64, u64) {
        abort 0
    }

    /// Get the points from position
    public fun get_position_points<CoinTypeA, CoinTypeB>(
        _pool: &Pool<CoinTypeA, CoinTypeB>,
        _position_id: ID
    ): u128 {
        abort 0
    }

    /// Get the rewards amount owned from position
    public fun get_position_rewards<CoinTypeA, CoinTypeB>(
        _pool: &Pool<CoinTypeA, CoinTypeB>,
        _position_id: ID
    ): vector<u64> {
        abort 0
    }

    public fun get_position_reward<CoinTypeA, CoinTypeB, CoinTypeC>(
        _pool: &Pool<CoinTypeA, CoinTypeB>,
        _position_id: ID
    ): u64 {
        abort 0
    }

    public fun is_position_exist<CoinTypeA, CoinTypeB>(
        _pool: &Pool<CoinTypeA, CoinTypeB>,
        _position_id: ID
    ): bool {
        abort 0
    }


    public fun calculated_swap_result_amount_out(_calculatedSwapResult: &CalculatedSwapResult): u64 {
        abort 0
    }

    public fun calculated_swap_result_is_exceed(_calculatedSwapResult: &CalculatedSwapResult): bool {
        abort 0
    }

    public fun calculated_swap_result_amount_in(_calculatedSwapResult: &CalculatedSwapResult): u64 {
        abort 0
    }

    public fun calculated_swap_result_after_sqrt_price(_calculatedSwapResult: &CalculatedSwapResult): u128 {
        abort 0
    }

    public fun calculated_swap_result_fee_amount(_calculatedSwapResult: &CalculatedSwapResult): u64 {
        abort 0
    }

    public fun calculate_swap_result_step_results(_calculatedSwapResult: &CalculatedSwapResult): &vector<SwapStepResult> {
        abort 0
    }

    public fun calculated_swap_result_steps_length(_calculatedSwapResult: &CalculatedSwapResult): u64 {
        abort 0
    }


    public fun calculated_swap_result_step_swap_result(
        calculatedSwapResult: &CalculatedSwapResult,
        index: u64
    ): &SwapStepResult {
        return vector::borrow<SwapStepResult>(&calculatedSwapResult.step_results, index)
    }

    public fun step_swap_result_amount_in(stepSwapResult: &SwapStepResult): u64 {
        return stepSwapResult.amount_in
    }

    public fun step_swap_result_amount_out(stepSwapResult: &SwapStepResult): u64 {
        return stepSwapResult.amount_out
    }

    public fun step_swap_result_fee_amount(stepSwapResult: &SwapStepResult): u64 {
        return stepSwapResult.fee_amount
    }

    public fun step_swap_result_current_sqrt_price(stepSwapResult: &SwapStepResult): u128 {
        return stepSwapResult.current_sqrt_price
    }

    public fun step_swap_result_target_sqrt_price(stepSwapResult: &SwapStepResult): u128 {
        return stepSwapResult.target_sqrt_price
    }

    public fun step_swap_result_current_liquidity(stepSwapResult: &SwapStepResult): u128 {
        return stepSwapResult.current_liquidity
    }

    public fun step_swap_result_remainder_amount(stepSwapResult: &SwapStepResult): u64 {
        return stepSwapResult.remainder_amount
    }
}