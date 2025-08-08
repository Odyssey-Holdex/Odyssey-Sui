#[test_only]
module odyssey_sui::vault_tests;

use sui::test_scenario::{Self, ctx};
use odyssey_sui::vault::{Self};
use odyssey_sui::test_utils::{setup_test_scenario, mint_usdc, get_test_addresses, cleanup_scenario};
use odyssey_sui::test_utils::setup_vault;
use sui::test_utils::assert_eq;
use odyssey_sui::test_utils::deposit_trader_funds;
use odyssey_sui::test_utils::setup_complete_system;
use std::option::none;
use odyssey_sui::order;
use odyssey_sui::test_utils::validate_coin_and_transfer_back;
use odyssey_sui::test_utils::setup_funded_scenario;
use odyssey_sui::test_utils::create_test_note;
use odyssey_sui::order::CoordinatorCap;

// ==========
// Initialization Tests
// ==========
#[test]
public fun test_initialize_success() {
    let mut scenario = setup_test_scenario();
    let (governor, _, _, _, _, _, _) = get_test_addresses();
    let (vault, order_cap) = setup_vault(&mut scenario);
    transfer::public_transfer(order_cap, governor);

    // Verify vault initialization
    test_scenario::next_tx(&mut scenario, governor);
    let total_asset = vault::total_asset_available(&vault);
    assert_eq(total_asset, 0);

    test_scenario::return_shared(vault);

    cleanup_scenario(scenario)
}

// ==========
// Deposit Tests
// ==========
#[test]
public fun test_deposit_success() {
    let mut scenario = setup_test_scenario();
    let (governor, trader1, _, _, _, _, _) = get_test_addresses();
    let (mut vault, order_cap) = setup_vault(&mut scenario);
    transfer::public_transfer(order_cap, governor);

    // Mint USDC and deposit into vault
    let amount = 1000;
    test_scenario::next_tx(&mut scenario, trader1);
    let usdc_coin = mint_usdc(&mut scenario, trader1, amount);
    vault::deposit(&mut vault, usdc_coin, ctx(&mut scenario));
    vault::assert_deposited_event(trader1, amount);

    // Verify deposit
    test_scenario::next_tx(&mut scenario, trader1);
    let total_asset = vault::total_asset_available(&vault);
    assert_eq(total_asset, amount);
    let balance = vault::taker_balance(&vault, trader1);
    assert_eq(balance, amount);

    test_scenario::return_shared(vault);
    cleanup_scenario(scenario)
}


#[test]
#[expected_failure(abort_code = vault::ENotZeroAmount)]
public fun test_cannot_deposit_zero_amount() {
    let mut scenario = setup_test_scenario();
    let (governor, trader1, _, _, _, _, _) = get_test_addresses();
    let (mut vault, order_cap) = setup_vault(&mut scenario);
    transfer::public_transfer(order_cap, governor);

    // Attempt to deposit zero amount
    test_scenario::next_tx(&mut scenario, trader1);
    let usdc_coin = mint_usdc(&mut scenario, trader1, 0);

    vault::deposit(&mut vault, usdc_coin, ctx(&mut scenario));

    test_scenario::return_shared(vault);
    cleanup_scenario(scenario)
}

// ==========
// Withdraw Tests
// ==========
#[test]
public fun test_withdraw_success() {
    let mut scenario = setup_test_scenario();
    let (_, trader1, trader2, _, _, _, _) = get_test_addresses();
    let (mut vault, maker_vault, mut order_manager) = setup_complete_system(&mut scenario, none());
    test_scenario::return_shared(maker_vault);

    // Mint USDC and deposit into vault
    let amount = 1000;
    let amount2 = 1500;
    deposit_trader_funds(&mut scenario, &mut vault, trader1, amount);
    deposit_trader_funds(&mut scenario, &mut vault, trader2, amount2);

    let total_asset_before = vault::total_asset_available(&vault);
    assert_eq(total_asset_before, amount + amount2);

    // Withdraw from vault, not all balance
    test_scenario::next_tx(&mut scenario, trader1);
    let withdraw_amount = 800;
    let withdrawn_coin = order::taker_withdraw(&mut order_manager, &mut vault, withdraw_amount, ctx(&mut scenario));
    vault::assert_withdrawn_event(trader1, withdraw_amount);

    let total_asset = vault::total_asset_available(&vault);
    assert_eq(total_asset, total_asset_before - withdraw_amount);
    let balance = vault::taker_balance(&vault, trader1);
    assert_eq(balance, amount - withdraw_amount);
    let balance2 = vault::taker_balance(&vault, trader2);
    assert_eq(balance2, amount2);

    // Verify the withdrawn coin
    validate_coin_and_transfer_back(&mut scenario, withdrawn_coin, trader1, withdraw_amount);

    // Withdraw from vault, all balance
    test_scenario::next_tx(&mut scenario, trader2);
    let withdraw_amount = amount2;
    let withdrawn_coin = order::taker_withdraw(&mut order_manager, &mut vault, withdraw_amount, ctx(&mut scenario));
    vault::assert_withdrawn_event(trader2, withdraw_amount);
    let total_asset_after = vault::total_asset_available(&vault);
    assert_eq(total_asset_after, total_asset - withdraw_amount);
    let balance2_after = vault::taker_balance(&vault, trader2);
    assert_eq(balance2_after, 0);

    // Verify the withdrawn coin
    validate_coin_and_transfer_back(&mut scenario, withdrawn_coin, trader2, withdraw_amount);

    test_scenario::return_shared(vault);
    test_scenario::return_shared(order_manager);
    cleanup_scenario(scenario)
}



