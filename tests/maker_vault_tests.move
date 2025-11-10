#[test_only]
module odyssey_sui::maker_vault_tests;

use sui::test_scenario::{Self, ctx};
use sui::test_utils::assert_eq;
use std::option::{none, some};
use std::string;

use odyssey_sui::maker_vault::{Self, MakerVaultAdminCap};
use odyssey_sui::test_utils::{
    setup_test_scenario,
    get_test_addresses,
    cleanup_scenario,
    setup_maker_vault,
    setup_complete_system,
    setup_funded_scenario,
    mint_ithaca,
    mint_usdc,
    register_test_maker,
    deposit_maker_collateral,
    validate_coin_and_transfer_back,
    create_test_note,
    USDC,
    ITHACA,
};
use odyssey_sui::types;
use odyssey_sui::order;
use odyssey_sui::order::CoordinatorCap;
use odyssey_sui::test_utils::get_minimum_stake;
use odyssey_sui::test_utils::deposit_trader_funds;
use odyssey_sui::test_utils::get_btc_symbol;
use odyssey_sui::maker_vault::EMakerNotAvailable;
use odyssey_sui::test_utils::get_eth_symbol;


// ==========
// Initialization Tests
// ==========
#[test]
public fun test_initialize_success() {
    let mut scenario = setup_test_scenario();
    let (governor, _, _, _, _, _, _) = get_test_addresses();

    let (maker_vault, order_cap) = setup_maker_vault(&mut scenario, none());
    transfer::public_transfer(order_cap, governor);

    // Verify vault initialization
    test_scenario::next_tx(&mut scenario, governor);
    let total_asset = maker_vault::total_asset_available(&maker_vault);
    assert_eq(total_asset, 0);

    test_scenario::return_shared(maker_vault);
    cleanup_scenario(scenario)
}

#[test]
#[expected_failure(abort_code = maker_vault::ENotZeroAmount)]
public fun test_initialize_fails_with_zero_minimum_stake() {
    let mut scenario = setup_test_scenario();
    let (governor, _, _, _, _, _, _) = get_test_addresses();

    test_scenario::next_tx(&mut scenario, governor);
    maker_vault::test_init(ctx(&mut scenario));

    test_scenario::next_tx(&mut scenario, governor);
    let admin_cap = scenario.take_from_sender<MakerVaultAdminCap>();
    let mut initial_symbols = vector::empty<string::String>();
    vector::push_back(&mut initial_symbols, string::utf8(b"BTC"));
    let order_cap = maker_vault::initialize<USDC, ITHACA>(&admin_cap, 0, initial_symbols, ctx(&mut scenario));
    transfer::public_transfer(order_cap, governor);
    scenario.return_to_sender(admin_cap);

    cleanup_scenario(scenario)
}

// ==========
// Registration & Stake Tests
// ==========
#[test]
public fun test_register_maker_success() {
    let mut scenario = setup_test_scenario();
    let (_, _, _, maker1, _, _, _) = get_test_addresses();
    let (mut maker_vault, maker_order_cap) = setup_maker_vault(&mut scenario, none());
    transfer::public_transfer(maker_order_cap, maker1);

    let stake_amount = get_minimum_stake();
    register_test_maker(&mut scenario, &mut maker_vault, maker1, get_btc_symbol(), stake_amount);
    maker_vault::assert_maker_registered_event(maker1, stake_amount);

    test_scenario::next_tx(&mut scenario, maker1);
    let staked = maker_vault::get_maker_staked_ithaca(&maker_vault, maker1, get_btc_symbol());
    assert_eq(staked, stake_amount);

    let ithaca_balance = maker_vault::vault_ithaca_balance_value(&maker_vault);
    assert_eq(ithaca_balance, stake_amount);

    test_scenario::return_shared(maker_vault);
    cleanup_scenario(scenario)
}

