#[test_only]
module odyssey_sui::vault_tests;

use sui::test_scenario::{Self, Scenario, ctx};
use sui::coin::{Self, Coin};
use odyssey_sui::vault::{Self, Vault, VaultAdminCap, OrderCap};
use odyssey_sui::test_utils::{Self, USDC, setup_test_scenario, mint_usdc, get_test_addresses, cleanup_scenario};
use odyssey_sui::order;
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

// #[test]
// fun test_deposit_success() {
//     let mut scenario = setup_test_scenario();
//     let (governor, trader_1, _, _, _, _, _) = get_test_addresses();
    
//     // Setup vault
//     test_scenario::next_tx(&mut scenario, governor);
//     let (vault_admin_cap, order_cap, mut vault) = vault::initialize<USDC>(ctx(&mut scenario));
    
//     // Mint and deposit USDC
//     let deposit_amount = 1_000_000; // 1 USDC (6 decimals)
//     let usdc_coin = mint_usdc(&mut scenario, trader_1, deposit_amount);
    
//     test_scenario::next_tx(&mut scenario, trader_1);
//     vault::deposit(&mut vault, usdc_coin, ctx(&mut scenario));
    
//     // Verify deposit
//     assert!(vault::total_asset_available(&vault) == deposit_amount);
//     assert!(vault::taker_balance(&vault, trader_1) == deposit_amount);
    
//     // Cleanup
//     test_scenario::next_tx(&mut scenario, governor);
//     transfer::public_transfer(vault_admin_cap, governor);
//     transfer::public_transfer(order_cap, governor);
//     transfer::public_share_object(vault);
    
//     cleanup_scenario(scenario);
// }

// #[test]
// #[expected_failure(abort_code = vault::ENotZeroAmount)]
// fun test_deposit_zero_amount_fails() {
//     let mut scenario = setup_test_scenario();
//     let (governor, trader_1, _, _, _, _, _) = get_test_addresses();
    
//     // Setup vault
//     test_scenario::next_tx(&mut scenario, governor);
//     let (vault_admin_cap, order_cap, mut vault) = vault::initialize<USDC>(ctx(&mut scenario));
    
//     // Try to deposit zero amount
//     let zero_coin = coin::zero<USDC>(ctx(&mut scenario));
    
//     test_scenario::next_tx(&mut scenario, trader_1);
//     vault::deposit(&mut vault, zero_coin, ctx(&mut scenario)); // Should fail
    
//     // Cleanup
//     test_scenario::next_tx(&mut scenario, governor);
//     transfer::public_transfer(vault_admin_cap, governor);
//     transfer::public_transfer(order_cap, governor);
//     transfer::public_share_object(vault);
    
//     cleanup_scenario(scenario);
// }

// #[test]
// fun test_multiple_deposits() {
//     let mut scenario = setup_test_scenario();
//     let (governor, trader_1, trader_2, _, _, _, _) = get_test_addresses();
    
//     // Setup vault
//     test_scenario::next_tx(&mut scenario, governor);
//     let (vault_admin_cap, order_cap, mut vault) = vault::initialize<USDC>(ctx(&mut scenario));
    
//     // Multiple deposits from trader_1
//     let deposit_1 = 1_000_000; // 1 USDC
//     let deposit_2 = 500_000;   // 0.5 USDC
    
//     let usdc_coin_1 = mint_usdc(&mut scenario, trader_1, deposit_1);
//     test_scenario::next_tx(&mut scenario, trader_1);
//     vault::deposit(&mut vault, usdc_coin_1, ctx(&mut scenario));
    
//     let usdc_coin_2 = mint_usdc(&mut scenario, trader_1, deposit_2);
//     test_scenario::next_tx(&mut scenario, trader_1);
//     vault::deposit(&mut vault, usdc_coin_2, ctx(&mut scenario));
    
//     // Deposit from trader_2
//     let deposit_3 = 2_000_000; // 2 USDC
//     let usdc_coin_3 = mint_usdc(&mut scenario, trader_2, deposit_3);
//     test_scenario::next_tx(&mut scenario, trader_2);
//     vault::deposit(&mut vault, usdc_coin_3, ctx(&mut scenario));
    
