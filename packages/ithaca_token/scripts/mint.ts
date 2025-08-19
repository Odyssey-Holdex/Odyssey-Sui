import { getFullnodeUrl, SuiClient } from '@mysten/sui/client';
import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';
import { Transaction } from '@mysten/sui/transactions';

// Static package ID for ithaca_token package. Replace with your deployed package ID.
const PACKAGE_ID = '0x07f4f6d476db10680282778a85be596ded56cbefed6d2a1a416337f9b51446e9';
const TREASURY_CAPABILITY_ID = '0x57751c4ba66bcbcb33bb290ba5bc67e31ef3d73b9d1c46073562fd4742494dac' // get from the deployments folder, check the latest deployment, objectChanges, and get the TreasuryCap object ID

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

  const tx = new Transaction();
  tx.moveCall({
    target: `${PACKAGE_ID}::ithaca::mint`,
    arguments: [
      tx.object(TREASURY_CAPABILITY_ID),
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