#[test]
#[expected_failure(abort_code = maker_vault::ENotZeroAmount)]
public fun test_cannot_register_with_zero_stake() {
    let mut scenario = setup_test_scenario();
    let (_, _, _, maker1, _, _, _) = get_test_addresses();
    let (mut maker_vault, maker_order_cap) = setup_maker_vault(&mut scenario, none());
    transfer::public_transfer(maker_order_cap, maker1);

    test_scenario::next_tx(&mut scenario, maker1);
    let ithaca_coin = mint_ithaca(&mut scenario, maker1, 0);
    maker_vault::register_maker_symbol(&mut maker_vault, get_btc_symbol(), ithaca_coin, ctx(&mut scenario));

    test_scenario::return_shared(maker_vault);
    cleanup_scenario(scenario)
}

#[test]
#[expected_failure(abort_code = maker_vault::EInsufficientStake)]
public fun test_cannot_register_below_minimum_stake() {
    let mut scenario = setup_test_scenario();
    let (governor, _, _, maker1, _, _, _) = get_test_addresses();

    let (mut maker_vault, maker_order_cap) = setup_maker_vault(&mut scenario, some(1_000_000));
    transfer::public_transfer(maker_order_cap, governor);

    test_scenario::next_tx(&mut scenario, maker1);
    let ithaca_coin = mint_ithaca(&mut scenario, maker1, 999_999);
    maker_vault::register_maker_symbol(&mut maker_vault, get_btc_symbol(), ithaca_coin, ctx(&mut scenario));

    test_scenario::return_shared(maker_vault);
    cleanup_scenario(scenario)
}


#[test]
#[expected_failure(abort_code = maker_vault::EMakerAlreadyRegistered)]
public fun test_cannot_register_twice() {
    let mut scenario = setup_test_scenario();
    let (_, _, _, maker1, _, _, _) = get_test_addresses();
    let (mut maker_vault, maker_order_cap) = setup_maker_vault(&mut scenario, none());
    transfer::public_transfer(maker_order_cap, maker1);

    let stake_amount = get_minimum_stake();
    // First registration succeeds
    register_test_maker(&mut scenario, &mut maker_vault, maker1, get_btc_symbol(), stake_amount);

    // Second registration should abort with EMakerAlreadyRegistered
    test_scenario::next_tx(&mut scenario, maker1);
    let ithaca_again = mint_ithaca(&mut scenario, maker1, stake_amount);
    maker_vault::register_maker_symbol(&mut maker_vault, get_btc_symbol(), ithaca_again, ctx(&mut scenario));

    test_scenario::return_shared(maker_vault);
    cleanup_scenario(scenario)
}

// ==========
// Collateral Deposit Tests
// ==========
#[test]
public fun test_deposit_collateral_success() {
    let mut scenario = setup_test_scenario();
    let (_, _, _, maker1, _, _, _) = get_test_addresses();
    let (mut maker_vault, maker_order_cap) = setup_maker_vault(&mut scenario, none());
    transfer::public_transfer(maker_order_cap, maker1);

    let stake_amount = get_minimum_stake();
    register_test_maker(&mut scenario, &mut maker_vault, maker1, get_btc_symbol(), stake_amount);

    let amount = 1_500_000;
    deposit_maker_collateral(&mut scenario, &mut maker_vault, maker1, get_btc_symbol(), amount);
    maker_vault::assert_collateral_deposited_event(maker1, amount);

    test_scenario::next_tx(&mut scenario, maker1);
    let maker_collateral = maker_vault::get_maker_collateral(&maker_vault, maker1, get_btc_symbol());
    assert_eq(maker_collateral, amount);

    let total_asset = maker_vault::total_asset_available(&maker_vault);
    assert_eq(total_asset, amount);

    test_scenario::return_shared(maker_vault);
    cleanup_scenario(scenario)
}

