#[test_only]
module odyssey_sui::maker_vault_tests;

use sui::test_scenario::{Self, ctx};
use sui::test_utils::assert_eq;
use std::option::{none, some};

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
    let order_cap = maker_vault::initialize<USDC, ITHACA>(&admin_cap, 0, ctx(&mut scenario));
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
    register_test_maker(&mut scenario, &mut maker_vault, maker1, stake_amount);
    maker_vault::assert_maker_registered_event(maker1, stake_amount);

    test_scenario::next_tx(&mut scenario, maker1);
    let staked = maker_vault::get_maker_info(&maker_vault, maker1);
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
    maker_vault::register_maker(&mut maker_vault, ithaca_coin, ctx(&mut scenario));

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
    maker_vault::register_maker(&mut maker_vault, ithaca_coin, ctx(&mut scenario));

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
    register_test_maker(&mut scenario, &mut maker_vault, maker1, stake_amount);

    // Second registration should abort with EMakerAlreadyRegistered
    test_scenario::next_tx(&mut scenario, maker1);
    let ithaca_again = mint_ithaca(&mut scenario, maker1, stake_amount);
    maker_vault::register_maker(&mut maker_vault, ithaca_again, ctx(&mut scenario));

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
    register_test_maker(&mut scenario, &mut maker_vault, maker1, stake_amount);

    let amount = 1_500_000;
    deposit_maker_collateral(&mut scenario, &mut maker_vault, maker1, types::tradable_asset_btc(), amount);
    maker_vault::assert_collateral_deposited_event(maker1, amount);

    test_scenario::next_tx(&mut scenario, maker1);
    let maker_collateral = maker_vault::get_maker_collateral(&maker_vault, maker1, &types::tradable_asset_btc());
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
    register_test_maker(&mut scenario, &mut maker_vault, maker1, stake_amount);

    test_scenario::next_tx(&mut scenario, maker1);
    let usdc_coin = mint_usdc(&mut scenario, maker1, 0);
    maker_vault::deposit_collateral(&mut maker_vault, types::tradable_asset_btc(), usdc_coin, ctx(&mut scenario));

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
    maker_vault::deposit_collateral(&mut maker_vault, types::tradable_asset_btc(), usdc_coin, ctx(&mut scenario));

    test_scenario::return_shared(maker_vault);
    cleanup_scenario(scenario)
}

// ==========
// Stake Ithaca Tests
// ==========
#[test]
public fun test_stake_ithaca_success() {
    let mut scenario = setup_test_scenario();
    let (_, _, _, maker1, _, _, _) = get_test_addresses();
    let (mut maker_vault, maker_order_cap) = setup_maker_vault(&mut scenario, none());
    transfer::public_transfer(maker_order_cap, maker1);

    let stake_amount = get_minimum_stake();
    register_test_maker(&mut scenario, &mut maker_vault, maker1, stake_amount);

    test_scenario::next_tx(&mut scenario, maker1);
    let extra = 1_000_000;
    let ithaca_payment = mint_ithaca(&mut scenario, maker1, extra);
    maker_vault::stake_ithaca(&mut maker_vault, ithaca_payment, ctx(&mut scenario));
    maker_vault::assert_ithaca_staked_event(maker1, extra);

    test_scenario::next_tx(&mut scenario, maker1);
    let staked_after = maker_vault::get_maker_info(&maker_vault, maker1);
    assert_eq(staked_after, stake_amount + extra);
    let ithaca_balance_after = maker_vault::vault_ithaca_balance_value(&maker_vault);
    assert_eq(ithaca_balance_after, stake_amount + extra);

    test_scenario::return_shared(maker_vault);
    cleanup_scenario(scenario)
}

#[test]
#[expected_failure(abort_code = maker_vault::EMakerNotAvailable)]
public fun test_stake_ithaca_only_called_by_maker() {
    let mut scenario = setup_test_scenario();
    let (_, _, _, _, maker2, _, _) = get_test_addresses();
    let (mut maker_vault, maker_order_cap) = setup_maker_vault(&mut scenario, none());
    transfer::public_transfer(maker_order_cap, maker2);

    // maker2 is not registered
    test_scenario::next_tx(&mut scenario, maker2);
    let extra = 1_000_000;
    let ithaca_payment = mint_ithaca(&mut scenario, maker2, extra);
    maker_vault::stake_ithaca(&mut maker_vault, ithaca_payment, ctx(&mut scenario));

    test_scenario::return_shared(maker_vault);
    cleanup_scenario(scenario)
}

