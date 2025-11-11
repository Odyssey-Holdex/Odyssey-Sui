import { getFullnodeUrl, SuiClient } from '@mysten/sui/client'
import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519'
import { Transaction, coinWithBalance } from '@mysten/sui/transactions'
import fs from 'fs'

if (!process.env.PRIVATE_KEY) {
  throw new Error('PRIVATE_KEY is not set')
}
const privateKey = process.env.PRIVATE_KEY
const signer = Ed25519Keypair.fromSecretKey(privateKey)

const network = process.env.NETWORK === 'mainnet' ? 'mainnet' : 'testnet'

// Static package ID for ithaca_token package. Replace with your deployed package ID.
const PACKAGE_ID =
  '0xf13ff4f6a99bc863c021afbe86d07de8e410bcfa0ef5bb4d89415e21fdb9a94e'

const TO_ADDRESS =
  '0x2060ec337085e0e1a830a8f88a57933205125e2ea2fa820b6964be8bc338b469'

async function main(): Promise<void> {
  const client = new SuiClient({ url: getFullnodeUrl(network) })

  const makerVaultAdminCapRes = await client.getOwnedObjects({
    filter: { StructType: `${PACKAGE_ID}::maker_vault::MakerVaultAdminCap` },
    owner: signer.toSuiAddress(),
  })
  const orderAdminCapRes = await client.getOwnedObjects({
    filter: { StructType: `${PACKAGE_ID}::order::OrderAdminCap` },
    owner: signer.toSuiAddress(),
  })
  const vaultAdminCapRes = await client.getOwnedObjects({
    filter: { StructType: `${PACKAGE_ID}::vault::VaultAdminCap` },
    owner: signer.toSuiAddress(),
  })
  const makerVaultAdminCap = makerVaultAdminCapRes.data[0]
  const orderAdminCap = orderAdminCapRes.data[0]
  const vaultAdminCap = vaultAdminCapRes.data[0]

  if (!makerVaultAdminCap.data || !orderAdminCap.data || !vaultAdminCap.data)
    throw new Error('Admin cap not found')

  const tx = new Transaction()
  tx.transferObjects(
    [
      makerVaultAdminCap.data.objectId,
      orderAdminCap.data.objectId,
      vaultAdminCap.data.objectId,
    ],
    TO_ADDRESS
  )

  await client.signAndExecuteTransaction({
    signer,
    transaction: tx,
    options: { showEffects: true, showEvents: true },
  })
  console.log('Transferred admin caps to', TO_ADDRESS)
}

main().catch((err) => {
  console.error(err)
  process.exit(1)
})