#[test]
#[expected_failure(abort_code = maker_vault::ENotZeroAmount)]
public fun test_cannot_deposit_zero_amount() {
    let mut scenario = setup_test_scenario();
    let (governor, _, _, maker1, _, _, _) = get_test_addresses();
    let (mut maker_vault, maker_order_cap) = setup_maker_vault(&mut scenario, none());
    transfer::public_transfer(maker_order_cap, governor);

    let stake_amount = get_minimum_stake();
    register_test_maker(&mut scenario, &mut maker_vault, maker1, get_btc_symbol(), stake_amount);

    test_scenario::next_tx(&mut scenario, maker1);
    let usdc_coin = mint_usdc(&mut scenario, maker1, 0);
    maker_vault::deposit_collateral(&mut maker_vault, get_btc_symbol(), usdc_coin, ctx(&mut scenario));

    test_scenario::return_shared(maker_vault);
    cleanup_scenario(scenario)
}

#[test]
#[expected_failure(abort_code = maker_vault::EMakerNotAvailable)]
public fun test_cannot_deposit_without_registration() {
    let mut scenario = setup_test_scenario();
    let (governor, _, _, maker1, _, _, _) = get_test_addresses();
    let (mut maker_vault, maker_order_cap) = setup_maker_vault(&mut scenario, none());
    transfer::public_transfer(maker_order_cap, governor);

    // Maker has not registered yet
    test_scenario::next_tx(&mut scenario, maker1);
    let usdc_coin = mint_usdc(&mut scenario, maker1, 1_000);
    maker_vault::deposit_collateral(&mut maker_vault, get_btc_symbol(), usdc_coin, ctx(&mut scenario));

    test_scenario::return_shared(maker_vault);
    cleanup_scenario(scenario)
}

#[test]
#[expected_failure(abort_code = maker_vault::EMakerNotAvailable)]
public fun test_cannot_deposit_even_with_registration_on_other_asset() {
    let mut scenario = setup_test_scenario();
    let (_, _, _, maker1, _, _, _) = get_test_addresses();
    let (mut maker_vault, maker_order_cap) = setup_maker_vault(&mut scenario, none());
    transfer::public_transfer(maker_order_cap, maker1);

    let stake_amount = get_minimum_stake();
    register_test_maker(&mut scenario, &mut maker_vault, maker1, get_btc_symbol(), stake_amount);

    let amount = 1_500_000;
    let eth_symbol = get_eth_symbol();
    deposit_maker_collateral(&mut scenario, &mut maker_vault, maker1, eth_symbol, amount);

    test_scenario::return_shared(maker_vault);
    cleanup_scenario(scenario)
}

// ==========
// Set Minimum Stake Tests
// ==========
#[test]
public fun test_set_minimum_stake_success() {
    let mut scenario = setup_test_scenario();
    let (governor, _, _, _, _, _, _) = get_test_addresses();
    let (mut maker_vault, maker_order_cap) = setup_maker_vault(&mut scenario, none());
    transfer::public_transfer(maker_order_cap, governor);

    test_scenario::next_tx(&mut scenario, governor);
    let admin_cap = scenario.take_from_sender<MakerVaultAdminCap>();
    let new_min = get_minimum_stake() + 123;
    maker_vault::set_minimum_stake_amount(&admin_cap, &mut maker_vault, new_min);
    maker_vault::assert_minimum_stake_amount_set_event(new_min);
    scenario.return_to_sender(admin_cap);

    test_scenario::next_tx(&mut scenario, governor);
    let current_min = maker_vault::minimum_stake_amount(&maker_vault);
    assert_eq(current_min, new_min);

    test_scenario::return_shared(maker_vault);
    cleanup_scenario(scenario)
}

#[test]
#[expected_failure(abort_code = maker_vault::ENotZeroAmount)]
public fun test_set_minimum_stake_fails_with_zero() {
    let mut scenario = setup_test_scenario();
    let (governor, _, _, _, _, _, _) = get_test_addresses();
    let (mut maker_vault, maker_order_cap) = setup_maker_vault(&mut scenario, none());
    transfer::public_transfer(maker_order_cap, governor);

    test_scenario::next_tx(&mut scenario, governor);
    let admin_cap = scenario.take_from_sender<MakerVaultAdminCap>();
    maker_vault::set_minimum_stake_amount(&admin_cap, &mut maker_vault, 0);
    scenario.return_to_sender(admin_cap);

    test_scenario::return_shared(maker_vault);
    cleanup_scenario(scenario)
}

