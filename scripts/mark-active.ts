import path from "path";
import fs from "fs";
import { readJSONFile } from "@/mx-bridge-typescript/src/utils";
import { ENV } from "@/env";

/**
 * Mark a specific deployment as active/official for the current network
 * Usage: DEPLOYMENT_ID=2 npx tsx scripts/mark-active.ts
 */
async function markActive() {
  const deploymentId = parseInt(process.env.DEPLOYMENT_ID || "0", 10);
  const network = ENV.DEPLOY_ON;

  if (!deploymentId) {
    console.error("Error: DEPLOYMENT_ID environment variable is required");
    console.log("\nUsage: DEPLOYMENT_ID=2 npx tsx scripts/mark-active.ts");
    process.exit(1);
  }

  if (!network) {
    console.error("Error: DEPLOY_ON environment variable is required");
    process.exit(1);
  }

  const filePath = path.join(path.resolve(__dirname), "../deployment.json");
  const allDeployments = readJSONFile(filePath);

  const networkData = allDeployments[network];
  if (!networkData || !networkData.deployments) {
    console.error(`No deployments found for network: ${network}`);
    process.exit(1);
  }

  const deployments = networkData.deployments;
  const deployment = deployments.find((d: any) => d.id === deploymentId);

  if (!deployment) {
    console.error(`Deployment #${deploymentId} not found on ${network}`);
    console.log("\nAvailable deployments:");
    deployments.forEach((d: any) => {
      const activeMarker = d.active ? " [ACTIVE]" : "";
      console.log(`  - #${d.id} (${d.createdAt})${activeMarker}`);
    });
    process.exit(1);
  }

  deployments.forEach((d: any) => {
    d.active = false;
  });

  deployment.active = true;

  fs.writeFileSync(filePath, JSON.stringify(allDeployments, null, 2), "utf-8");

  console.log(
    "\n╔═══════════════════════════════════════════════════════════╗"
  );
  console.log("║           ACTIVE DEPLOYMENT UPDATED                       ║");
  console.log("╠═══════════════════════════════════════════════════════════╣");
  console.log(`║  Deployment ID:  ${String(deploymentId).padEnd(39)} ║`);
  console.log(`║  Network:        ${network.padEnd(39)} ║`);
  console.log(
    `║  Created:        ${new Date(deployment.createdAt)
      .toLocaleString()
      .padEnd(39)} ║`
  );
  console.log(
    `║  Package:        ${(deployment.Package || "N/A")
      .substring(0, 38)
      .padEnd(39)} ║`
  );
  console.log(
    "╚═══════════════════════════════════════════════════════════╝\n"
  );
  console.log(
    `This deployment is now marked as the official/active deployment for ${network}.`
  );
  console.log(
    `Scripts using DEPLOYMENT_ID=active will now use this deployment.\n`
  );
}

if (require.main === module) {
  markActive();
}