#[test]
#[expected_failure(abort_code = maker_vault::ENotZeroAmount)]
public fun test_cannot_stake_zero_amount() {
    let mut scenario = setup_test_scenario();
    let (_, _, _, maker1, _, _, _) = get_test_addresses();
    let (mut maker_vault, maker_order_cap) = setup_maker_vault(&mut scenario, none());
    transfer::public_transfer(maker_order_cap, maker1);

    let stake_amount = get_minimum_stake();
    register_test_maker(&mut scenario, &mut maker_vault, maker1, stake_amount);

    test_scenario::next_tx(&mut scenario, maker1);
    let ithaca_payment = mint_ithaca(&mut scenario, maker1, 0);
    maker_vault::stake_ithaca(&mut maker_vault, ithaca_payment, ctx(&mut scenario));

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
    register_test_maker(&mut scenario, &mut maker_vault, maker1, maker_stake);

    // Set custom min for BTC higher than maker's stake
    test_scenario::next_tx(&mut scenario, governor);
    let admin_cap = scenario.take_from_sender<MakerVaultAdminCap>();
    let btc = types::tradable_asset_btc();
    let eth = types::tradable_asset_eth();
    let custom_btc_min = default_min + 10;
    maker_vault::set_custom_min_stake_amount(&admin_cap, &mut maker_vault, btc, custom_btc_min);
    maker_vault::assert_custom_min_stake_amount_set_event(custom_btc_min);
    scenario.return_to_sender(admin_cap);

    // Verify get_min_stake_amount reflects custom setting
    test_scenario::next_tx(&mut scenario, maker1);
    let min_btc = maker_vault::get_min_stake_amount(&maker_vault, &btc);
    assert_eq(min_btc, custom_btc_min);
    let min_eth = maker_vault::get_min_stake_amount(&maker_vault, &eth);
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

    // Register maker with stake moderately above default
    let maker_stake = default_min + 5;
    register_test_maker(&mut scenario, &mut maker_vault, maker1, maker_stake);

    // Set custom min for BTC higher than maker's stake
    test_scenario::next_tx(&mut scenario, governor);
    let admin_cap = scenario.take_from_sender<MakerVaultAdminCap>();
    let btc = types::tradable_asset_btc();
    let custom_btc_min = default_min + 10;
    maker_vault::set_custom_min_stake_amount(&admin_cap, &mut maker_vault, btc, custom_btc_min);
    scenario.return_to_sender(admin_cap);

    // Attempt to deposit BTC collateral should fail due to insufficient stake vs custom min
    test_scenario::next_tx(&mut scenario, maker1);
    let usdc_btc = mint_usdc(&mut scenario, maker1, 1_000);
    maker_vault::deposit_collateral(&mut maker_vault, btc, usdc_btc, ctx(&mut scenario));

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

    // Register maker with stake moderately above default
    let maker_stake = default_min + 5;
    register_test_maker(&mut scenario, &mut maker_vault, maker1, maker_stake);

    // Set custom min for BTC higher than maker's stake
    test_scenario::next_tx(&mut scenario, governor);
    let admin_cap = scenario.take_from_sender<MakerVaultAdminCap>();
    let btc = types::tradable_asset_btc();
    let eth = types::tradable_asset_eth();
    let custom_btc_min = default_min + 10;
    maker_vault::set_custom_min_stake_amount(&admin_cap, &mut maker_vault, btc, custom_btc_min);
    scenario.return_to_sender(admin_cap);

    // Deposit ETH collateral should still succeed
    test_scenario::next_tx(&mut scenario, maker1);
    let usdc_eth = mint_usdc(&mut scenario, maker1, 2_000);
    maker_vault::deposit_collateral(&mut maker_vault, eth, usdc_eth, ctx(&mut scenario));
    maker_vault::assert_collateral_deposited_event(maker1, 2_000);

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
    register_test_maker(&mut scenario, &mut maker_vault, maker1, stake_amount);
    let deposit_amount = 10_000;
    deposit_maker_collateral(&mut scenario, &mut maker_vault, maker1, types::tradable_asset_btc(), deposit_amount);

    // pre total assets
    test_scenario::next_tx(&mut scenario, maker1);
    let total_before = maker_vault::total_asset_available(&maker_vault);
    assert_eq(total_before, deposit_amount);

    // Withdraw part of collateral
    test_scenario::next_tx(&mut scenario, maker1);
    let withdraw_amount = 6_000;
    let withdrawn_coin = order::maker_withdraw(&mut order_manager, &mut maker_vault, types::tradable_asset_btc(), withdraw_amount, ctx(&mut scenario));
    maker_vault::assert_collateral_withdrawn_event(maker1, withdraw_amount);

    // Validate events/state
    test_scenario::next_tx(&mut scenario, maker1);
    let maker_collateral = maker_vault::get_maker_collateral(&maker_vault, maker1, &types::tradable_asset_btc());
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
    register_test_maker(&mut scenario, &mut maker_vault, maker1, stake_amount);
    let deposit_amount = 5_000;
    deposit_maker_collateral(&mut scenario, &mut maker_vault, maker1, types::tradable_asset_btc(), deposit_amount);

    test_scenario::next_tx(&mut scenario, maker1);
    let withdraw_amount = 0;
    let withdrawn_coin = order::maker_withdraw(&mut order_manager, &mut maker_vault, types::tradable_asset_btc(), withdraw_amount, ctx(&mut scenario));
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
    let coin_out = order::maker_withdraw(&mut order_manager, &mut maker_vault, types::tradable_asset_btc(), 1, ctx(&mut scenario));
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
    register_test_maker(&mut scenario, &mut maker_vault, maker1, stake_amount);
    let deposit_amount = 7_000;
    deposit_maker_collateral(&mut scenario, &mut maker_vault, maker1, types::tradable_asset_btc(), deposit_amount);

    // Attempt to withdraw more than available (no locked amounts)
    test_scenario::next_tx(&mut scenario, maker1);
    let withdraw_amount = deposit_amount + 1;
    let withdrawn_coin = order::maker_withdraw(&mut order_manager, &mut maker_vault, types::tradable_asset_btc(), withdraw_amount, ctx(&mut scenario));
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
    let (mut vault, mut maker_vault, mut order_manager, clock, maker_deposit_amount) = setup_funded_scenario(&mut scenario, none());

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
    let withdrawn = order::maker_withdraw(&mut order_manager, &mut maker_vault, types::tradable_asset_btc(), withdraw_amount, ctx(&mut scenario));
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
    let (mut vault, mut maker_vault, mut order_manager, clock, maker_deposit_amount) = setup_funded_scenario(&mut scenario, none());

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
    let withdrawn = order::maker_withdraw(&mut order_manager, &mut maker_vault, types::tradable_asset_btc(), withdraw_amount, ctx(&mut scenario));
    maker_vault::assert_collateral_withdrawn_event(maker1, withdraw_amount);
    validate_coin_and_transfer_back(&mut scenario, withdrawn, maker1, withdraw_amount);

    test_scenario::next_tx(&mut scenario, maker1);
    let remaining = maker_vault::get_maker_collateral(&maker_vault, maker1, &types::tradable_asset_btc());
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
    register_test_maker(&mut scenario, &mut maker_vault, maker1, stake_amount);

    // Unregister should return all staked ITHACA and clear maker entry
    test_scenario::next_tx(&mut scenario, maker1);
    let withdrawn = maker_vault::unregister_maker(&mut maker_vault, ctx(&mut scenario));
    maker_vault::assert_maker_unregistered_event(maker1);
    let value = sui::coin::value(&withdrawn);
    assert_eq(value, stake_amount);
    transfer::public_transfer(withdrawn, maker1);

    test_scenario::next_tx(&mut scenario, maker1);
    let staked_after = maker_vault::get_maker_info(&maker_vault, maker1);
    assert_eq(staked_after, 0);

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
    register_test_maker(&mut scenario, &mut maker_vault, maker1, stake_amount);

    // Deposit some collateral so unregister fails
    let deposit_amount = 1_000_000;
    deposit_maker_collateral(&mut scenario, &mut maker_vault, maker1, types::tradable_asset_btc(), deposit_amount);

    test_scenario::next_tx(&mut scenario, maker1);
    let withdrawn = maker_vault::unregister_maker(&mut maker_vault, ctx(&mut scenario));
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
    register_test_maker(&mut scenario, &mut maker_vault, maker1, stake_amount);

    // Deposit and then withdraw all collateral
    let deposit_amount = 50_000;
    deposit_maker_collateral(&mut scenario, &mut maker_vault, maker1, types::tradable_asset_btc(), deposit_amount);

    let (vault_tmp, maker_vault_tmp, mut order_manager) = setup_complete_system(&mut scenario, none(), none());
    test_scenario::return_shared(vault_tmp);
    test_scenario::return_shared(maker_vault_tmp);

    test_scenario::next_tx(&mut scenario, maker1);
    let withdrawn_all = order::maker_withdraw(&mut order_manager, &mut maker_vault, types::tradable_asset_btc(), deposit_amount, ctx(&mut scenario));
    transfer::public_transfer(withdrawn_all, maker1);

    test_scenario::return_shared(order_manager);

    test_scenario::next_tx(&mut scenario, maker1);
    let withdrawn = maker_vault::unregister_maker(&mut maker_vault, ctx(&mut scenario));
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
    register_test_maker(&mut scenario, &mut maker_vault, maker1, stake_amount);

    let deposit_amount = 9_000;
    deposit_maker_collateral(&mut scenario, &mut maker_vault, maker1, types::tradable_asset_btc(), deposit_amount);

    test_scenario::next_tx(&mut scenario, maker1);
    // Use zero-locked and then some locked to validate subtraction
    let withdrawable_0 = maker_vault::get_withdrawable_balance_with_locked(
        &maker_order_cap,
        &maker_vault,
        maker1,
        &types::tradable_asset_btc(),
        0
    );
    assert_eq(withdrawable_0, deposit_amount);

    let locked = 4_000;
    let withdrawable_locked = maker_vault::get_withdrawable_balance_with_locked(
        &maker_order_cap,
        &maker_vault,
        maker1,
        &types::tradable_asset_btc(),
        locked
    );
    assert_eq(withdrawable_locked, deposit_amount - locked);

    transfer::public_transfer(maker_order_cap, governor);

    test_scenario::return_shared(maker_vault);
    cleanup_scenario(scenario)
}

