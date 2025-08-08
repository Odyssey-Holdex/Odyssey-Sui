// #[test_only]
// module odyssey_sui::maker_vault_tests;

// use sui::test_scenario::{Self, ctx};
// use sui::coin::{Self};
// use odyssey_sui::maker_vault::{Self, MakerVault, MakerVaultAdminCap, MakerOrderCap};
// use odyssey_sui::types::{Self};
// use odyssey_sui::test_utils::{Self, USDC, ITHACA, setup_test_scenario, mint_usdc, mint_ithaca, get_test_addresses, cleanup_scenario};

// const MINIMUM_STAKE: u64 = 200_000_000; // 200 ITHACA tokens

// #[test]
// fun test_initialize_maker_vault() {
//     let mut scenario = setup_test_scenario();
//     let (governor, _, _, _, _, _, _) = get_test_addresses();
    
//     test_scenario::next_tx(&mut scenario, governor);
//     let (maker_vault_admin_cap, maker_order_cap, maker_vault) = maker_vault::initialize<USDC, ITHACA>(MINIMUM_STAKE, ctx(&mut scenario));
    
//     // Test that maker vault was initialized correctly
//     assert!(maker_vault::total_asset_available(&maker_vault) == 0);
//     assert!(maker_vault::minimum_stake_amount(&maker_vault) == MINIMUM_STAKE);
    
//     // Cleanup
//     test_scenario::next_tx(&mut scenario, governor);
//     transfer::public_transfer(maker_vault_admin_cap, governor);
//     transfer::public_transfer(maker_order_cap, governor);
//     transfer::public_share_object(maker_vault);
    
//     cleanup_scenario(scenario);
// }

// #[test]
// #[expected_failure(abort_code = maker_vault::ENotZeroAmount)]
// fun test_initialize_with_zero_minimum_stake_fails() {
//     let mut scenario = setup_test_scenario();
//     let (governor, _, _, _, _, _, _) = get_test_addresses();
    
//     test_scenario::next_tx(&mut scenario, governor);
//     let (maker_vault_admin_cap, maker_order_cap, maker_vault) = maker_vault::initialize<USDC, ITHACA>(0, ctx(&mut scenario)); // Should fail
    
//     // Cleanup (should not reach here)
//     test_scenario::next_tx(&mut scenario, governor);
//     transfer::public_transfer(maker_vault_admin_cap, governor);
//     transfer::public_transfer(maker_order_cap, governor);
//     transfer::public_share_object(maker_vault);
    
//     cleanup_scenario(scenario);
// }

// #[test]
// fun test_register_maker_success() {
//     let mut scenario = setup_test_scenario();
//     let (governor, _, _, maker_1, _, _, _) = get_test_addresses();
    
//     // Setup maker vault
//     test_scenario::next_tx(&mut scenario, governor);
//     let (maker_vault_admin_cap, maker_order_cap, mut maker_vault) = maker_vault::initialize<USDC, ITHACA>(MINIMUM_STAKE, ctx(&mut scenario));
    
//     // Register maker
//     let stake_amount = MINIMUM_STAKE;
//     let ithaca_coin = mint_ithaca(&mut scenario, maker_1, stake_amount);
    
//     test_scenario::next_tx(&mut scenario, maker_1);
//     maker_vault::register_maker(&mut maker_vault, ithaca_coin, ctx(&mut scenario));
    
//     // Verify registration
//     assert!(maker_vault::get_maker_info(&maker_vault, maker_1) == stake_amount);
//     assert!(maker_vault::vault_ithaca_balance_value(&maker_vault) == stake_amount);
    
//     // Cleanup
//     test_scenario::next_tx(&mut scenario, governor);
//     transfer::public_transfer(maker_vault_admin_cap, governor);
//     transfer::public_transfer(maker_order_cap, governor);
//     transfer::public_share_object(maker_vault);
    
//     cleanup_scenario(scenario);
// }

// #[test]
// #[expected_failure(abort_code = maker_vault::ENotZeroAmount)]
// fun test_register_maker_zero_stake_fails() {
//     let mut scenario = setup_test_scenario();
//     let (governor, _, _, maker_1, _, _, _) = get_test_addresses();
    
//     // Setup maker vault
//     test_scenario::next_tx(&mut scenario, governor);
//     let (maker_vault_admin_cap, maker_order_cap, mut maker_vault) = maker_vault::initialize<USDC, ITHACA>(MINIMUM_STAKE, ctx(&mut scenario));
    
