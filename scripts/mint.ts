import { ADMIN, SUI_CLIENT, DEPLOYMENT, ENV } from "@/env";
import path from "path";
import {
  sleep,
  readJSONFile,
  writeJSONFile,
} from "@/mx-bridge-typescript/src/utils";

// --- PARAMS ---
const AMOUNT = 200000000000000n;
const RECEIVER =
  "0xde91225b70964422bbaea44f2b77bf76e962eb7b1607039783bd2af31e96ce74";
// --------------

/**
 * Mint a specified amount of tokens to a receiver address
 * Usage: DEPLOYMENT_ID=2 npx tsx scripts/mint.ts
 */
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

  console.log("\n=== MINTING TOKENS ===");
  console.log(`Package:  ${packageId}`);
  console.log(`Treasury: ${treasuryId}`);
  console.log(`Amount:   ${AMOUNT.toString()}`);
  console.log(`Receiver: ${RECEIVER}\n`);

  const result = await SUI_CLIENT.mintCoinToReceiver(AMOUNT, RECEIVER);

  await sleep(2000);

  console.log("Mint transaction successfully executed");
  console.log("Transaction digest:", result.digest);
  console.log(
    `View transaction: https://suiscan.xyz/${ENV.DEPLOY_ON}/tx/${result.digest}`
  );

  console.log("Fetching transaction object changes...");

  const createdCoin = result.objectChanges?.find(
    (change: any) =>
      change.type === "created" &&
      change.objectType?.startsWith("0x2::coin::Coin<")
  );

  if (createdCoin && "objectId" in createdCoin) {
    const createdCoinAny = createdCoin as any;
    console.log(`Minted coin: ${createdCoinAny.objectId}`);
    console.log(`Coin type: ${createdCoinAny.objectType}`);
  } else {
    console.log(
      "Tokens merged with existing balance (no new coin object created)"
    );
  }

  try {
    const outputPath = path.join(path.resolve(__dirname), "../deployment.json");
    const allDeployments = readJSONFile(outputPath);
    const network = ENV.DEPLOY_ON;
    if (
      network &&
      allDeployments[network] &&
      Array.isArray(allDeployments[network].deployments)
    ) {
      const target = allDeployments[network].deployments.find(
        (d: any) => d.id === DEPLOYMENT.id
      );
      if (target) {
        const coinTypeString = (createdCoin as any)?.objectType || null;
        if (coinTypeString) {
          const match = coinTypeString.match(/0x2::coin::Coin<(.+)>$/);
          const tokenType = match ? match[1] : coinTypeString;
          target.TokenType = tokenType;
          writeJSONFile(allDeployments, outputPath);
        } else {
          console.warn("No created coin objectType available to save.");
        }
      }
    }
  } catch (e) {
    console.warn("Failed to persist token type to deployment.json", e);
  }

  console.log("Objects saved to deployment.json");
}

if (require.main === module) {
  mint().catch((error) => {
    console.error("Error:", error);
    process.exit(1);
  });
}