// ==========
// Multi-Asset Stake Tests
// ==========

#[test]
public fun test_multi_asset_deposit_with_sufficient_stake() {
    let mut scenario = setup_test_scenario();
    let (governor, _, _, maker1, _, _, _) = get_test_addresses();
    let (mut maker_vault, maker_order_cap) = setup_maker_vault(&mut scenario, none());
    transfer::public_transfer(maker_order_cap, governor);

    let min_stake = get_minimum_stake();
    let total_stake = min_stake * 3; // Enough for 3 assets
    
    // Register maker with enough stake for 3 assets
    register_test_maker(&mut scenario, &mut maker_vault, maker1, total_stake);

    // First asset deposit should succeed
    test_scenario::next_tx(&mut scenario, maker1);
    let btc_amount = 1_000_000;
    let usdc_btc = mint_usdc(&mut scenario, maker1, btc_amount);
    maker_vault::deposit_collateral(&mut maker_vault, types::tradable_asset_btc(), usdc_btc, ctx(&mut scenario));
    maker_vault::assert_collateral_deposited_event(maker1, btc_amount);

    // Second asset deposit should succeed
    test_scenario::next_tx(&mut scenario, maker1);
    let eth_amount = 2_000_000;
    let usdc_eth = mint_usdc(&mut scenario, maker1, eth_amount);
    maker_vault::deposit_collateral(&mut maker_vault, types::tradable_asset_eth(), usdc_eth, ctx(&mut scenario));
    maker_vault::assert_collateral_deposited_event(maker1, eth_amount);

    // Third asset deposit should succeed
    test_scenario::next_tx(&mut scenario, maker1);
    let sol_amount = 3_000_000;
    let usdc_sol = mint_usdc(&mut scenario, maker1, sol_amount);
    maker_vault::deposit_collateral(&mut maker_vault, types::tradable_asset_sol(), usdc_sol, ctx(&mut scenario));
    maker_vault::assert_collateral_deposited_event(maker1, sol_amount);

    // Verify all deposits were successful
    test_scenario::next_tx(&mut scenario, maker1);
    let btc_collateral = maker_vault::get_maker_collateral(&maker_vault, maker1, &types::tradable_asset_btc());
    let eth_collateral = maker_vault::get_maker_collateral(&maker_vault, maker1, &types::tradable_asset_eth());
    let sol_collateral = maker_vault::get_maker_collateral(&maker_vault, maker1, &types::tradable_asset_sol());
    assert_eq(btc_collateral, btc_amount);
    assert_eq(eth_collateral, eth_amount);
    assert_eq(sol_collateral, sol_amount);

    test_scenario::return_shared(maker_vault);
    cleanup_scenario(scenario)
}