//     // Try to register with zero stake
//     let zero_coin = coin::zero<ITHACA>(ctx(&mut scenario));
    
//     test_scenario::next_tx(&mut scenario, maker_1);
//     maker_vault::register_maker(&mut maker_vault, zero_coin, ctx(&mut scenario)); // Should fail
    
//     // Cleanup
//     test_scenario::next_tx(&mut scenario, governor);
//     transfer::public_transfer(maker_vault_admin_cap, governor);
//     transfer::public_transfer(maker_order_cap, governor);
//     transfer::public_share_object(maker_vault);
    
//     cleanup_scenario(scenario);
// }

// #[test]
// #[expected_failure(abort_code = maker_vault::EInsufficientStake)]
// fun test_register_maker_insufficient_stake_fails() {
//     let mut scenario = setup_test_scenario();
//     let (governor, _, _, maker_1, _, _, _) = get_test_addresses();
    
//     // Setup maker vault
//     test_scenario::next_tx(&mut scenario, governor);
//     let (maker_vault_admin_cap, maker_order_cap, mut maker_vault) = maker_vault::initialize<USDC, ITHACA>(MINIMUM_STAKE, ctx(&mut scenario));
    
//     // Try to register with insufficient stake
//     let insufficient_stake = MINIMUM_STAKE - 1;
//     let ithaca_coin = mint_ithaca(&mut scenario, maker_1, insufficient_stake);
    
//     test_scenario::next_tx(&mut scenario, maker_1);
//     maker_vault::register_maker(&mut maker_vault, ithaca_coin, ctx(&mut scenario)); // Should fail
    
//     // Cleanup
//     test_scenario::next_tx(&mut scenario, governor);
//     transfer::public_transfer(maker_vault_admin_cap, governor);
//     transfer::public_transfer(maker_order_cap, governor);
//     transfer::public_share_object(maker_vault);
    
//     cleanup_scenario(scenario);
// }

// #[test]
// #[expected_failure(abort_code = maker_vault::EMakerAlreadyRegistered)]
// fun test_register_maker_twice_fails() {
//     let mut scenario = setup_test_scenario();
//     let (governor, _, _, maker_1, _, _, _) = get_test_addresses();
    
//     // Setup maker vault
//     test_scenario::next_tx(&mut scenario, governor);
//     let (maker_vault_admin_cap, maker_order_cap, mut maker_vault) = maker_vault::initialize<USDC, ITHACA>(MINIMUM_STAKE, ctx(&mut scenario));
    
//     // Register maker first time
//     let stake_amount = MINIMUM_STAKE;
//     let ithaca_coin_1 = mint_ithaca(&mut scenario, maker_1, stake_amount);
    
//     test_scenario::next_tx(&mut scenario, maker_1);
//     maker_vault::register_maker(&mut maker_vault, ithaca_coin_1, ctx(&mut scenario));
    
//     // Try to register again
//     let ithaca_coin_2 = mint_ithaca(&mut scenario, maker_1, stake_amount);
//     test_scenario::next_tx(&mut scenario, maker_1);
//     maker_vault::register_maker(&mut maker_vault, ithaca_coin_2, ctx(&mut scenario)); // Should fail
    
//     // Cleanup
//     test_scenario::next_tx(&mut scenario, governor);
//     transfer::public_transfer(maker_vault_admin_cap, governor);
//     transfer::public_transfer(maker_order_cap, governor);
//     transfer::public_share_object(maker_vault);
    
//     cleanup_scenario(scenario);
// }

// #[test]
// fun test_deposit_collateral_success() {
//     let mut scenario = setup_test_scenario();
//     let (governor, _, _, maker_1, _, _, _) = get_test_addresses();
    
//     // Setup and register maker
//     test_scenario::next_tx(&mut scenario, governor);
//     let (maker_vault_admin_cap, maker_order_cap, mut maker_vault) = maker_vault::initialize<USDC, ITHACA>(MINIMUM_STAKE, ctx(&mut scenario));
    
//     let stake_amount = MINIMUM_STAKE;
//     let ithaca_coin = mint_ithaca(&mut scenario, maker_1, stake_amount);
    
//     test_scenario::next_tx(&mut scenario, maker_1);
//     maker_vault::register_maker(&mut maker_vault, ithaca_coin, ctx(&mut scenario));
    