// ==========
// Set Custom Minimum Stake Tests
// ==========
#[test]
public fun test_set_custom_minimum_stake_success_view_only() {
    let mut scenario = setup_test_scenario();
    let (governor, _, _, maker1, _, _, _) = get_test_addresses();
    let (mut maker_vault, maker_order_cap) = setup_maker_vault(&mut scenario, none());
    transfer::public_transfer(maker_order_cap, governor);

    let default_min = get_minimum_stake();

    // Register maker with stake moderately above default
    let maker_stake = default_min + 5;
    register_test_maker(&mut scenario, &mut maker_vault, maker1, get_btc_symbol(), maker_stake);

    // Set custom min for BTC higher than maker's stake
    test_scenario::next_tx(&mut scenario, governor);
    let admin_cap = scenario.take_from_sender<MakerVaultAdminCap>();
    let btc = get_btc_symbol();
    let eth = get_eth_symbol();
    let custom_btc_min = default_min + 10;
    maker_vault::set_custom_min_stake_amount(&admin_cap, &mut maker_vault, btc, custom_btc_min);
    maker_vault::assert_custom_min_stake_amount_set_event(custom_btc_min);
    scenario.return_to_sender(admin_cap);

    // Verify get_min_stake_amount reflects custom setting
    test_scenario::next_tx(&mut scenario, maker1);
    let min_btc = maker_vault::get_min_stake_amount(&maker_vault, btc);
    assert_eq(min_btc, custom_btc_min);
    let min_eth = maker_vault::get_min_stake_amount(&maker_vault, eth);
    assert_eq(min_eth, default_min);

    test_scenario::return_shared(maker_vault);
    cleanup_scenario(scenario)
}

#[test]
#[expected_failure(abort_code = maker_vault::EInsufficientStake)]
public fun test_custom_minimum_stake_enforced_for_btc_deposit() {
    let mut scenario = setup_test_scenario();
    let (governor, _, _, maker1, _, _, _) = get_test_addresses();
    let (mut maker_vault, maker_order_cap) = setup_maker_vault(&mut scenario, none());
    transfer::public_transfer(maker_order_cap, governor);

    let default_min = get_minimum_stake();

    // Set custom min for BTC higher than maker's stake
    test_scenario::next_tx(&mut scenario, governor);
    let admin_cap = scenario.take_from_sender<MakerVaultAdminCap>();
    let btc = get_btc_symbol();
    let custom_btc_min = default_min + 10;
    maker_vault::set_custom_min_stake_amount(&admin_cap, &mut maker_vault, btc, custom_btc_min);
    scenario.return_to_sender(admin_cap);

    // Attempt to register for BTC collateral should fail due to insufficient stake vs custom min
    let maker_stake = default_min + 5;
    register_test_maker(&mut scenario, &mut maker_vault, maker1, get_btc_symbol(), maker_stake);

    test_scenario::return_shared(maker_vault);
    cleanup_scenario(scenario)
}

#[test]
public fun test_custom_minimum_stake_other_asset_allows_deposit() {
    let mut scenario = setup_test_scenario();
    let (governor, _, _, maker1, _, _, _) = get_test_addresses();
    let (mut maker_vault, maker_order_cap) = setup_maker_vault(&mut scenario, none());
    transfer::public_transfer(maker_order_cap, governor);

    let default_min = get_minimum_stake();

    // Set custom min for BTC higher than maker's stake
    test_scenario::next_tx(&mut scenario, governor);
    let admin_cap = scenario.take_from_sender<MakerVaultAdminCap>();
    let btc = get_btc_symbol();
    let eth = get_eth_symbol();
    let custom_btc_min = default_min + 10;
    maker_vault::set_custom_min_stake_amount(&admin_cap, &mut maker_vault, btc, custom_btc_min);
    scenario.return_to_sender(admin_cap);

    // Register maker with stake moderately above default
    let maker_stake = default_min + 5;
    register_test_maker(&mut scenario, &mut maker_vault, maker1, eth, maker_stake);

    // Deposit ETH collateral should still succeed
    test_scenario::next_tx(&mut scenario, maker1);
    let usdc_eth = mint_usdc(&mut scenario, maker1, 2_000);
    maker_vault::deposit_collateral(&mut maker_vault, eth, usdc_eth, ctx(&mut scenario));
    maker_vault::assert_collateral_deposited_event(maker1, 2_000);

    test_scenario::return_shared(maker_vault);
    cleanup_scenario(scenario)
}

