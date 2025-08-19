import { getFullnodeUrl, SuiClient } from '@mysten/sui/client';
import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';
import { Transaction } from "@mysten/sui/transactions";
import { execSync } from 'child_process';
import fs from 'fs'

const client = new SuiClient({ url: getFullnodeUrl('testnet') });
if (!process.env.PRIVATE_KEY) {
  throw new Error('PRIVATE_KEY is not set');
}
const signer = Ed25519Keypair.fromSecretKey(process.env.PRIVATE_KEY);

const PACKAGE_ID = ''
const PUBLISH_NEW_PACKAGE = false

const addresses = {
  usdc: {
    testnet: '0xa1ec7fc00a6f40db9693ad1415d0c193ad3906494428cf252621037bd7117e29::usdc::USDC',
    mainnet: '0xdba34672e30cb065b1f93e3ab55318768fd6fef66c15942c9f7cb846e2f900e7::usdc::USDC'
  },
  ithaca: {
    testnet: '0x098cf6cd93b90fd1c7e693575c5762e063ea921b92f646be7763e21e6387e76d::ithaca::ITHACA',
    mainnet: '0xa8871e2b78b9e2462fd2d44560cefcc5d2ecba97028a1ad06a4c63b55fc49e81::ithaca::ITHACA'
  }
} satisfies Record<string, { testnet: string, mainnet: string }>
const network = process.env.NETWORK === 'mainnet' ? 'mainnet' : 'testnet'

const USDC = addresses.usdc[network]
const ITHACA = addresses.ithaca[network]
const COORDINATOR = '0x816d80321564335bcada156554ee4dc6fa6993e961a18287dc7bf9219bdd05dd'
const TREASURY = '0x816d80321564335bcada156554ee4dc6fa6993e961a18287dc7bf9219bdd05dd'
const MINIMUM_STAKE_AMOUNT = '500000000000' // 500,000 ITHACA, with 6 decimals

async function main() {
  let packageId = PACKAGE_ID
  if (!PACKAGE_ID || PUBLISH_NEW_PACKAGE) {
    // 1. Publish package (via CLI, but capture JSON)
    const publishResult = JSON.parse(
      execSync('sui client publish --json').toString()
    );
  
    // 2. Extract packageId
    packageId = publishResult.effects.created.find(
      (o: any) => o.owner === 'Immutable'
    ).reference.objectId;
    const effects = publishResult.effects
    if (!effects.created) {
      throw new Error('No created objects in publish result')
    }

    // 3. Save publish result to deployments folder
    const timestamp = new Date().toISOString()
    const path = './deployments'
    if (!fs.existsSync(path)) {
      fs.mkdirSync(path)
    }
    fs.writeFileSync(`${path}/${timestamp}.json`, JSON.stringify(publishResult, null, 2), { flag: 'w' })
  
    console.log('Deployed packageId:', packageId);
  }

  // 3. Get necessary objects (capabilities)
  const vaultAdminCapRes = await client.getOwnedObjects({
    filter: { StructType: `${packageId}::vault::VaultAdminCap` },
    owner: signer.toSuiAddress(),
    options: { showContent: true }
  })
  const makerVaultAdminCapRes = await client.getOwnedObjects({
    filter: { StructType: `${packageId}::maker_vault::MakerVaultAdminCap` },
    owner: signer.toSuiAddress(),
    options: { showContent: true }
  })
  const orderAdminCapRes = await client.getOwnedObjects({
    filter: { StructType: `${packageId}::order::OrderAdminCap` },
    owner: signer.toSuiAddress(),
    options: { showContent: true }
  })
  const vaultAdminCap = vaultAdminCapRes.data[0]
  const makerVaultAdminCap = makerVaultAdminCapRes.data[0]
  const orderAdminCap = orderAdminCapRes.data[0]

  if (!vaultAdminCap.data || !makerVaultAdminCap.data || !orderAdminCap.data) {
    throw new Error('VaultAdminCap or MakerVaultAdminCap or OrderAdminCap not found')
  }

  // 4. Call all initialize functions
  console.log('Initializing...')

  const tx = new Transaction();
  const [vaultOrderCap] = tx.moveCall({
    arguments: [tx.object(vaultAdminCap.data.objectId)],
    target: `${packageId}::vault::initialize`,
    typeArguments: [USDC]
  });
  const [makerVaultOrderCap] = tx.moveCall({
    arguments: [tx.object(makerVaultAdminCap.data.objectId), tx.pure.u64(MINIMUM_STAKE_AMOUNT)],
    target: `${packageId}::maker_vault::initialize`,
    typeArguments: [USDC, ITHACA]
  })
  const [coordinatorCap] = tx.moveCall({
    arguments: [tx.object(orderAdminCap.data.objectId), tx.object(vaultOrderCap), tx.object(makerVaultOrderCap), tx.pure.address(TREASURY)],
    target: `${packageId}::order::initialize`,
    typeArguments: [USDC]
  })
  tx.transferObjects([coordinatorCap], COORDINATOR)

  await client.signAndExecuteTransaction({
    signer,
    transaction: tx,
    options: { showEffects: true },
  });
  console.log('Finished initialize')
}

main().catch(console.error);