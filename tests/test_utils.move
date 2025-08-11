#[test_only]
module odyssey_sui::test_utils;

use sui::test_scenario::{Self, Scenario, ctx};
use sui::clock::{Self, Clock};
use sui::coin::{Self, Coin};
use odyssey_sui::types::{Self, Note, TradableAsset, Direction};
use odyssey_sui::vault::{Self, Vault, VaultAdminCap, OrderCap};
use odyssey_sui::maker_vault::{Self, MakerVault, MakerVaultAdminCap, MakerOrderCap};
use odyssey_sui::order::{Self, OrderManager, OrderAdminCap};
use sui::test_utils::assert_eq;
use std::option::none;

// Test token types
public struct USDC has drop {}
public struct ITHACA has drop {}

// Constants for testing
const DAY_MS: u64 = 24 * 60 * 60 * 1000;
const START_MS: u64 = DAY_MS * 5; // day 5 in milliseconds
const HOUR_MS: u64 = 60 * 60 * 1000;
const MINIMUM_STAKE: u64 = 200_000_000; // 200 ITHACA (with 6 decimals)

// Test addresses
const GOVERNOR: address = @0xa11ce;
const TRADER_1: address = @0xb0b;
const TRADER_2: address = @0xc0c;
const MAKER_1: address = @0xd1d;
const MAKER_2: address = @0xe2e;
const TREASURY: address = @0xfee;
const COORDINATOR: address = @0xc00;

/// Setup basic test scenario with multiple actors
#[test_only]
public fun setup_test_scenario(): Scenario {
    let scenario = test_scenario::begin(GOVERNOR);
    scenario
}

/// Create and mint test coins for an address
#[test_only]
public fun mint_usdc(scenario: &mut Scenario, recipient: address, amount: u64): Coin<USDC> {
    test_scenario::next_tx(scenario, GOVERNOR);
    let coin = coin::mint_for_testing<USDC>(amount, ctx(scenario));
    test_scenario::next_tx(scenario, recipient);
    coin
}

#[test_only]
public fun mint_ithaca(scenario: &mut Scenario, recipient: address, amount: u64): Coin<ITHACA> {
    test_scenario::next_tx(scenario, GOVERNOR);
    let coin = coin::mint_for_testing<ITHACA>(amount, ctx(scenario));
    test_scenario::next_tx(scenario, recipient);
    coin
}

/// Initialize vault system
#[test_only]
public fun setup_vault(scenario: &mut Scenario): (Vault<USDC>, OrderCap) {
    let (governor, _, _, _, _, _, _) = get_test_addresses();
    
    test_scenario::next_tx(scenario, governor);
    vault::test_init(ctx(scenario));

    test_scenario::next_tx(scenario, governor);
    let vault_admin_cap = scenario.take_from_sender<VaultAdminCap>();
    let order_cap = vault::initialize<USDC>(&vault_admin_cap, ctx(scenario));
    scenario.return_to_sender(vault_admin_cap);

    test_scenario::next_tx(scenario, governor);
    assert!(test_scenario::has_most_recent_shared<Vault<USDC>>());
    let vault = scenario.take_shared<Vault<USDC>>();

    (vault, order_cap)
}

/// Initialize maker vault system
#[test_only]
public fun setup_maker_vault(scenario: &mut Scenario, mut minimum_stake: Option<u64>): (MakerVault<USDC, ITHACA>, MakerOrderCap) {
    let (governor, _, _, _, _, _, _) = get_test_addresses();
    
    test_scenario::next_tx(scenario, governor);
    maker_vault::test_init(ctx(scenario));

    test_scenario::next_tx(scenario, governor);
    let maker_vault_admin_cap = scenario.take_from_sender<MakerVaultAdminCap>();
    let minimum_stake_amount = if (option::is_some(&minimum_stake)) {
        let amount = option::extract(&mut minimum_stake);
        amount
    } else {
        MINIMUM_STAKE
    };
    let maker_order_cap = maker_vault::initialize<USDC, ITHACA>(&maker_vault_admin_cap, minimum_stake_amount, ctx(scenario));
    scenario.return_to_sender(maker_vault_admin_cap);

    test_scenario::next_tx(scenario, governor);
    assert!(test_scenario::has_most_recent_shared<MakerVault<USDC, ITHACA>>());
    let maker_vault = scenario.take_shared<MakerVault<USDC, ITHACA>>();

    (maker_vault, maker_order_cap)
}

