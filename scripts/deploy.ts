import path from "path";
import fs from "fs";
import { execSync } from "child_process";
import { ADMIN, SUI_CLIENT, ENV } from "@/env";
import { Transaction } from "@mysten/sui/transactions";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";
import {
  sleep,
  getCreatedObjectsIDs,
  readJSONFile,
  validateTransactionSuccess,
} from "@/mx-bridge-typescript/src/utils";

/**
 * Update Move.lock file with the new published package ID
 * For fresh deployments, both original and latest IDs are set to the new package
 */
function updateMoveLock(
  pkgPath: string,
  network: string,
  packageId: string
): void {
  const moveLockPath = path.join(pkgPath, "Move.lock");

  if (!fs.existsSync(moveLockPath)) {
    console.warn("Move.lock not found, skipping update");
    return;
  }

  let content = fs.readFileSync(moveLockPath, "utf-8");
  const lines = content.split("\n");

  let inTargetEnv = false;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();

    if (line === `[env.${network}]`) {
      inTargetEnv = true;
      continue;
    }

    if (inTargetEnv) {
      if (line.startsWith("[")) {
        inTargetEnv = false;
        continue;
      }

      if (line.startsWith("original-published-id")) {
        lines[i] = `original-published-id = "${packageId}"`;
      }

      if (line.startsWith("latest-published-id")) {
        lines[i] = `latest-published-id = "${packageId}"`;
      }

      if (line.startsWith("published-version")) {
        lines[i] = `published-version = "1"`;
      }
    }
  }

  fs.writeFileSync(moveLockPath, lines.join("\n"), "utf-8");
  console.log(`Updated Move.lock: fresh deployment, package ${packageId}`);
}

export async function deploy() {
  const deployerAddress = ADMIN.getPublicKey().toSuiAddress();
  console.log(`Deployer: ${deployerAddress}`);

  const pkgPath = path.join(path.resolve(__dirname), "../");

  const { modules, dependencies } = JSON.parse(
    execSync(
      `sui move build --with-unpublished-dependencies --dump-bytecode-as-base64 --path ${pkgPath}`,
      {
        encoding: "utf-8",
      }
    )
  );

  const tx = new Transaction();
  const [upgradeCap] = tx.publish({ modules, dependencies });

  tx.transferObjects([upgradeCap], tx.pure.address(deployerAddress));

  console.log("Deploying");
  await sleep(3000);

  const result = await SUI_CLIENT.signAndExecuteTransaction({
    signer: ADMIN as unknown as Ed25519Keypair,
    transaction: tx,
    options: {
      showEffects: true,
      showObjectChanges: true,
    },
  });

  await sleep(3000);

  validateTransactionSuccess(result);

  console.log("Transaction digest:", result.digest);

  const objects = getCreatedObjectsIDs(result);

  const filePath = path.join(path.resolve(__dirname), "../deployment.json");
  const allDeployments = readJSONFile(filePath);

  const { Package, ...restObjects } = objects;

  const existingDeployments = allDeployments[ENV.DEPLOY_ON]?.deployments || [];
  const deploymentId =
    existingDeployments.length > 0
      ? Math.max(...existingDeployments.map((d: any) => d.id)) + 1
      : 1;
  const createdAt = new Date().toISOString();

  const deploymentData = {
    id: deploymentId,
    createdAt,
    active: false,
    Package: Package || undefined,
    Objects: restObjects,
    Operators: { Admin: deployerAddress },
    digest: result.digest,
  };

  if (!allDeployments[ENV.DEPLOY_ON]) {
    allDeployments[ENV.DEPLOY_ON] = { deployments: [] };
  }
  if (!allDeployments[ENV.DEPLOY_ON].deployments) {
    allDeployments[ENV.DEPLOY_ON].deployments = [];
  }

  allDeployments[ENV.DEPLOY_ON].deployments.push(deploymentData);

  fs.writeFileSync(filePath, JSON.stringify(allDeployments, null, 2), "utf-8");

  // Update Move.lock with the new package ID
  if (Package && ENV.DEPLOY_ON) {
    updateMoveLock(pkgPath, ENV.DEPLOY_ON, Package);
  }

  console.log(
    "\n╔═══════════════════════════════════════════════════════════╗"
  );
  console.log("║                  DEPLOYMENT SUCCESSFUL                    ║");
  console.log("╠═══════════════════════════════════════════════════════════╣");
  console.log(`║  Deployment ID:  ${String(deploymentId).padEnd(39)} ║`);
  console.log(`║  Network:        ${ENV.DEPLOY_ON?.padEnd(39)} ║`);
  console.log(
    `║  Created:        ${new Date(createdAt).toLocaleString().padEnd(39)} ║`
  );
  console.log(
    `║  Package:        ${(Package || "N/A").substring(0, 38).padEnd(39)} ║`
  );
  console.log(
    "╚═══════════════════════════════════════════════════════════╝\n"
  );
  console.log(`\nTo use this deployment in other scripts, set:`);
  console.log(`  export DEPLOYMENT_ID=${deploymentId}\n`);

  console.log("Deployment saved to:", filePath);

  return result;
}

if (require.main === module) {
  deploy();
}