#[test]
#[expected_failure(abort_code = maker_vault::ENotZeroAmount)]
public fun test_set_custom_minimum_stake_fails_with_zero() {
    let mut scenario = setup_test_scenario();
    let (governor, _, _, _, _, _, _) = get_test_addresses();
    let (mut maker_vault, maker_order_cap) = setup_maker_vault(&mut scenario, none());
    transfer::public_transfer(maker_order_cap, governor);

    test_scenario::next_tx(&mut scenario, governor);
    let admin_cap = scenario.take_from_sender<MakerVaultAdminCap>();
    let btc = get_btc_symbol();
    maker_vault::set_custom_min_stake_amount(&admin_cap, &mut maker_vault, btc, 0);
    scenario.return_to_sender(admin_cap);

    test_scenario::return_shared(maker_vault);
    cleanup_scenario(scenario)
}

// ==========
// Collateral Withdraw Tests
// ==========
#[test]
public fun test_withdraw_collateral_success() {
    let mut scenario = setup_test_scenario();
    let (_, _, _, maker1, _, _, _) = get_test_addresses();
    let (vault_unused, mut maker_vault, mut order_manager) = setup_complete_system(&mut scenario, none(), none());

    // Ensure maker registered and deposit collateral
    let stake_amount = get_minimum_stake();
    let btc = get_btc_symbol();
    register_test_maker(&mut scenario, &mut maker_vault, maker1, btc, stake_amount);
    let deposit_amount = 10_000;
    deposit_maker_collateral(&mut scenario, &mut maker_vault, maker1, btc, deposit_amount);

    // pre total assets
    test_scenario::next_tx(&mut scenario, maker1);
    let total_before = maker_vault::total_asset_available(&maker_vault);
    assert_eq(total_before, deposit_amount);

    // Withdraw part of collateral
    test_scenario::next_tx(&mut scenario, maker1);
    let withdraw_amount = 6_000;
    let withdrawn_coin = order::maker_withdraw(&mut order_manager, &mut maker_vault, btc, withdraw_amount, ctx(&mut scenario));
    maker_vault::assert_collateral_withdrawn_event(maker1, withdraw_amount);

    // Validate events/state
    test_scenario::next_tx(&mut scenario, maker1);
    let maker_collateral = maker_vault::get_maker_collateral(&maker_vault, maker1, btc);
    assert_eq(maker_collateral, deposit_amount - withdraw_amount);

    let total_after = maker_vault::total_asset_available(&maker_vault);
    assert_eq(total_after, deposit_amount - withdraw_amount);

    validate_coin_and_transfer_back(&mut scenario, withdrawn_coin, maker1, withdraw_amount);

    test_scenario::return_shared(vault_unused);
    test_scenario::return_shared(maker_vault);
    test_scenario::return_shared(order_manager);
    cleanup_scenario(scenario)
}

#[test]
#[expected_failure(abort_code = maker_vault::ENotZeroAmount)]
public fun test_cannot_withdraw_zero_amount() {
    let mut scenario = setup_test_scenario();
    let (_, _, _, maker1, _, _, _) = get_test_addresses();
    let (vault_unused, mut maker_vault, mut order_manager) = setup_complete_system(&mut scenario, none(), none());

    let stake_amount = get_minimum_stake();
    register_test_maker(&mut scenario, &mut maker_vault, maker1, get_btc_symbol(), stake_amount);
    let deposit_amount = 5_000;
    deposit_maker_collateral(&mut scenario, &mut maker_vault, maker1, get_btc_symbol(), deposit_amount);

    test_scenario::next_tx(&mut scenario, maker1);
    let withdraw_amount = 0;
    let withdrawn_coin = order::maker_withdraw(&mut order_manager, &mut maker_vault, get_btc_symbol(), withdraw_amount, ctx(&mut scenario));
    transfer::public_transfer(withdrawn_coin, maker1);

    test_scenario::return_shared(vault_unused);
    test_scenario::return_shared(maker_vault);
    test_scenario::return_shared(order_manager);
    cleanup_scenario(scenario)
}