//     // Verify balances
//     assert!(vault::taker_balance(&vault, trader_1) == deposit_1 + deposit_2);
//     assert!(vault::taker_balance(&vault, trader_2) == deposit_3);
//     assert!(vault::total_asset_available(&vault) == deposit_1 + deposit_2 + deposit_3);
    
//     // Cleanup
//     test_scenario::next_tx(&mut scenario, governor);
//     transfer::public_transfer(vault_admin_cap, governor);
//     transfer::public_transfer(order_cap, governor);
//     transfer::public_share_object(vault);
    
//     cleanup_scenario(scenario);
// }

// #[test]
// fun test_withdraw_success() {
//     let mut scenario = setup_test_scenario();
//     let (governor, trader_1, _, _, _, _, _) = get_test_addresses();
    
//     // Setup vault with deposit
//     test_scenario::next_tx(&mut scenario, governor);
//     let (vault_admin_cap, order_cap, mut vault) = vault::initialize<USDC>(ctx(&mut scenario));
    
//     let deposit_amount = 1_000_000; // 1 USDC
//     let usdc_coin = mint_usdc(&mut scenario, trader_1, deposit_amount);
    
//     test_scenario::next_tx(&mut scenario, trader_1);
//     vault::deposit(&mut vault, usdc_coin, ctx(&mut scenario));
    
//     // Withdraw portion
//     let withdraw_amount = 600_000; // 0.6 USDC
//     let locked_amount = 0; // No locked funds
    
//     test_scenario::next_tx(&mut scenario, trader_1);
//     let withdrawn_coin = vault::withdraw(&order_cap, &mut vault, trader_1, withdraw_amount, locked_amount, ctx(&mut scenario));
    
//     // Verify withdrawal
//     assert!(coin::value(&withdrawn_coin) == withdraw_amount);
//     assert!(vault::taker_balance(&vault, trader_1) == deposit_amount - withdraw_amount);
//     assert!(vault::total_asset_available(&vault) == deposit_amount - withdraw_amount);
    
//     // Cleanup
//     coin::burn_for_testing(withdrawn_coin);
//     test_scenario::next_tx(&mut scenario, governor);
//     transfer::public_transfer(vault_admin_cap, governor);
//     transfer::public_transfer(order_cap, governor);
//     transfer::public_share_object(vault);
    
//     cleanup_scenario(scenario);
// }

// #[test]
// #[expected_failure(abort_code = vault::ENotZeroAmount)]
// fun test_withdraw_zero_amount_fails() {
//     let mut scenario = setup_test_scenario();
//     let (governor, trader_1, _, _, _, _, _) = get_test_addresses();
    
//     // Setup vault with deposit
//     test_scenario::next_tx(&mut scenario, governor);
//     let (vault_admin_cap, order_cap, mut vault) = vault::initialize<USDC>(ctx(&mut scenario));
    
//     let deposit_amount = 1_000_000;
//     let usdc_coin = mint_usdc(&mut scenario, trader_1, deposit_amount);
    
//     test_scenario::next_tx(&mut scenario, trader_1);
//     vault::deposit(&mut vault, usdc_coin, ctx(&mut scenario));
    
//     // Try to withdraw zero amount
//     test_scenario::next_tx(&mut scenario, trader_1);
//     let withdrawn_coin = vault::withdraw(&order_cap, &mut vault, trader_1, 0, 0, ctx(&mut scenario)); // Should fail
    
//     coin::burn_for_testing(withdrawn_coin);
//     test_scenario::next_tx(&mut scenario, governor);
//     transfer::public_transfer(vault_admin_cap, governor);
//     transfer::public_transfer(order_cap, governor);
//     transfer::public_share_object(vault);
    
//     cleanup_scenario(scenario);
// }

// #[test]
// #[expected_failure(abort_code = vault::EInsufficientBalance)]
// fun test_withdraw_insufficient_balance_fails() {
//     let mut scenario = setup_test_scenario();
//     let (governor, trader_1, _, _, _, _, _) = get_test_addresses();
    
