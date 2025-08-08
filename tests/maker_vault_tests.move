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

    // Manually call initialize with zero to ensure abort happens before any objects are created
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

    let stake_amount = 200_000_000; // matches default in setup_maker_vault
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
    // Set a custom minimum stake via setup helper
    let (mut maker_vault, maker_order_cap) = setup_maker_vault(&mut scenario, some(1_000_000));
    transfer::public_transfer(maker_order_cap, governor);

    test_scenario::next_tx(&mut scenario, maker1);
    let ithaca_coin = mint_ithaca(&mut scenario, maker1, 999_999);
    maker_vault::register_maker(&mut maker_vault, ithaca_coin, ctx(&mut scenario));

    test_scenario::return_shared(maker_vault);
    cleanup_scenario(scenario)
}

#[test]
public fun test_unregister_success() {
    let mut scenario = setup_test_scenario();
    let (_, _, _, maker1, _, _, _) = get_test_addresses();
    let (mut maker_vault, maker_order_cap) = setup_maker_vault(&mut scenario, none());
    transfer::public_transfer(maker_order_cap, maker1);

    let stake_amount = 200_000_000;
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

    let stake_amount = 200_000_000;
    register_test_maker(&mut scenario, &mut maker_vault, maker1, stake_amount);

    // Deposit some collateral so unregister fails
    let deposit_amount = 1_000_000;
    deposit_maker_collateral(&mut scenario, &mut maker_vault, maker1, types::tradable_asset_btc(), deposit_amount);

    test_scenario::next_tx(&mut scenario, maker1);
    let withdrawn = maker_vault::unregister_maker(&mut maker_vault, ctx(&mut scenario));
    // ensure type checker sees the coin (unreachable due to abort)
    transfer::public_transfer(withdrawn, maker1);

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

    let stake_amount = 200_000_000;
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

    let stake_amount = 200_000_000;
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
// Collateral Withdraw Tests
// ==========
#[test]
public fun test_withdraw_collateral_success() {
    let mut scenario = setup_test_scenario();
    let (_, _, _, maker1, _, _, _) = get_test_addresses();
    let (mut vault_unused, mut maker_vault, mut order_manager) = setup_complete_system(&mut scenario, none());

    // Ensure maker registered and deposit collateral
    let stake_amount = 200_000_000;
    register_test_maker(&mut scenario, &mut maker_vault, maker1, stake_amount);
    let deposit_amount = 10_000;
    deposit_maker_collateral(&mut scenario, &mut maker_vault, maker1, types::tradable_asset_btc(), deposit_amount);

    // Withdraw part of collateral via order manager API (uses locked=0 by default)
    test_scenario::next_tx(&mut scenario, maker1);
    let withdraw_amount = 6_000;
    let withdrawn_coin = order::maker_withdraw(&mut order_manager, &mut maker_vault, types::tradable_asset_btc(), withdraw_amount, ctx(&mut scenario));
    maker_vault::assert_collateral_withdrawn_event(maker1, withdraw_amount);

    // Validate events/state
    test_scenario::next_tx(&mut scenario, maker1);
    let maker_collateral = maker_vault::get_maker_collateral(&maker_vault, maker1, &types::tradable_asset_btc());
    assert_eq(maker_collateral, deposit_amount - withdraw_amount);

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
    let (mut vault_unused, mut maker_vault, mut order_manager) = setup_complete_system(&mut scenario, none());

    let stake_amount = 200_000_000;
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
#[expected_failure(abort_code = maker_vault::EInsufficientCollateral)]
public fun test_cannot_withdraw_more_than_available() {
    let mut scenario = setup_test_scenario();
    let (_, _, _, maker1, _, _, _) = get_test_addresses();
    let (mut vault_unused, mut maker_vault, mut order_manager) = setup_complete_system(&mut scenario, none());

    let stake_amount = 200_000_000;
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

// ==========
// Locked Balance Behavior (via create_note)
// ==========
#[test]
#[expected_failure(abort_code = maker_vault::EInsufficientCollateral)]
public fun test_cannot_withdraw_locked_balance() {
    let mut scenario = setup_test_scenario();
    let (_, trader1, _, maker1, _, _, coordinator) = get_test_addresses();
    let (mut vault, mut maker_vault, mut order_manager, clock, maker_deposit_amount) = setup_funded_scenario(&mut scenario, none());

    // Create a note to lock maker balance
    test_scenario::next_tx(&mut scenario, trader1);
    let amount = 1_000;
    // Ensure trader has funds in taker vault
    {
        // deposit into taker vault for trader1
        let usdc = mint_usdc(&mut scenario, trader1, amount);
        odyssey_sui::vault::deposit(&mut vault, usdc, ctx(&mut scenario));
    };

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

// ==========
// Views
// ==========
#[test]
public fun test_get_withdrawable_balance_with_locked_view() {
    let mut scenario = setup_test_scenario();
    let (governor, _, _, maker1, _, _, _) = get_test_addresses();
    let (mut maker_vault, maker_order_cap) = setup_maker_vault(&mut scenario, none());

    let stake_amount = 200_000_000;
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

    // Move capability to avoid drop
    transfer::public_transfer(maker_order_cap, governor);

    test_scenario::return_shared(maker_vault);
    cleanup_scenario(scenario)
}