//     // Deposit collateral
//     let collateral_amount = 5_000_000; // 5 USDC
//     let usdc_coin = mint_usdc(&mut scenario, maker_1, collateral_amount);
//     let asset = types::tradable_asset_btc();
    
//     test_scenario::next_tx(&mut scenario, maker_1);
//     maker_vault::deposit_collateral(&mut maker_vault, asset, usdc_coin, ctx(&mut scenario));
    
//     // Verify collateral deposit
//     assert!(maker_vault::get_maker_collateral(&maker_vault, maker_1, &asset) == collateral_amount);
//     assert!(maker_vault::vault_collateral_balance_value(&maker_vault) == collateral_amount);
    
//     // Cleanup
//     test_scenario::next_tx(&mut scenario, governor);
//     transfer::public_transfer(maker_vault_admin_cap, governor);
//     transfer::public_transfer(maker_order_cap, governor);
//     transfer::public_share_object(maker_vault);
    
//     cleanup_scenario(scenario);
// }

// #[test]
// #[expected_failure(abort_code = maker_vault::ENotZeroAmount)]
// fun test_deposit_zero_collateral_fails() {
//     let mut scenario = setup_test_scenario();
//     let (governor, _, _, maker_1, _, _, _) = get_test_addresses();
    
//     // Setup and register maker
//     test_scenario::next_tx(&mut scenario, governor);
//     let (maker_vault_admin_cap, maker_order_cap, mut maker_vault) = maker_vault::initialize<USDC, ITHACA>(MINIMUM_STAKE, ctx(&mut scenario));
    
//     let stake_amount = MINIMUM_STAKE;
//     let ithaca_coin = mint_ithaca(&mut scenario, maker_1, stake_amount);
    
//     test_scenario::next_tx(&mut scenario, maker_1);
//     maker_vault::register_maker(&mut maker_vault, ithaca_coin, ctx(&mut scenario));
    
//     // Try to deposit zero collateral
//     let zero_coin = coin::zero<USDC>(ctx(&mut scenario));
//     let asset = types::tradable_asset_btc();
    
//     test_scenario::next_tx(&mut scenario, maker_1);
//     maker_vault::deposit_collateral(&mut maker_vault, asset, zero_coin, ctx(&mut scenario)); // Should fail
    
//     // Cleanup
//     test_scenario::next_tx(&mut scenario, governor);
//     transfer::public_transfer(maker_vault_admin_cap, governor);
//     transfer::public_transfer(maker_order_cap, governor);
//     transfer::public_share_object(maker_vault);
    
//     cleanup_scenario(scenario);
// }

// #[test]
// #[expected_failure(abort_code = maker_vault::EMakerNotAvailable)]
// fun test_deposit_collateral_unregistered_maker_fails() {
//     let mut scenario = setup_test_scenario();
//     let (governor, _, _, maker_1, _, _, _) = get_test_addresses();
    
//     // Setup maker vault without registering maker
//     test_scenario::next_tx(&mut scenario, governor);
//     let (maker_vault_admin_cap, maker_order_cap, mut maker_vault) = maker_vault::initialize<USDC, ITHACA>(MINIMUM_STAKE, ctx(&mut scenario));
    
//     // Try to deposit collateral without being registered
//     let collateral_amount = 5_000_000;
//     let usdc_coin = mint_usdc(&mut scenario, maker_1, collateral_amount);
//     let asset = types::tradable_asset_btc();
    
//     test_scenario::next_tx(&mut scenario, maker_1);
//     maker_vault::deposit_collateral(&mut maker_vault, asset, usdc_coin, ctx(&mut scenario)); // Should fail
    
//     // Cleanup
//     test_scenario::next_tx(&mut scenario, governor);
//     transfer::public_transfer(maker_vault_admin_cap, governor);
//     transfer::public_transfer(maker_order_cap, governor);
//     transfer::public_share_object(maker_vault);
    
//     cleanup_scenario(scenario);
// }

// #[test]
// fun test_withdraw_collateral_success() {
//     let mut scenario = setup_test_scenario();
//     let (governor, _, _, maker_1, _, _, _) = get_test_addresses();
    
//     // Setup, register maker, and deposit collateral
//     test_scenario::next_tx(&mut scenario, governor);
//     let (maker_vault_admin_cap, maker_order_cap, mut maker_vault) = maker_vault::initialize<USDC, ITHACA>(MINIMUM_STAKE, ctx(&mut scenario));
    
