import { ADMIN, SUI_CLIENT, DEPLOYMENT, ENV } from "@/env";
import { Transaction } from "@mysten/sui/transactions";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";
import {
  sleep,
  readJSONFile,
  writeJSONFile,
  validateTransactionSuccess,
} from "@/mx-bridge-typescript/src/utils";
import path from "path";

async function grantFromCoinCap() {
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

  const RECEIVER =
    "0xde91225b70964422bbaea44f2b77bf76e962eb7b1607039783bd2af31e96ce74";

  console.log("\n=== GRANTING FROM_COIN_CAP ===");
  console.log(`Package:  ${packageId}`);
  console.log(`Treasury: ${treasuryId}`);
  console.log(`Receiver: ${RECEIVER}\n`);

  const tx = new Transaction();

  tx.moveCall({
    target: `${packageId}::treasury::transfer_from_coin_cap`,
    typeArguments: [bridgeTokenType],
    arguments: [tx.object(treasuryId), tx.pure.address(RECEIVER)],
  });

  console.log("Executing transaction...");
  await sleep(2000);

  const result = await SUI_CLIENT.signAndExecuteTransaction({
    signer: ADMIN as unknown as Ed25519Keypair,
    transaction: tx,
    options: {
      showEffects: true,
      showObjectChanges: true,
    },
  });

  await sleep(2000);

  validateTransactionSuccess(result);

  console.log("Transaction digest:", result.digest);

  const createdCap = result.objectChanges?.find(
    (change: any) =>
      change.type === "created" &&
      change.objectType?.includes("::treasury::FromCoinCap<")
  );

  console.log("\nGrant completed!");
  if (createdCap && "objectId" in createdCap) {
    console.log(`FromCoinCap ID: ${createdCap.objectId}`);
    console.log(`Cap type: ${createdCap.objectType}`);

    const filePath = path.join(path.resolve(__dirname), "../deployment.json");
    const allDeployments = readJSONFile(filePath);
    const targetDeployment = allDeployments[ENV.DEPLOY_ON].deployments.find(
      (d: any) => d.id === DEPLOYMENT.id
    );

    if (targetDeployment) {
      if (!targetDeployment.Capabilities) {
        targetDeployment.Capabilities = {};
      }
      targetDeployment.Capabilities.FromCoinCap = createdCap.objectId;
      writeJSONFile(allDeployments, filePath);
    }
  } else {
    console.warn(
      "FromCoinCap can't be found in the transaction object changes"
    );
  }

  console.log(
    `\nView transaction: https://suiscan.xyz/${ENV.DEPLOY_ON}/tx/${result.digest}`
  );
}

grantFromCoinCap()
  .then(() => {
    console.log("\nFromCoinCap grant script completed successfully");
    process.exit(0);
  })
  .catch((error) => {
    console.error("\nError during FromCoinCap grant:", error);
    process.exit(1);
  });