#[test]
#[expected_failure(abort_code = maker_vault::EMakerNotAvailable)]
public fun test_cannot_withdraw_if_not_registered_maker() {
    let mut scenario = setup_test_scenario();
    let (_, _, _, maker1, _, _, _) = get_test_addresses();
    let (vault_unused, mut maker_vault, mut order_manager) = setup_complete_system(&mut scenario, none(), none());

    // maker1 not registered
    test_scenario::next_tx(&mut scenario, maker1);
    let coin_out = order::maker_withdraw(&mut order_manager, &mut maker_vault, get_btc_symbol(), 1, ctx(&mut scenario));
    transfer::public_transfer(coin_out, maker1);

    test_scenario::return_shared(vault_unused);
    test_scenario::return_shared(maker_vault);
    test_scenario::return_shared(order_manager);
    cleanup_scenario(scenario)
}

#[test]
#[expected_failure(abort_code = maker_vault::EInsufficientCollateral)]
public fun test_cannot_withdraw_more_than_available() {
    let mut scenario = setup_test_scenario();
    let (_, _, _, maker1, _, _, _) = get_test_addresses();
    let (vault_unused, mut maker_vault, mut order_manager) = setup_complete_system(&mut scenario, none(), none());

    let stake_amount = get_minimum_stake();
    register_test_maker(&mut scenario, &mut maker_vault, maker1, get_btc_symbol(), stake_amount);
    let deposit_amount = 7_000;
    deposit_maker_collateral(&mut scenario, &mut maker_vault, maker1, get_btc_symbol(), deposit_amount);

    // Attempt to withdraw more than available (no locked amounts)
    test_scenario::next_tx(&mut scenario, maker1);
    let withdraw_amount = deposit_amount + 1;
    let withdrawn_coin = order::maker_withdraw(&mut order_manager, &mut maker_vault, get_btc_symbol(), withdraw_amount, ctx(&mut scenario));
    transfer::public_transfer(withdrawn_coin, maker1);

    test_scenario::return_shared(vault_unused);
    test_scenario::return_shared(maker_vault);
    test_scenario::return_shared(order_manager);
    cleanup_scenario(scenario)
}

#[test]
#[expected_failure(abort_code = maker_vault::EInsufficientCollateral)]
public fun test_cannot_withdraw_locked_balance() {
    let mut scenario = setup_test_scenario();
    let (_, trader1, _, maker1, _, _, coordinator) = get_test_addresses();
    let (mut vault, mut maker_vault, mut order_manager, clock, maker_deposit_amount, symbol) = setup_funded_scenario(&mut scenario, none());

    // Create a note to lock maker balance
    test_scenario::next_tx(&mut scenario, trader1);
    let amount = 1_000;
    deposit_trader_funds(&mut scenario, &mut vault, trader1, amount);

    test_scenario::next_tx(&mut scenario, coordinator);
    let order_amount = 300;
    let note = create_test_note(trader1, maker1, order_amount, order_amount * 3, clock.timestamp_ms());
    let coordinator_cap = scenario.take_from_sender<CoordinatorCap>();
    order::create_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note, &clock, ctx(&mut scenario));
    scenario.return_to_sender(coordinator_cap);

    // Attempt to withdraw more than withdrawable (deposit - locked)
    test_scenario::next_tx(&mut scenario, maker1);
    let withdraw_amount = maker_deposit_amount - (order_amount * 2) + 1; // win_amount = 2x amount locked
    let withdrawn = order::maker_withdraw(&mut order_manager, &mut maker_vault, symbol, withdraw_amount, ctx(&mut scenario));
    validate_coin_and_transfer_back(&mut scenario, withdrawn, maker1, withdraw_amount);

    clock.destroy_for_testing();
    test_scenario::return_shared(vault);
    test_scenario::return_shared(maker_vault);
    test_scenario::return_shared(order_manager);
    cleanup_scenario(scenario)
}