//     let stake_amount = MINIMUM_STAKE;
//     let ithaca_coin = mint_ithaca(&mut scenario, maker_1, stake_amount);
    
//     test_scenario::next_tx(&mut scenario, maker_1);
//     maker_vault::register_maker(&mut maker_vault, ithaca_coin, ctx(&mut scenario));
    
//     let collateral_amount = 5_000_000; // 5 USDC
//     let usdc_coin = mint_usdc(&mut scenario, maker_1, collateral_amount);
//     let asset = types::tradable_asset_btc();
    
//     test_scenario::next_tx(&mut scenario, maker_1);
//     maker_vault::deposit_collateral(&mut maker_vault, asset, usdc_coin, ctx(&mut scenario));
    
//     // Withdraw portion of collateral
//     let withdraw_amount = 2_000_000; // 2 USDC
//     let locked_amount = 0; // No locked funds
    
//     test_scenario::next_tx(&mut scenario, maker_1);
//     let withdrawn_coin = maker_vault::withdraw_collateral(&maker_order_cap, &mut maker_vault, maker_1, asset, locked_amount, withdraw_amount, ctx(&mut scenario));
    
//     // Verify withdrawal
//     assert!(coin::value(&withdrawn_coin) == withdraw_amount);
//     assert!(maker_vault::get_maker_collateral(&maker_vault, maker_1, &asset) == collateral_amount - withdraw_amount);
//     assert!(maker_vault::vault_collateral_balance_value(&maker_vault) == collateral_amount - withdraw_amount);
    
//     // Cleanup
//     coin::burn_for_testing(withdrawn_coin);
//     test_scenario::next_tx(&mut scenario, governor);
//     transfer::public_transfer(maker_vault_admin_cap, governor);
//     transfer::public_transfer(maker_order_cap, governor);
//     transfer::public_share_object(maker_vault);
    
//     cleanup_scenario(scenario);
// }

// #[test]
// #[expected_failure(abort_code = maker_vault::EInsufficientCollateral)]
// fun test_withdraw_excessive_collateral_fails() {
//     let mut scenario = setup_test_scenario();
//     let (governor, _, _, maker_1, _, _, _) = get_test_addresses();
    
//     // Setup, register maker, and deposit collateral
//     test_scenario::next_tx(&mut scenario, governor);
//     let (maker_vault_admin_cap, maker_order_cap, mut maker_vault) = maker_vault::initialize<USDC, ITHACA>(MINIMUM_STAKE, ctx(&mut scenario));
    
//     let stake_amount = MINIMUM_STAKE;
//     let ithaca_coin = mint_ithaca(&mut scenario, maker_1, stake_amount);
    
//     test_scenario::next_tx(&mut scenario, maker_1);
//     maker_vault::register_maker(&mut maker_vault, ithaca_coin, ctx(&mut scenario));
    
//     let collateral_amount = 5_000_000; // 5 USDC
//     let usdc_coin = mint_usdc(&mut scenario, maker_1, collateral_amount);
//     let asset = types::tradable_asset_btc();
    
//     test_scenario::next_tx(&mut scenario, maker_1);
//     maker_vault::deposit_collateral(&mut maker_vault, asset, usdc_coin, ctx(&mut scenario));
    
//     // Try to withdraw more than available
//     let withdraw_amount = 10_000_000; // 10 USDC (more than deposited)
//     let locked_amount = 0;
    
//     test_scenario::next_tx(&mut scenario, maker_1);
//     let withdrawn_coin = maker_vault::withdraw_collateral(&maker_order_cap, &mut maker_vault, maker_1, asset, locked_amount, withdraw_amount, ctx(&mut scenario)); // Should fail
    
//     coin::burn_for_testing(withdrawn_coin);
//     test_scenario::next_tx(&mut scenario, governor);
//     transfer::public_transfer(maker_vault_admin_cap, governor);
//     transfer::public_transfer(maker_order_cap, governor);
//     transfer::public_share_object(maker_vault);
    
//     cleanup_scenario(scenario);
// }

// #[test]
// fun test_stake_additional_ithaca() {
//     let mut scenario = setup_test_scenario();
//     let (governor, _, _, maker_1, _, _, _) = get_test_addresses();
    
