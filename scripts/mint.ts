import { ADMIN, SUI_CLIENT, DEPLOYMENT, ENV } from "@/env";
import { Transaction } from "@mysten/sui/transactions";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";
import {
  getCreatedObjectsIDs,
  sleep,
  validateTransactionSuccess,
  writeJSONFile,
} from "@/mx-bridge-typescript/src/utils";

async function mint() {
  if (!DEPLOYMENT.Package) {
    console.error(
      "No active deployment found. Please deploy first or mark an existing deployment as active."
    );
    process.exit(1);
  }

  const deployerAddress = ADMIN.getPublicKey().toSuiAddress();
  console.log(`Sender: ${deployerAddress}`);

  const treasuryId = DEPLOYMENT.Objects?.Treasury;
  if (!treasuryId) {
    console.error("Treasury object not found in deployment data");
    process.exit(1);
  }

  const packageId = DEPLOYMENT.Package;
  const bridgeTokenType = `${packageId}::bridge_token::BRIDGE_TOKEN`;

  const AMOUNT = 200000000000000n;
  const RECEIVER =
    "0xde91225b70964422bbaea44f2b77bf76e962eb7b1607039783bd2af31e96ce74";

  console.log("\n=== MINTING TOKENS ===");
  console.log(`Package:  ${packageId}`);
  console.log(`Treasury: ${treasuryId}`);
  console.log(`Amount:   ${AMOUNT.toString()}`);
  console.log(`Receiver: ${RECEIVER}\n`);

  const tx = new Transaction();

  tx.moveCall({
    target: `${packageId}::treasury::mint_coin_to_receiver`,
    typeArguments: [bridgeTokenType],
    arguments: [
      tx.object(treasuryId),
      tx.pure.u64(AMOUNT.toString()),
      tx.pure.address(RECEIVER),
    ],
  });

  console.log("Executing mint transaction...");
  await sleep(2000);

  const result = await SUI_CLIENT.signAndExecuteTransaction({
    signer: ADMIN as unknown as Ed25519Keypair,
    transaction: tx,
    options: {
      showEffects: true,
      showObjectChanges: true,
    },
  });

  validateTransactionSuccess(result);

  await sleep(2000);

  console.log("Transaction digest:", result.digest);

  const createdCoin = result.objectChanges?.find(
    (change: any) =>
      change.type === "created" &&
      change.objectType?.startsWith("0x2::coin::Coin<")
  );

  console.log("\nMint completed!");
  if (createdCoin && "objectId" in createdCoin) {
    console.log(`Minted coin: ${createdCoin.objectId}`);
    console.log(`Coin type: ${createdCoin.objectType}`);
  } else {
    console.log(
      "Tokens merged with existing balance (no new coin object created)"
    );
  }

  console.log(
    `\nView transaction: https://suiscan.xyz/${ENV.DEPLOY_ON}/tx/${result.digest}`
  );
}

mint()
  .then(() => {
    console.log("\nMint script completed successfully");
    process.exit(0);
  })
  .catch((error) => {
    console.error("\nError during mint:", error);
    process.exit(1);
  });