#[test]
#[expected_failure(abort_code = maker_vault::EInsufficientStake)]
public fun test_multi_asset_deposit_insufficient_stake_for_second_asset() {
    let mut scenario = setup_test_scenario();
    let (governor, _, _, maker1, _, _, _) = get_test_addresses();
    let (mut maker_vault, maker_order_cap) = setup_maker_vault(&mut scenario, none());
    transfer::public_transfer(maker_order_cap, governor);

    let min_stake = get_minimum_stake();
    let total_stake = min_stake + (min_stake / 2); // Only enough for 1.5 assets
    
    // Register maker with insufficient stake for 2 assets
    register_test_maker(&mut scenario, &mut maker_vault, maker1, total_stake);

    // First asset deposit should succeed
    test_scenario::next_tx(&mut scenario, maker1);
    let btc_amount = 1_000_000;
    let usdc_btc = mint_usdc(&mut scenario, maker1, btc_amount);
    maker_vault::deposit_collateral(&mut maker_vault, types::tradable_asset_btc(), usdc_btc, ctx(&mut scenario));

    // Second asset deposit should fail due to insufficient stake
    test_scenario::next_tx(&mut scenario, maker1);
    let eth_amount = 2_000_000;
    let usdc_eth = mint_usdc(&mut scenario, maker1, eth_amount);
    maker_vault::deposit_collateral(&mut maker_vault, types::tradable_asset_eth(), usdc_eth, ctx(&mut scenario));

    test_scenario::return_shared(maker_vault);
    cleanup_scenario(scenario)
}