/// Initialize order manager
#[test_only]
public fun setup_order_manager(
    scenario: &mut Scenario,
    vault_order_cap: OrderCap,
    maker_order_cap: MakerOrderCap,
    mut custom_treasury: Option<address>
): (OrderManager<USDC>) {
    let (governor, _, _, _, _, treasury, coordinator) = get_test_addresses();

    test_scenario::next_tx(scenario, governor);
    order::test_init(ctx(scenario));

    let used_treasury: address = if (option::is_some(&custom_treasury)) {
        let treasury_address = option::extract(&mut custom_treasury);
        treasury_address
    } else {
        treasury
    };

    test_scenario::next_tx(scenario, governor);
    let order_admin_cap = scenario.take_from_sender<OrderAdminCap>();
    let coordinator_cap = order::initialize<USDC>(&order_admin_cap, vault_order_cap, maker_order_cap, used_treasury, ctx(scenario));
    transfer::public_transfer(coordinator_cap, coordinator);
    scenario.return_to_sender(order_admin_cap);

    test_scenario::next_tx(scenario, governor);
    assert!(test_scenario::has_most_recent_shared<OrderManager<USDC>>());
    let order_manager = scenario.take_shared<OrderManager<USDC>>();

    (order_manager)
}

/// Complete system setup
#[test_only]
public fun setup_complete_system(scenario: &mut Scenario, minimum_stake: Option<u64>, custom_treasury: Option<address>): (
    Vault<USDC>,
    MakerVault<USDC, ITHACA>,
    OrderManager<USDC>
) {
    let (vault, order_cap) = setup_vault(scenario);
    let (maker_vault, maker_order_cap) = setup_maker_vault(scenario, minimum_stake);
    let (order_manager) = setup_order_manager(
        scenario, 
        order_cap,
        maker_order_cap,
        custom_treasury
    );
    
    (vault, maker_vault, order_manager)
}

/// Create a test clock with current timestamp
#[test_only]
public fun create_test_clock(scenario: &mut Scenario, timestamp_ms: u64): Clock {
    test_scenario::next_tx(scenario, GOVERNOR);
    let mut clock = clock::create_for_testing(ctx(scenario));
    clock.set_for_testing(timestamp_ms);
    (clock)
}

/// Register a maker in the maker vault
#[test_only]
public fun register_test_maker(
    scenario: &mut Scenario,
    maker_vault: &mut MakerVault<USDC, ITHACA>,
    maker: address,
    stake_amount: u64
) {
    test_scenario::next_tx(scenario, maker);
    let ithaca_coin = mint_ithaca(scenario, maker, stake_amount);
    maker_vault::register_maker(maker_vault, ithaca_coin, ctx(scenario));
}

/// Deposit collateral for a maker
#[test_only]
public fun deposit_maker_collateral(
    scenario: &mut Scenario,
    maker_vault: &mut MakerVault<USDC, ITHACA>,
    maker: address,
    asset: TradableAsset,
    amount: u64
) {
    test_scenario::next_tx(scenario, maker);
    let usdc_coin = mint_usdc(scenario, maker, amount);
    maker_vault::deposit_collateral(maker_vault, asset, usdc_coin, ctx(scenario));
}

/// Deposit funds for a trader
#[test_only]
public fun deposit_trader_funds(
    scenario: &mut Scenario,
    vault: &mut Vault<USDC>,
    trader: address,
    amount: u64
) {
    test_scenario::next_tx(scenario, trader);
    let usdc_coin = mint_usdc(scenario, trader, amount);
    vault::deposit(vault, usdc_coin, ctx(scenario));
}

/// Create a test note with default values
#[test_only]
public fun create_test_note(
    taker: address,
    maker: address,
    amount: u64,
    win_payout: u64,
    day_to_expire: u64
): Note {
    types::new_note(
        taker,                              // taker
        maker,                              // maker  
        types::tradable_asset_btc(),        // asset (BTC)
        types::direction_up(),              // direction (UP)
        amount,                             // amount
        84000000000000,                     // starting_price (84k USD, 9 decimal precision)
        15000000000,                        // spread (15 USD, 9 decimal precision)
        win_payout,                         // win_payout
        START_MS + day_to_expire * DAY_MS,  // expiry_time
        0,                                  // nonce
        amount,                             // refund_payout (full refund)
        10000000000,                        // almost_win_spread (10 USD, 9 decimal precision)
        amount + (win_payout - amount) / 2, // almost_win_payout (halfway)
        START_MS                            // start_time
    )
}

