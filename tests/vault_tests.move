#[test_only]
module odyssey_sui::vault_tests;

use sui::test_scenario::{Self, ctx};
use odyssey_sui::vault::{Self};
use odyssey_sui::test_utils::{setup_test_scenario, mint_usdc, get_test_addresses, cleanup_scenario};
use odyssey_sui::test_utils::setup_vault;
use sui::test_utils::assert_eq;

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