#[test]
#[expected_failure(abort_code = maker_vault::EInsufficientStake)]
public fun test_multi_asset_deposit_insufficient_stake_for_third_asset() {
    let mut scenario = setup_test_scenario();
    let (governor, _, _, maker1, _, _, _) = get_test_addresses();
    let (mut maker_vault, maker_order_cap) = setup_maker_vault(&mut scenario, none());
    transfer::public_transfer(maker_order_cap, governor);

    let min_stake = get_minimum_stake();
    let total_stake = min_stake * 2 + (min_stake / 2); // Only enough for 2.5 assets
    
    // Register maker with insufficient stake for 3 assets
    register_test_maker(&mut scenario, &mut maker_vault, maker1, total_stake);

    // First two asset deposits should succeed
    test_scenario::next_tx(&mut scenario, maker1);
    let btc_amount = 1_000_000;
    let usdc_btc = mint_usdc(&mut scenario, maker1, btc_amount);
    maker_vault::deposit_collateral(&mut maker_vault, types::tradable_asset_btc(), usdc_btc, ctx(&mut scenario));

    test_scenario::next_tx(&mut scenario, maker1);
    let eth_amount = 2_000_000;
    let usdc_eth = mint_usdc(&mut scenario, maker1, eth_amount);
    maker_vault::deposit_collateral(&mut maker_vault, types::tradable_asset_eth(), usdc_eth, ctx(&mut scenario));

    // Third asset deposit should fail due to insufficient stake
    test_scenario::next_tx(&mut scenario, maker1);
    let sol_amount = 3_000_000;
    let usdc_sol = mint_usdc(&mut scenario, maker1, sol_amount);
    maker_vault::deposit_collateral(&mut maker_vault, types::tradable_asset_sol(), usdc_sol, ctx(&mut scenario));

    test_scenario::return_shared(maker_vault);
    cleanup_scenario(scenario)
}

