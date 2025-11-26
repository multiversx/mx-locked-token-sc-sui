import { ADMIN, SUI_CLIENT, DEPLOYMENT, ENV } from "@/env";
import {
  sleep,
  readJSONFile,
  writeJSONFile,
} from "@/mx-bridge-typescript/src/utils";
import path from "path";

// --- PARAMS ---
const RECEIVER =
  "0xde91225b70964422bbaea44f2b77bf76e962eb7b1607039783bd2af31e96ce74";
// --------------

/**
 * Grant TO_COIN_CAP capability to a specified receiver address
 * Usage: DEPLOYMENT_ID=2 npx tsx scripts/to-coin.ts
 */
async function main() {
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

  console.log("\n=== GRANTING TO_COIN_CAP ===");
  console.log(`Package:  ${packageId}`);
  console.log(`Treasury: ${treasuryId}`);
  console.log(`Receiver: ${RECEIVER}\n`);

  const result = await SUI_CLIENT.grantToCoinCap(RECEIVER);

  await sleep(2000);

  console.log("Grant transaction successfully executed");
  console.log("Transaction digest:", result.digest);
  console.log(
    `View transaction: https://suiscan.xyz/${ENV.DEPLOY_ON}/tx/${result.digest}`
  );

  console.log("Fetching transaction object changes...");

  const createdCap = result.objectChanges?.find(
    (change: any) =>
      change.type === "created" &&
      change.objectType?.includes("::treasury::ToCoinCap<")
  );

  if (createdCap && "objectId" in createdCap) {
    console.log(`ToCoinCap ID: ${createdCap.objectId}`);
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
      targetDeployment.Capabilities.ToCoinCap = createdCap.objectId;
      writeJSONFile(allDeployments, filePath);
    }
  } else {
    console.warn("ToCoinCap can't be found in the transaction object changes");
  }

  console.log(`Objects saved to deployment.json`);
}

if (require.main === module) {
  main().catch((error) => {
    console.error("Error:", error);
    process.exit(1);
  });
}