#[test]
public fun test_withdraw_all_remaining_after_lock_success() {
    let mut scenario = setup_test_scenario();
    let (_, trader1, _, maker1, _, _, coordinator) = get_test_addresses();
    let (mut vault, mut maker_vault, mut order_manager, clock, maker_deposit_amount, symbol) = setup_funded_scenario(&mut scenario, none());

    // Create a note to lock maker balance
    test_scenario::next_tx(&mut scenario, trader1);
    let amount = 1_000;
    deposit_trader_funds(&mut scenario, &mut vault, trader1, amount);

    test_scenario::next_tx(&mut scenario, coordinator);
    let order_amount = 300;
    let note = create_test_note(trader1, maker1, order_amount, order_amount * 3, clock.timestamp_ms());
    let coordinator_cap = scenario.take_from_sender<CoordinatorCap>();
    order::create_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note, &clock, ctx(&mut scenario));
    scenario.return_to_sender(coordinator_cap);

    // Withdraw exactly the remaining after lock
    test_scenario::next_tx(&mut scenario, maker1);
    let withdraw_amount = maker_deposit_amount - (order_amount * 2);
    let withdrawn = order::maker_withdraw(&mut order_manager, &mut maker_vault, symbol, withdraw_amount, ctx(&mut scenario));
    maker_vault::assert_collateral_withdrawn_event(maker1, withdraw_amount);
    validate_coin_and_transfer_back(&mut scenario, withdrawn, maker1, withdraw_amount);

    test_scenario::next_tx(&mut scenario, maker1);
    let remaining = maker_vault::get_maker_collateral(&maker_vault, maker1, symbol);
    assert_eq(remaining, order_amount * 2);

    clock.destroy_for_testing();
    test_scenario::return_shared(vault);
    test_scenario::return_shared(maker_vault);
    test_scenario::return_shared(order_manager);
    cleanup_scenario(scenario)
}

// ==========
// Unregister Maker
// ==========

#[test]
public fun test_unregister_success() {
    let mut scenario = setup_test_scenario();
    let (_, _, _, maker1, _, _, _) = get_test_addresses();
    let (mut maker_vault, maker_order_cap) = setup_maker_vault(&mut scenario, none());
    transfer::public_transfer(maker_order_cap, maker1);

    let stake_amount = get_minimum_stake();
    register_test_maker(&mut scenario, &mut maker_vault, maker1, get_btc_symbol(), stake_amount);
    register_test_maker(&mut scenario, &mut maker_vault, maker1, get_eth_symbol(), stake_amount);

    // Unregister should return all staked ITHACA and clear maker entry
    test_scenario::next_tx(&mut scenario, maker1);
    let withdrawn = maker_vault::unregister_maker(&mut maker_vault, get_btc_symbol(), ctx(&mut scenario));
    maker_vault::assert_maker_unregistered_event(maker1);
    let value = sui::coin::value(&withdrawn);
    assert_eq(value, stake_amount);
    transfer::public_transfer(withdrawn, maker1);

    test_scenario::next_tx(&mut scenario, maker1);
    let staked_after = maker_vault::get_maker_staked_ithaca(&maker_vault, maker1, get_btc_symbol());
    assert_eq(staked_after, 0);

    // The eth maker entry should still exist
    let staked_eth = maker_vault::get_maker_staked_ithaca(&maker_vault, maker1, get_eth_symbol());
    assert_eq(staked_eth, stake_amount);

    test_scenario::return_shared(maker_vault);
    cleanup_scenario(scenario)
}