#[test]
public fun test_multi_asset_deposit_with_custom_stake_amounts() {
    let mut scenario = setup_test_scenario();
    let (governor, _, _, maker1, _, _, _) = get_test_addresses();
    let (mut maker_vault, maker_order_cap) = setup_maker_vault(&mut scenario, none());
    transfer::public_transfer(maker_order_cap, governor);

    let default_min_stake = get_minimum_stake();
    let custom_btc_stake = default_min_stake * 2; // BTC requires double stake
    let custom_eth_stake = default_min_stake * 3; // ETH requires triple stake
    
    // Set custom minimum stake amounts
    test_scenario::next_tx(&mut scenario, governor);
    let admin_cap = scenario.take_from_sender<MakerVaultAdminCap>();
    maker_vault::set_custom_min_stake_amount(&admin_cap, &mut maker_vault, types::tradable_asset_btc(), custom_btc_stake);
    maker_vault::set_custom_min_stake_amount(&admin_cap, &mut maker_vault, types::tradable_asset_eth(), custom_eth_stake);
    scenario.return_to_sender(admin_cap);

    // Register maker with enough stake for BTC + ETH + SOL (2x + 3x + 1x = 6x default)
    let total_stake = default_min_stake * 6;
    register_test_maker(&mut scenario, &mut maker_vault, maker1, total_stake);

    // BTC deposit should succeed (uses 2x stake)
    test_scenario::next_tx(&mut scenario, maker1);
    let btc_amount = 1_000_000;
    let usdc_btc = mint_usdc(&mut scenario, maker1, btc_amount);
    maker_vault::deposit_collateral(&mut maker_vault, types::tradable_asset_btc(), usdc_btc, ctx(&mut scenario));
    maker_vault::assert_collateral_deposited_event(maker1, btc_amount);

    // ETH deposit should succeed (uses 3x stake)
    test_scenario::next_tx(&mut scenario, maker1);
    let eth_amount = 2_000_000;
    let usdc_eth = mint_usdc(&mut scenario, maker1, eth_amount);
    maker_vault::deposit_collateral(&mut maker_vault, types::tradable_asset_eth(), usdc_eth, ctx(&mut scenario));
    maker_vault::assert_collateral_deposited_event(maker1, eth_amount);

    // SOL deposit should succeed (uses 1x stake)
    test_scenario::next_tx(&mut scenario, maker1);
    let sol_amount = 3_000_000;
    let usdc_sol = mint_usdc(&mut scenario, maker1, sol_amount);
    maker_vault::deposit_collateral(&mut maker_vault, types::tradable_asset_sol(), usdc_sol, ctx(&mut scenario));
    maker_vault::assert_collateral_deposited_event(maker1, sol_amount);

    test_scenario::return_shared(maker_vault);
    cleanup_scenario(scenario)
}