//     // Setup and register maker
//     test_scenario::next_tx(&mut scenario, governor);
//     let (maker_vault_admin_cap, maker_order_cap, mut maker_vault) = maker_vault::initialize<USDC, ITHACA>(MINIMUM_STAKE, ctx(&mut scenario));
    
//     let initial_stake = MINIMUM_STAKE;
//     let ithaca_coin = mint_ithaca(&mut scenario, maker_1, initial_stake);
    
//     test_scenario::next_tx(&mut scenario, maker_1);
//     maker_vault::register_maker(&mut maker_vault, ithaca_coin, ctx(&mut scenario));
    
//     // Stake additional ITHACA
//     let additional_stake = 100_000_000; // 100 ITHACA
//     let additional_ithaca = mint_ithaca(&mut scenario, maker_1, additional_stake);
    
//     test_scenario::next_tx(&mut scenario, maker_1);
//     maker_vault::stake_ithaca(&mut maker_vault, additional_ithaca, ctx(&mut scenario));
    
//     // Verify additional staking
//     assert!(maker_vault::get_maker_info(&maker_vault, maker_1) == initial_stake + additional_stake);
//     assert!(maker_vault::vault_ithaca_balance_value(&maker_vault) == initial_stake + additional_stake);
    
//     // Cleanup
//     test_scenario::next_tx(&mut scenario, governor);
//     transfer::public_transfer(maker_vault_admin_cap, governor);
//     transfer::public_transfer(maker_order_cap, governor);
//     transfer::public_share_object(maker_vault);
    
//     cleanup_scenario(scenario);
// }

// #[test]
// fun test_unregister_maker_success() {
//     let mut scenario = setup_test_scenario();
//     let (governor, _, _, maker_1, _, _, _) = get_test_addresses();
    
//     // Setup and register maker
//     test_scenario::next_tx(&mut scenario, governor);
//     let (maker_vault_admin_cap, maker_order_cap, mut maker_vault) = maker_vault::initialize<USDC, ITHACA>(MINIMUM_STAKE, ctx(&mut scenario));
    
//     let stake_amount = MINIMUM_STAKE;
//     let ithaca_coin = mint_ithaca(&mut scenario, maker_1, stake_amount);
    
//     test_scenario::next_tx(&mut scenario, maker_1);
//     maker_vault::register_maker(&mut maker_vault, ithaca_coin, ctx(&mut scenario));
    
//     // Unregister maker (with zero collateral)
//     test_scenario::next_tx(&mut scenario, maker_1);
//     let returned_ithaca = maker_vault::unregister_maker(&mut maker_vault, ctx(&mut scenario));
    
//     // Verify unregistration
//     assert!(coin::value(&returned_ithaca) == stake_amount);
//     assert!(maker_vault::get_maker_info(&maker_vault, maker_1) == 0);
//     assert!(maker_vault::vault_ithaca_balance_value(&maker_vault) == 0);
    
//     // Cleanup
//     coin::burn_for_testing(returned_ithaca);
//     test_scenario::next_tx(&mut scenario, governor);
//     transfer::public_transfer(maker_vault_admin_cap, governor);
//     transfer::public_transfer(maker_order_cap, governor);
//     transfer::public_share_object(maker_vault);
    
//     cleanup_scenario(scenario);
// }

// #[test]
// #[expected_failure(abort_code = maker_vault::ECollateralMustBeZero)]
// fun test_unregister_maker_with_collateral_fails() {
//     let mut scenario = setup_test_scenario();
//     let (governor, _, _, maker_1, _, _, _) = get_test_addresses();
    
//     // Setup, register maker, and deposit collateral
//     test_scenario::next_tx(&mut scenario, governor);
//     let (maker_vault_admin_cap, maker_order_cap, mut maker_vault) = maker_vault::initialize<USDC, ITHACA>(MINIMUM_STAKE, ctx(&mut scenario));
    
//     let stake_amount = MINIMUM_STAKE;
//     let ithaca_coin = mint_ithaca(&mut scenario, maker_1, stake_amount);
    
//     test_scenario::next_tx(&mut scenario, maker_1);
//     maker_vault::register_maker(&mut maker_vault, ithaca_coin, ctx(&mut scenario));
    
//     let collateral_amount = 5_000_000;
//     let usdc_coin = mint_usdc(&mut scenario, maker_1, collateral_amount);
//     let asset = types::tradable_asset_btc();
    