#[test]
#[expected_failure(abort_code = maker_vault::ECollateralMustBeZero)]
public fun test_cannot_unregister_with_nonzero_collateral() {
    let mut scenario = setup_test_scenario();
    let (governor, _, _, maker1, _, _, _) = get_test_addresses();
    let (mut maker_vault, maker_order_cap) = setup_maker_vault(&mut scenario, none());
    transfer::public_transfer(maker_order_cap, governor);

    let stake_amount = get_minimum_stake();
    register_test_maker(&mut scenario, &mut maker_vault, maker1, get_btc_symbol(), stake_amount);

    // Deposit some collateral so unregister fails
    let deposit_amount = 1_000_000;
    deposit_maker_collateral(&mut scenario, &mut maker_vault, maker1, get_btc_symbol(), deposit_amount);

    test_scenario::next_tx(&mut scenario, maker1);
    let withdrawn = maker_vault::unregister_maker(&mut maker_vault, get_btc_symbol(), ctx(&mut scenario));
    transfer::public_transfer(withdrawn, maker1);

    test_scenario::return_shared(maker_vault);
    cleanup_scenario(scenario)
}

#[test]
public fun test_unregister_success_after_withdrawing_all_collateral() {
    let mut scenario = setup_test_scenario();
    let (_, _, _, maker1, _, _, _) = get_test_addresses();
    let (mut maker_vault, maker_order_cap) = setup_maker_vault(&mut scenario, none());
    transfer::public_transfer(maker_order_cap, maker1);

    let stake_amount = get_minimum_stake();
    register_test_maker(&mut scenario, &mut maker_vault, maker1, get_btc_symbol(), stake_amount);

    // Deposit and then withdraw all collateral
    let deposit_amount = 50_000;
    deposit_maker_collateral(&mut scenario, &mut maker_vault, maker1, get_btc_symbol(), deposit_amount);

    let (vault_tmp, maker_vault_tmp, mut order_manager) = setup_complete_system(&mut scenario, none(), none());
    test_scenario::return_shared(vault_tmp);
    test_scenario::return_shared(maker_vault_tmp);

    test_scenario::next_tx(&mut scenario, maker1);
    let withdrawn_all = order::maker_withdraw(&mut order_manager, &mut maker_vault, get_btc_symbol(), deposit_amount, ctx(&mut scenario));
    transfer::public_transfer(withdrawn_all, maker1);

    test_scenario::return_shared(order_manager);

    test_scenario::next_tx(&mut scenario, maker1);
    let withdrawn = maker_vault::unregister_maker(&mut maker_vault, get_btc_symbol(), ctx(&mut scenario));
    let value = sui::coin::value(&withdrawn);
    assert_eq(value, stake_amount);
    transfer::public_transfer(withdrawn, maker1);

    test_scenario::return_shared(maker_vault);
    cleanup_scenario(scenario)
}

// ==========
// Views
// ==========
#[test]
public fun test_get_withdrawable_balance_with_locked_view() {
    let mut scenario = setup_test_scenario();
    let (governor, _, _, maker1, _, _, _) = get_test_addresses();
    let (mut maker_vault, maker_order_cap) = setup_maker_vault(&mut scenario, none());

    let stake_amount = get_minimum_stake();
    register_test_maker(&mut scenario, &mut maker_vault, maker1, get_btc_symbol(), stake_amount);

    let deposit_amount = 9_000;
    deposit_maker_collateral(&mut scenario, &mut maker_vault, maker1, get_btc_symbol(), deposit_amount);

    test_scenario::next_tx(&mut scenario, maker1);
    // Use zero-locked and then some locked to validate subtraction
    let withdrawable_0 = maker_vault::get_withdrawable_balance_with_locked(
        &maker_vault,
        maker1,
        get_btc_symbol(),
        0
    );
    assert_eq(withdrawable_0, deposit_amount);

    let locked = 4_000;
    let withdrawable_locked = maker_vault::get_withdrawable_balance_with_locked(
        &maker_vault,
        maker1,
        get_btc_symbol(),
        locked
    );
    assert_eq(withdrawable_locked, deposit_amount - locked);

    transfer::public_transfer(maker_order_cap, governor);

    test_scenario::return_shared(maker_vault);
    cleanup_scenario(scenario)
}