#[test]
#[expected_failure(abort_code = maker_vault::EInsufficientStake)]
public fun test_multi_asset_deposit_insufficient_stake_with_custom_amounts() {
    let mut scenario = setup_test_scenario();
    let (governor, _, _, maker1, _, _, _) = get_test_addresses();
    let (mut maker_vault, maker_order_cap) = setup_maker_vault(&mut scenario, none());
    transfer::public_transfer(maker_order_cap, governor);

    let default_min_stake = get_minimum_stake();
    let custom_btc_stake = default_min_stake * 2; // BTC requires double stake
    
    // Set custom minimum stake amount for BTC
    test_scenario::next_tx(&mut scenario, governor);
    let admin_cap = scenario.take_from_sender<MakerVaultAdminCap>();
    maker_vault::set_custom_min_stake_amount(&admin_cap, &mut maker_vault, types::tradable_asset_btc(), custom_btc_stake);
    scenario.return_to_sender(admin_cap);

    // Register maker with enough stake for BTC + ETH but not BTC + ETH + SOL
    let total_stake = default_min_stake * 3; // 2x for BTC + 1x for ETH = 3x total
    register_test_maker(&mut scenario, &mut maker_vault, maker1, total_stake);

    // BTC deposit should succeed (uses 2x stake)
    test_scenario::next_tx(&mut scenario, maker1);
    let btc_amount = 1_000_000;
    let usdc_btc = mint_usdc(&mut scenario, maker1, btc_amount);
    maker_vault::deposit_collateral(&mut maker_vault, types::tradable_asset_btc(), usdc_btc, ctx(&mut scenario));

    // ETH deposit should succeed (uses 1x stake)
    test_scenario::next_tx(&mut scenario, maker1);
    let eth_amount = 2_000_000;
    let usdc_eth = mint_usdc(&mut scenario, maker1, eth_amount);
    maker_vault::deposit_collateral(&mut maker_vault, types::tradable_asset_eth(), usdc_eth, ctx(&mut scenario));

    // SOL deposit should fail (no remaining stake)
    test_scenario::next_tx(&mut scenario, maker1);
    let sol_amount = 3_000_000;
    let usdc_sol = mint_usdc(&mut scenario, maker1, sol_amount);
    maker_vault::deposit_collateral(&mut maker_vault, types::tradable_asset_sol(), usdc_sol, ctx(&mut scenario));

    test_scenario::return_shared(maker_vault);
    cleanup_scenario(scenario)
}

#[test]
public fun test_multi_asset_deposit_after_withdrawing_collateral() {
    let mut scenario = setup_test_scenario();
    let (_, _, _, maker1, _, _, _) = get_test_addresses();
    let (vault_unused, mut maker_vault, mut order_manager) = setup_complete_system(&mut scenario, none(), none());

    let min_stake = get_minimum_stake();
    let total_stake = min_stake * 2; // Enough for 2 assets
    
    // Register maker with enough stake for 2 assets
    register_test_maker(&mut scenario, &mut maker_vault, maker1, total_stake);

    // Deposit BTC and ETH
    test_scenario::next_tx(&mut scenario, maker1);
    let btc_amount = 1_000_000;
    let usdc_btc = mint_usdc(&mut scenario, maker1, btc_amount);
    maker_vault::deposit_collateral(&mut maker_vault, types::tradable_asset_btc(), usdc_btc, ctx(&mut scenario));

    test_scenario::next_tx(&mut scenario, maker1);
    let eth_amount = 2_000_000;
    let usdc_eth = mint_usdc(&mut scenario, maker1, eth_amount);
    maker_vault::deposit_collateral(&mut maker_vault, types::tradable_asset_eth(), usdc_eth, ctx(&mut scenario));

    // Withdraw all BTC collateral
    test_scenario::next_tx(&mut scenario, maker1);
    let withdrawn_btc = order::maker_withdraw(&mut order_manager, &mut maker_vault, types::tradable_asset_btc(), btc_amount, ctx(&mut scenario));
    validate_coin_and_transfer_back(&mut scenario, withdrawn_btc, maker1, btc_amount);

    // Now should be able to deposit SOL (BTC stake is freed up)
    test_scenario::next_tx(&mut scenario, maker1);
    let sol_amount = 3_000_000;
    let usdc_sol = mint_usdc(&mut scenario, maker1, sol_amount);
    maker_vault::deposit_collateral(&mut maker_vault, types::tradable_asset_sol(), usdc_sol, ctx(&mut scenario));
    maker_vault::assert_collateral_deposited_event(maker1, sol_amount);

    // Verify final state
    test_scenario::next_tx(&mut scenario, maker1);
    let btc_collateral = maker_vault::get_maker_collateral(&maker_vault, maker1, &types::tradable_asset_btc());
    let eth_collateral = maker_vault::get_maker_collateral(&maker_vault, maker1, &types::tradable_asset_eth());
    let sol_collateral = maker_vault::get_maker_collateral(&maker_vault, maker1, &types::tradable_asset_sol());
    assert_eq(btc_collateral, 0);
    assert_eq(eth_collateral, eth_amount);
    assert_eq(sol_collateral, sol_amount);

    test_scenario::return_shared(vault_unused);
    test_scenario::return_shared(maker_vault);
    test_scenario::return_shared(order_manager);
    cleanup_scenario(scenario)
}