/// Create a test note with custom parameters
#[test_only]
public fun create_custom_note(
    taker: address,
    maker: address,
    asset: TradableAsset,
    direction: Direction,
    amount: u64,
    starting_price: u64,
    spread: u64,
    win_payout: u64,
    expiry_time: u64,
    refund_payout: u64,
    almost_win_spread: u64,
    almost_win_payout: u64
): Note {
    types::new_note(
        taker,
        maker,
        asset,
        direction,
        amount,
        starting_price,
        spread,
        win_payout,
        expiry_time,
        0, // nonce
        refund_payout,
        almost_win_spread,
        almost_win_payout,
        expiry_time - DAY_MS // start_time
    )
}

/// Setup a complete trading scenario with funded accounts
#[test_only]
public fun setup_funded_scenario(scenario: &mut Scenario, minimum_stake: Option<u64>): (
    Vault<USDC>,
    MakerVault<USDC, ITHACA>,
    OrderManager<USDC>,
    Clock,
    u64
) {
    let (vault, mut maker_vault, order_manager) = setup_complete_system(scenario, minimum_stake, none());    
    let clock = create_test_clock(scenario, START_MS); // Arbitrary timestamp

    // Register and fund maker
    register_test_maker(scenario, &mut maker_vault, MAKER_1, MINIMUM_STAKE);
    let maker_deposit_amount = 50_000_000_000_000; // 50,000 USDC with 9 decimal precision
    deposit_maker_collateral(scenario, &mut maker_vault, MAKER_1, types::tradable_asset_btc(), maker_deposit_amount);
    
    (vault, maker_vault, order_manager, clock, maker_deposit_amount)
}

#[test_only]
public fun validate_coin_and_transfer_back(
    scenario: &mut Scenario,
    coin: Coin<USDC>,
    recipient: address,
    expected_amount: u64
) {
    test_scenario::next_tx(scenario, recipient);
    let value = sui::coin::value(&coin);
    assert_eq(value, expected_amount);
    transfer::public_transfer(coin, recipient);
}

#[test_only]
public fun get_minimum_stake(): u64 {
    MINIMUM_STAKE
}

/// Advance clock time
#[test_only]
public fun advance_time(clock: &mut Clock, ms: u64) {
    clock::increment_for_testing(clock, ms);
}

/// Get test addresses for easy access
#[test_only]
public fun get_test_addresses(): (address, address, address, address, address, address, address) {
    (GOVERNOR, TRADER_1, TRADER_2, MAKER_1, MAKER_2, TREASURY, COORDINATOR)
}

/// Helper to get current timestamp plus days
#[test_only]
public fun timestamp_plus_days(clock: &Clock, days: u64): u64 {
    clock::timestamp_ms(clock) + (days * DAY_MS)
}

/// Helper to get current timestamp plus hours  
#[test_only]
public fun timestamp_plus_hours(clock: &Clock, hours: u64): u64 {
    clock::timestamp_ms(clock) + (hours * HOUR_MS)
}

/// Set both taker and maker fee percentages for testing
#[test_only]
public fun set_fee_percentages(
    scenario: &mut Scenario,
    order_manager: &mut OrderManager<USDC>,
    taker_fee_percentage: u64,
    maker_fee_percentage: u64
) {
    let (governor, _, _, _, _, _, _) = get_test_addresses();
    
    test_scenario::next_tx(scenario, governor);
    let admin_cap = scenario.take_from_sender<OrderAdminCap>();
    order::set_taker_fee_percentage(&admin_cap, order_manager, taker_fee_percentage);
    order::set_maker_fee_percentage(&admin_cap, order_manager, maker_fee_percentage);
    scenario.return_to_sender(admin_cap);
}

/// Cleanup test scenario
#[test_only]
public fun cleanup_scenario(scenario: Scenario) {
    test_scenario::end(scenario);
}
