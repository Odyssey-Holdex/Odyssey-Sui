import { getFullnodeUrl, SuiClient } from '@mysten/sui/client';
import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';
import { Transaction } from '@mysten/sui/transactions';

// Static package ID for ithaca_token package. Replace with your deployed package ID.
const PACKAGE_ID = '0x56a3ebc8fa65d0abc5fcc4a617ae898e239909a5b341d90a1139dab707039983';

interface CliArgs {
  address?: string;
  amount?: string;
}

const parseArgs = (argv: string[]): CliArgs => {
  const args: CliArgs = {};
  const rest = argv.slice(2);

  for (let i = 0; i < rest.length; i++) {
    const token = rest[i];

    if (token === '--address' || token === '-a') {
      args.address = rest[i + 1];
      i++;
      continue;
    }
    if (token.startsWith('--address=')) {
      args.address = token.split('=')[1];
      continue;
    }

    if (token === '--amount' || token === '-n') {
      args.amount = rest[i + 1];
      i++;
      continue;
    }
    if (token.startsWith('--amount=')) {
      args.amount = token.split('=')[1];
      continue;
    }

    // Fallback to positional args: <address> <amount>
    if (!args.address) {
      args.address = token;
    } else if (!args.amount) {
      args.amount = token;
    }
  }

  return args;
};

const requireEnv = (key: string): string => {
  const value = process.env[key];
  if (!value) throw new Error(`${key} is not set`);
  return value;
};

async function main(): Promise<void> {
  const { address, amount } = parseArgs(process.argv);

  const missing: string[] = [];
  if (!address) missing.push('--address');
  if (!amount) missing.push('--amount');

  if (missing.length > 0) {
    const plural = missing.length > 1 ? 's' : '';
    console.error(`Missing required argument${plural}: ${missing.join(', ')}`);
    console.error('Usage: pnpm ts-node packages/ithaca_token/scripts/mint-token.ts --address <0x...> --amount <u64>');
    process.exit(1);
  }

  if (!PACKAGE_ID) {
    throw new Error('PACKAGE_ID is not configured. Please set the deployed package ID.');
  }

  const client = new SuiClient({ url: getFullnodeUrl('testnet') });
  const privateKey = requireEnv('PRIVATE_KEY');
  const signer = Ed25519Keypair.fromSecretKey(privateKey);

  const ithacaType = `${PACKAGE_ID}::ithaca::ITHACA`;
  const treasuryCapType = `0x2::coin::TreasuryCap<${ithacaType}>`;

  const owned = await client.getOwnedObjects({
    owner: signer.toSuiAddress(),
    filter: { StructType: treasuryCapType },
    options: { showContent: true },
  });

  const treasuryCapObjectId = owned.data[0]?.data?.objectId as string | undefined;
  if (!treasuryCapObjectId) {
    throw new Error(`TreasuryCap not found for type ${treasuryCapType}`);
  }

  const tx = new Transaction();
  tx.moveCall({
    target: `${PACKAGE_ID}::ithaca::mint`,
    arguments: [
      tx.object(treasuryCapObjectId),
      tx.pure.u64(amount as string),
      tx.pure.address(address as string),
    ],
  });

  const result = await client.signAndExecuteTransaction({
    signer,
    transaction: tx,
    options: { showEffects: true },
  });

  console.log('Mint executed:', result.effects?.status);
  console.log(`Minted ${(BigInt(amount as string) / BigInt(10**6)).toString()} ITHACA to ${address}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