//     // Setup vault with small deposit
//     test_scenario::next_tx(&mut scenario, governor);
//     let (vault_admin_cap, order_cap, mut vault) = vault::initialize<USDC>(ctx(&mut scenario));
    
//     let deposit_amount = 500_000; // 0.5 USDC
//     let usdc_coin = mint_usdc(&mut scenario, trader_1, deposit_amount);
    
//     test_scenario::next_tx(&mut scenario, trader_1);
//     vault::deposit(&mut vault, usdc_coin, ctx(&mut scenario));
    
//     // Try to withdraw more than available
//     let withdraw_amount = 1_000_000; // 1 USDC (more than deposited)
//     test_scenario::next_tx(&mut scenario, trader_1);
//     let withdrawn_coin = vault::withdraw(&order_cap, &mut vault, trader_1, withdraw_amount, 0, ctx(&mut scenario)); // Should fail
    
//     coin::burn_for_testing(withdrawn_coin);
//     test_scenario::next_tx(&mut scenario, governor);
//     transfer::public_transfer(vault_admin_cap, governor);
//     transfer::public_transfer(order_cap, governor);
//     transfer::public_share_object(vault);
    
//     cleanup_scenario(scenario);
// }

// #[test]
// #[expected_failure(abort_code = vault::EInsufficientBalance)]
// fun test_withdraw_with_locked_funds_fails() {
//     let mut scenario = setup_test_scenario();
//     let (governor, trader_1, _, _, _, _, _) = get_test_addresses();
    
//     // Setup vault with deposit
//     test_scenario::next_tx(&mut scenario, governor);
//     let (vault_admin_cap, order_cap, mut vault) = vault::initialize<USDC>(ctx(&mut scenario));
    
//     let deposit_amount = 1_000_000; // 1 USDC
//     let usdc_coin = mint_usdc(&mut scenario, trader_1, deposit_amount);
    
//     test_scenario::next_tx(&mut scenario, trader_1);
//     vault::deposit(&mut vault, usdc_coin, ctx(&mut scenario));
    
//     // Try to withdraw with locked funds that exceed available
//     let withdraw_amount = 600_000; // 0.6 USDC
//     let locked_amount = 500_000;   // 0.5 USDC locked
//     // Available = 1.0 - 0.5 = 0.5 USDC, but trying to withdraw 0.6 USDC
    
//     test_scenario::next_tx(&mut scenario, trader_1);
//     let withdrawn_coin = vault::withdraw(&order_cap, &mut vault, trader_1, withdraw_amount, locked_amount, ctx(&mut scenario)); // Should fail
    
//     coin::burn_for_testing(withdrawn_coin);
//     test_scenario::next_tx(&mut scenario, governor);
//     transfer::public_transfer(vault_admin_cap, governor);
//     transfer::public_transfer(order_cap, governor);
//     transfer::public_share_object(vault);
    
//     cleanup_scenario(scenario);
// }

// #[test]
// fun test_withdraw_with_locked_funds_success() {
//     let mut scenario = setup_test_scenario();
//     let (governor, trader_1, _, _, _, _, _) = get_test_addresses();
    
//     // Setup vault with deposit
//     test_scenario::next_tx(&mut scenario, governor);
//     let (vault_admin_cap, order_cap, mut vault) = vault::initialize<USDC>(ctx(&mut scenario));
    
//     let deposit_amount = 1_000_000; // 1 USDC
//     let usdc_coin = mint_usdc(&mut scenario, trader_1, deposit_amount);
    
//     test_scenario::next_tx(&mut scenario, trader_1);
//     vault::deposit(&mut vault, usdc_coin, ctx(&mut scenario));
    
//     // Withdraw with locked funds (valid case)
//     let withdraw_amount = 400_000; // 0.4 USDC
//     let locked_amount = 500_000;   // 0.5 USDC locked
//     // Available = 1.0 - 0.5 = 0.5 USDC, withdrawing 0.4 USDC is ok
    
