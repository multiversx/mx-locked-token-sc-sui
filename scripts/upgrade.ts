import path from "path";
import fs from "fs";
import { execSync } from "child_process";
import { ADMIN, DEPLOYMENT, SUI_CLIENT, ENV } from "@/env";
import { Transaction, UpgradePolicy } from "@mysten/sui/transactions";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";
import {
  getCreatedObjectsIDs,
  readJSONFile,
  validateTransactionSuccess,
} from "@/mx-bridge-typescript/src/utils";

async function prepareUpgrade() {
  const deployerAddress = ADMIN.getPublicKey().toSuiAddress();
  console.log(`Deployer: ${deployerAddress}`);

  if (!DEPLOYMENT.Objects?.UpgradeCap) {
    console.error("Error: No active deployment found or UpgradeCap missing");
    console.log(
      "Make sure you have deployed the package first and have an active deployment."
    );
    console.log("\nTo deploy: npx tsx scripts/deploy.ts");
    console.log(
      "To set active deployment: DEPLOYMENT_ID=<id> npx tsx scripts/mark-active.ts"
    );
    process.exit(1);
  }

  const pkgPath = path.join(path.resolve(__dirname), "../");

  const { modules, dependencies, digest } = JSON.parse(
    execSync(
      `sui move build --with-unpublished-dependencies --dump-bytecode-as-base64 --path ${pkgPath}`,
      {
        encoding: "utf-8",
      }
    )
  );

  const tx = new Transaction();
  const cap = tx.object(DEPLOYMENT.Objects.UpgradeCap);

  const ticket = tx.moveCall({
    target: "0x2::package::authorize_upgrade",
    arguments: [
      cap,
      tx.pure.u8(UpgradePolicy.COMPATIBLE),
      tx.pure.vector("u8", digest),
    ],
  });

  const receipt = tx.upgrade({
    modules,
    dependencies,
    package: DEPLOYMENT.Package,
    ticket,
  });

  tx.moveCall({
    target: "0x2::package::commit_upgrade",
    arguments: [cap, receipt],
  });

  tx.setSender(deployerAddress);

  const result = await SUI_CLIENT.signAndExecuteTransaction({
    signer: ADMIN as unknown as Ed25519Keypair,
    transaction: tx,
    options: {
      showEffects: true,
      showObjectChanges: true,
    },
  });

  validateTransactionSuccess(result);

  console.log("Digest:", result.digest);

  if (result.effects.status.status !== "success") {
    console.error("Upgrade transaction failed");
    process.exit(1);
  }

  const objects = getCreatedObjectsIDs(result);

  const filePath = path.join(path.resolve(__dirname), "../deployment.json");
  const allDeployments = readJSONFile(filePath);

  if (!allDeployments[ENV.DEPLOY_ON]?.deployments) {
    console.error("No deployments found to update");
    process.exit(1);
  }

  const targetDeployment = allDeployments[ENV.DEPLOY_ON].deployments.find(
    (d: any) => d.id === DEPLOYMENT.id
  );

  if (!targetDeployment) {
    console.error(`Deployment #${DEPLOYMENT.id} not found in deployment.json`);
    process.exit(1);
  }

  const newPackageId = objects.Package;
  if (newPackageId) {
    const oldPackageId = targetDeployment.Package;
    targetDeployment.Package = newPackageId;
    targetDeployment.lastUpgrade = {
      previousPackage: oldPackageId,
      upgradedAt: new Date().toISOString(),
      digest: result.digest,
    };

    fs.writeFileSync(
      filePath,
      JSON.stringify(allDeployments, null, 2),
      "utf-8"
    );

    console.log(
      "\n╔═══════════════════════════════════════════════════════════╗"
    );
    console.log(
      "║              UPGRADE SUCCESSFUL                           ║"
    );
    console.log(
      "╠═══════════════════════════════════════════════════════════╣"
    );
    console.log(`║  Deployment ID:  ${String(DEPLOYMENT.id).padEnd(39)} ║`);
    console.log(
      `║  Old Package:    ${oldPackageId.substring(0, 38).padEnd(39)} ║`
    );
    console.log(
      `║  New Package:    ${newPackageId.substring(0, 38).padEnd(39)} ║`
    );
    console.log(
      "╚═══════════════════════════════════════════════════════════╝\n"
    );
  } else {
    console.warn("No new package ID found in upgrade result");
  }

  return result;
}
if (require.main === module) {
  prepareUpgrade();
}