//     test_scenario::next_tx(&mut scenario, maker_1);
//     maker_vault::deposit_collateral(&mut maker_vault, asset, usdc_coin, ctx(&mut scenario));
    
//     // Try to unregister with non-zero collateral
//     test_scenario::next_tx(&mut scenario, maker_1);
//     let returned_ithaca = maker_vault::unregister_maker(&mut maker_vault, ctx(&mut scenario)); // Should fail
    
//     coin::burn_for_testing(returned_ithaca);
//     test_scenario::next_tx(&mut scenario, governor);
//     transfer::public_transfer(maker_vault_admin_cap, governor);
//     transfer::public_transfer(maker_order_cap, governor);
//     transfer::public_share_object(maker_vault);
    
//     cleanup_scenario(scenario);
// }

// #[test]
// fun test_set_minimum_stake_amount() {
//     let mut scenario = setup_test_scenario();
//     let (governor, _, _, _, _, _, _) = get_test_addresses();
    
//     // Setup maker vault
//     test_scenario::next_tx(&mut scenario, governor);
//     let (maker_vault_admin_cap, maker_order_cap, mut maker_vault) = maker_vault::initialize<USDC, ITHACA>(MINIMUM_STAKE, ctx(&mut scenario));
    
//     // Set new minimum stake amount
//     let new_minimum = 300_000_000; // 300 ITHACA
//     test_scenario::next_tx(&mut scenario, governor);
//     maker_vault::set_minimum_stake_amount(&maker_vault_admin_cap, &mut maker_vault, new_minimum);
    
//     // Verify new minimum
//     assert!(maker_vault::minimum_stake_amount(&maker_vault) == new_minimum);
    
//     // Cleanup
//     test_scenario::next_tx(&mut scenario, governor);
//     transfer::public_transfer(maker_vault_admin_cap, governor);
//     transfer::public_transfer(maker_order_cap, governor);
//     transfer::public_share_object(maker_vault);
    
//     cleanup_scenario(scenario);
// }

// #[test]
// fun test_multiple_assets_collateral() {
//     let mut scenario = setup_test_scenario();
//     let (governor, _, _, maker_1, _, _, _) = get_test_addresses();
    
//     // Setup and register maker
//     test_scenario::next_tx(&mut scenario, governor);
//     let (maker_vault_admin_cap, maker_order_cap, mut maker_vault) = maker_vault::initialize<USDC, ITHACA>(MINIMUM_STAKE, ctx(&mut scenario));
    
//     let stake_amount = MINIMUM_STAKE;
//     let ithaca_coin = mint_ithaca(&mut scenario, maker_1, stake_amount);
    
//     test_scenario::next_tx(&mut scenario, maker_1);
//     maker_vault::register_maker(&mut maker_vault, ithaca_coin, ctx(&mut scenario));
    
//     // Deposit collateral for multiple assets
//     let btc_amount = 5_000_000; // 5 USDC for BTC
//     let eth_amount = 3_000_000; // 3 USDC for ETH
    
//     let btc_coin = mint_usdc(&mut scenario, maker_1, btc_amount);
//     let eth_coin = mint_usdc(&mut scenario, maker_1, eth_amount);
    
//     test_scenario::next_tx(&mut scenario, maker_1);
//     maker_vault::deposit_collateral(&mut maker_vault, types::tradable_asset_btc(), btc_coin, ctx(&mut scenario));
    
//     test_scenario::next_tx(&mut scenario, maker_1);
//     maker_vault::deposit_collateral(&mut maker_vault, types::tradable_asset_eth(), eth_coin, ctx(&mut scenario));
    
//     // Verify separate collateral tracking
//     assert!(maker_vault::get_maker_collateral(&maker_vault, maker_1, &types::tradable_asset_btc()) == btc_amount);
//     assert!(maker_vault::get_maker_collateral(&maker_vault, maker_1, &types::tradable_asset_eth()) == eth_amount);
//     assert!(maker_vault::vault_collateral_balance_value(&maker_vault) == btc_amount + eth_amount);
    
//     // Cleanup
//     test_scenario::next_tx(&mut scenario, governor);
//     transfer::public_transfer(maker_vault_admin_cap, governor);
//     transfer::public_transfer(maker_order_cap, governor);
//     transfer::public_share_object(maker_vault);
    
//     cleanup_scenario(scenario);
// } 