//     test_scenario::next_tx(&mut scenario, trader_1);
//     let withdrawn_coin = vault::withdraw(&order_cap, &mut vault, trader_1, withdraw_amount, locked_amount, ctx(&mut scenario));
    
//     // Verify withdrawal
//     assert!(coin::value(&withdrawn_coin) == withdraw_amount);
//     assert!(vault::taker_balance(&vault, trader_1) == deposit_amount - withdraw_amount);
    
//     // Cleanup
//     coin::burn_for_testing(withdrawn_coin);
//     test_scenario::next_tx(&mut scenario, governor);
//     transfer::public_transfer(vault_admin_cap, governor);
//     transfer::public_transfer(order_cap, governor);
//     transfer::public_share_object(vault);
    
//     cleanup_scenario(scenario);
// }

// #[test]
// fun test_get_withdrawable_balance_with_locked() {
//     let mut scenario = setup_test_scenario();
//     let (governor, trader_1, _, _, _, _, _) = get_test_addresses();
    
//     // Setup vault with deposit
//     test_scenario::next_tx(&mut scenario, governor);
//     let (vault_admin_cap, order_cap, mut vault) = vault::initialize<USDC>(ctx(&mut scenario));
    
//     let deposit_amount = 1_000_000; // 1 USDC
//     let usdc_coin = mint_usdc(&mut scenario, trader_1, deposit_amount);
    
//     test_scenario::next_tx(&mut scenario, trader_1);
//     vault::deposit(&mut vault, usdc_coin, ctx(&mut scenario));
    
//     // Test withdrawable balance calculation
//     let locked_amount = 300_000; // 0.3 USDC locked
//     let expected_withdrawable = deposit_amount - locked_amount; // 0.7 USDC
    
//     let actual_withdrawable = vault::get_withdrawable_balance_with_locked(&order_cap, &vault, trader_1, locked_amount);
//     assert!(actual_withdrawable == expected_withdrawable);
    
//     // Test with locked amount exceeding balance
//     let excessive_locked = 1_500_000; // 1.5 USDC locked (more than balance)
//     let withdrawable_with_excess = vault::get_withdrawable_balance_with_locked(&order_cap, &vault, trader_1, excessive_locked);
//     assert!(withdrawable_with_excess == 0);
    
//     // Cleanup
//     test_scenario::next_tx(&mut scenario, governor);
//     transfer::public_transfer(vault_admin_cap, governor);
//     transfer::public_transfer(order_cap, governor);
//     transfer::public_share_object(vault);
    
//     cleanup_scenario(scenario);
// }

// #[test]
// fun test_complete_withdrawal() {
//     let mut scenario = setup_test_scenario();
//     let (governor, trader_1, _, _, _, _, _) = get_test_addresses();
    
//     // Setup vault with deposit
//     test_scenario::next_tx(&mut scenario, governor);
//     let (vault_admin_cap, order_cap, mut vault) = vault::initialize<USDC>(ctx(&mut scenario));
    
//     let deposit_amount = 1_000_000; // 1 USDC
//     let usdc_coin = mint_usdc(&mut scenario, trader_1, deposit_amount);
    
//     test_scenario::next_tx(&mut scenario, trader_1);
//     vault::deposit(&mut vault, usdc_coin, ctx(&mut scenario));
    
//     // Withdraw all funds
//     test_scenario::next_tx(&mut scenario, trader_1);
//     let withdrawn_coin = vault::withdraw(&order_cap, &mut vault, trader_1, deposit_amount, 0, ctx(&mut scenario));
    
//     // Verify complete withdrawal
//     assert!(coin::value(&withdrawn_coin) == deposit_amount);
//     assert!(vault::taker_balance(&vault, trader_1) == 0);
//     assert!(vault::total_asset_available(&vault) == 0);
    
//     // Cleanup
//     coin::burn_for_testing(withdrawn_coin);
//     test_scenario::next_tx(&mut scenario, governor);
//     transfer::public_transfer(vault_admin_cap, governor);
//     transfer::public_transfer(order_cap, governor);
//     transfer::public_share_object(vault);
    
//     cleanup_scenario(scenario);
// } 