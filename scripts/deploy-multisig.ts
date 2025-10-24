import { SuiClient, getFullnodeUrl } from '@mysten/sui/client';
import { Transaction } from '@mysten/sui/transactions';
import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';
import { MultiSigPublicKey } from '@mysten/sui/multisig';
import { execSync } from 'child_process';
import * as fs from 'fs';

const client = new SuiClient({ url: getFullnodeUrl('testnet') });

if (!process.env.PRIVATE_KEY || !process.env.PRIVATE_KEY2) {
  throw new Error('Both PRIVATE_KEY and PRIVATE_KEY2 must be set');
}

const privateKey = process.env.PRIVATE_KEY
const privateKey2 = process.env.PRIVATE_KEY2

const signer1 = Ed25519Keypair.fromSecretKey(privateKey);
const signer2 = Ed25519Keypair.fromSecretKey(privateKey2);

const multiSigPublicKey = MultiSigPublicKey.fromPublicKeys({
  threshold: 2,
  publicKeys: [
    { publicKey: signer1.getPublicKey(), weight: 1 },
    { publicKey: signer2.getPublicKey(), weight: 1 },
  ],
});

const multisigAddress = multiSigPublicKey.toSuiAddress();
console.log('Multisig address:', multisigAddress);

async function checkMultisigBalanceAndGetGasCoin(): Promise<void> {
  try {
    const balance = await client.getBalance({ owner: multisigAddress });
    console.log(`Multisig balance: ${balance.totalBalance} MIST (${Number(balance.totalBalance) / 1e9} SUI)`);

    if (Number(balance.totalBalance) < 100_000_000) {
      console.error('\n⚠️  ERROR: Insufficient balance!');
      console.error(`The multisig address needs at least 0.1 SUI for gas.`);
      console.error(`Please fund the multisig address: ${multisigAddress}\n`);
      process.exit(1);
    }
  } catch (error) {
    console.error('Error checking balance:', error);
    process.exit(1);
  }
}

async function deployContract() {
    console.log('\nBuilding and publishing Move package...');

    // Build the package and get the compiled modules as JSON
    const buildOutput = execSync('sui move build --dump-bytecode-as-base64', { encoding: 'utf-8' });

    // Parse the JSON output (it's at the end of the output)
    const jsonMatch = buildOutput.match(/\{.*"modules".*"dependencies".*\}/s);
    if (!jsonMatch) {
      throw new Error('Failed to parse build output');
    }

    const buildJson = JSON.parse(jsonMatch[0]);
    const compiledModules = buildJson.modules;
    const dependencies = buildJson.dependencies;

    console.log(`Found ${compiledModules.length} compiled modules`);
    console.log(`Dependencies: ${dependencies.join(', ')}`);

    // Create transaction
    const tx = new Transaction();
    tx.setSender(multisigAddress);
    tx.setGasBudget(100000000);
    // Gas coin will be automatically selected by the SDK

    // Publish the package
    const [upgradeCap] = tx.publish({
      modules: compiledModules,
      dependencies: dependencies,
    });

    // Transfer the upgrade capability to the sender
    tx.transferObjects([upgradeCap], multisigAddress);

    console.log('\nSigning transaction with multisig...');

    // Serialize the transaction to ensure both signers sign the exact same thing
    const txJson = await tx.toJSON();
    const tx1 = Transaction.from(txJson);
    const tx2 = Transaction.from(txJson);

    // Sign with both signers
    const { bytes: txBytesBase64, signature: signature1 } = await tx1.sign({
      client,
      signer: signer1
    });

    const { signature: signature2 } = await tx2.sign({
      client,
      signer: signer2
    });

    // Combine signatures into multisig signature
    const multisigSignature = multiSigPublicKey.combinePartialSignatures([
      signature1,
      signature2,
    ]);

    console.log('Executing transaction...');

    // Execute the transaction
    const result = await client.executeTransactionBlock({
      transactionBlock: txBytesBase64,
      signature: multisigSignature,
      options: {
        showEffects: true,
        showObjectChanges: true,
      },
    });

    console.log('\n✅ Transaction successful!');
    console.log('Transaction digest:', result.digest);

    const publishedPackage = result.objectChanges?.find(
      obj => obj.type === 'published'
    );

    if (publishedPackage && publishedPackage.type === 'published') {
      console.log('Package ID:', publishedPackage.packageId);

      // Save deployment info
      const deploymentInfo = {
        network: 'testnet',
        packageId: publishedPackage.packageId,
        digest: result.digest,
        multisigAddress,
        timestamp: new Date().toISOString(),
      };

      const deploymentsDir = './deployments';
      if (!fs.existsSync(deploymentsDir)) {
        fs.mkdirSync(deploymentsDir);
      }

      const filename = `${deploymentsDir}/multisig-deployment-${Date.now()}.json`;
      fs.writeFileSync(filename, JSON.stringify(deploymentInfo, null, 2));
      console.log(`\nDeployment info saved to: ${filename}`);
    }
}    


async function main() {
  await checkMultisigBalanceAndGetGasCoin();
  await deployContract();
}

main().catch(console.error);



  