#[test]
#[expected_failure(abort_code = vault::ENotZeroAmount)]
public fun test_cannot_withdraw_zero_amount() {
    let mut scenario = setup_test_scenario();
    let (_, trader1, trader2, _, _, _, _) = get_test_addresses();
    let (mut vault, maker_vault, mut order_manager) = setup_complete_system(&mut scenario, none());
    test_scenario::return_shared(maker_vault);

    // Mint USDC and deposit into vault
    let amount = 1000;
    let amount2 = 1500;
    deposit_trader_funds(&mut scenario, &mut vault, trader1, amount);
    deposit_trader_funds(&mut scenario, &mut vault, trader2, amount2);

    let total_asset_before = vault::total_asset_available(&vault);
    assert_eq(total_asset_before, amount + amount2);

    // Withdraw from vault
    test_scenario::next_tx(&mut scenario, trader1);
    let withdraw_amount = 0;
    let withdrawn_coin = order::taker_withdraw(&mut order_manager, &mut vault, withdraw_amount, ctx(&mut scenario));
    transfer::public_transfer(withdrawn_coin, trader1);

    test_scenario::return_shared(vault);
    test_scenario::return_shared(order_manager);
    cleanup_scenario(scenario)
}

#[test]
#[expected_failure(abort_code = vault::EInsufficientBalance)]
public fun test_can_withdraw_remaining_nonlocked_balance() {
    let mut scenario = setup_test_scenario();
    let (_, trader1, trader2, _, _, _, _) = get_test_addresses();
    let (mut vault, maker_vault, mut order_manager) = setup_complete_system(&mut scenario, none());
    test_scenario::return_shared(maker_vault);

    // Mint USDC and deposit into vault
    let amount = 1000;
    let amount2 = 1500;
    deposit_trader_funds(&mut scenario, &mut vault, trader1, amount);
    deposit_trader_funds(&mut scenario, &mut vault, trader2, amount2);

    let total_asset_before = vault::total_asset_available(&vault);
    assert_eq(total_asset_before, amount + amount2);

    // Attempt to withdraw more than balance
    test_scenario::next_tx(&mut scenario, trader1);
    let withdraw_amount = 1200;

    let withdrawn = order::taker_withdraw(&mut order_manager, &mut vault, withdraw_amount, ctx(&mut scenario));
    transfer::public_transfer(withdrawn, trader1);

    test_scenario::return_shared(vault);
    test_scenario::return_shared(order_manager);
    cleanup_scenario(scenario)
}

#[test]
#[expected_failure(abort_code = vault::EInsufficientBalance)]
public fun test_cannot_withdraw_locked_balance() {
    let mut scenario = setup_test_scenario();
    let (_, trader1, _, maker1, _, _, coordinator) = get_test_addresses();
    let (mut vault, mut maker_vault, mut order_manager, clock, _) = setup_funded_scenario(&mut scenario, none());

    // Create an order to lock some balance
    test_scenario::next_tx(&mut scenario, trader1);
    let deposit_amount = 1000;
    deposit_trader_funds(&mut scenario, &mut vault, trader1, deposit_amount);

    test_scenario::next_tx(&mut scenario, coordinator);
    let order_amount = 300;
    let note = create_test_note(trader1, maker1, order_amount, order_amount * 3, clock.timestamp_ms());
    let coordinator_cap = scenario.take_from_sender<CoordinatorCap>();
    order::create_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note, &clock, ctx(&mut scenario));
    scenario.return_to_sender(coordinator_cap);

    // Attempt to withdraw more than withdrawable balance
    test_scenario::next_tx(&mut scenario, trader1);
    let withdraw_amount = deposit_amount - order_amount + 1;
    let withdrawn = order::taker_withdraw(&mut order_manager, &mut vault, withdraw_amount, ctx(&mut scenario));
    validate_coin_and_transfer_back(&mut scenario, withdrawn, trader1, withdraw_amount);

    clock.destroy_for_testing();
    test_scenario::return_shared(maker_vault);
    test_scenario::return_shared(vault);
    test_scenario::return_shared(order_manager);
    cleanup_scenario(scenario)
}