#[test]
public fun test_can_deposit_collateral_view_function() {
    let mut scenario = setup_test_scenario();
    let (governor, _, _, maker1, _, _, _) = get_test_addresses();
    let (mut maker_vault, maker_order_cap) = setup_maker_vault(&mut scenario, none());
    transfer::public_transfer(maker_order_cap, governor);

    let min_stake = get_minimum_stake();
    let total_stake = min_stake * 2; // Enough for 2 assets
    
    // Register maker
    register_test_maker(&mut scenario, &mut maker_vault, maker1, total_stake);

    // Test can_deposit_collateral view function BEFORE any deposits
    test_scenario::next_tx(&mut scenario, maker1);
    let can_deposit_btc = maker_vault::can_deposit_collateral(&maker_vault, maker1, &types::tradable_asset_btc());
    let can_deposit_eth = maker_vault::can_deposit_collateral(&maker_vault, maker1, &types::tradable_asset_eth());
    let can_deposit_sol = maker_vault::can_deposit_collateral(&maker_vault, maker1, &types::tradable_asset_sol());
    assert_eq(can_deposit_btc, true); // Can deposit BTC (has 2x stake, needs 1x)
    assert_eq(can_deposit_eth, true); // Can deposit ETH (has 2x stake, needs 1x)
    assert_eq(can_deposit_sol, true); // Can deposit SOL (has 2x stake, needs 1x)

    // Deposit BTC and verify view function prediction was correct
    test_scenario::next_tx(&mut scenario, maker1);
    let btc_amount = 1_000_000;
    let usdc_btc = mint_usdc(&mut scenario, maker1, btc_amount);
    maker_vault::deposit_collateral(&mut maker_vault, types::tradable_asset_btc(), usdc_btc, ctx(&mut scenario));
    maker_vault::assert_collateral_deposited_event(maker1, btc_amount);

    // Test can_deposit_collateral view function AFTER BTC deposit
    test_scenario::next_tx(&mut scenario, maker1);
    let can_deposit_btc_after = maker_vault::can_deposit_collateral(&maker_vault, maker1, &types::tradable_asset_btc());
    let can_deposit_eth_after = maker_vault::can_deposit_collateral(&maker_vault, maker1, &types::tradable_asset_eth());
    let can_deposit_sol_after = maker_vault::can_deposit_collateral(&maker_vault, maker1, &types::tradable_asset_sol());
    assert_eq(can_deposit_btc_after, true); // Can still deposit BTC (already has it)
    assert_eq(can_deposit_eth_after, true); // Can deposit ETH (1 stake remaining)
    assert_eq(can_deposit_sol_after, true); // Can deposit SOL (1 stake remaining)

    // Deposit ETH and verify view function prediction was correct
    test_scenario::next_tx(&mut scenario, maker1);
    let eth_amount = 2_000_000;
    let usdc_eth = mint_usdc(&mut scenario, maker1, eth_amount);
    maker_vault::deposit_collateral(&mut maker_vault, types::tradable_asset_eth(), usdc_eth, ctx(&mut scenario));
    maker_vault::assert_collateral_deposited_event(maker1, eth_amount);

    // Test can_deposit_collateral view function AFTER both deposits
    test_scenario::next_tx(&mut scenario, maker1);
    let can_deposit_btc_final = maker_vault::can_deposit_collateral(&maker_vault, maker1, &types::tradable_asset_btc());
    let can_deposit_eth_final = maker_vault::can_deposit_collateral(&maker_vault, maker1, &types::tradable_asset_eth());
    let can_deposit_sol_final = maker_vault::can_deposit_collateral(&maker_vault, maker1, &types::tradable_asset_sol());
    assert_eq(can_deposit_btc_final, true); // Can still deposit BTC (already has it)
    assert_eq(can_deposit_eth_final, true); // Can still deposit ETH (already has it)
    assert_eq(can_deposit_sol_final, false); // Cannot deposit SOL (no stake remaining)

    test_scenario::return_shared(maker_vault);
    cleanup_scenario(scenario)
}

