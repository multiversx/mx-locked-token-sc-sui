import dotenv from "dotenv";
import path from "path";
import fs from "fs";
import { SuiClient } from "@mysten/sui/client";

import {
  readJSONFile,
  writeJSONFile,
} from "./mx-bridge-typescript/src/utils/json";
import {
  getKeyPairFromPvtKey,
  getKeyPairFromSeed,
} from "./mx-bridge-typescript/src/utils/keypair";
import { SuiProxy } from "./mx-bridge-typescript/src/clients/sui";

dotenv.config({ path: path.join(__dirname, ".env") });

type WalletScheme = "ED25519" | "SECP256K1" | "SECP256R1";

export const ENV = {
  DEPLOY_ON: process.env.DEPLOY_ON,
  DEPLOYER_KEY: process.env.DEPLOYER_KEY || "0x",
  DEPLOYER_PHRASE: process.env.DEPLOYER_PHRASE || "0x",
  WALLET_SCHEME: (process.env.WALLET_SCHEME || "ED25519") as WalletScheme,
  DEPLOYMENT_ID: process.env.DEPLOYMENT_ID || "active",
};

console.log(`ENVIVORMENT: ${ENV.DEPLOY_ON}`);

export const CONFIG = readJSONFile(path.join(__dirname, "config.json"))[
  ENV.DEPLOY_ON
];

const deploymentPath = path.join(__dirname, "deployment.json");

if (!fs.existsSync(deploymentPath)) {
  const emptyDeployment = {
    testnet: { deployments: [] },
    mainnet: { deployments: [] },
    devnet: { deployments: [] },
  };
  const x = writeJSONFile(emptyDeployment, deploymentPath); // TODO
  console.log("\nx = ", x, "\n");
  console.log("Created empty deployment.json file");
}

let deploymentData: any = {};
try {
  const allDeployments = readJSONFile(deploymentPath);
  const networkData = allDeployments[ENV.DEPLOY_ON] || { deployments: [] };
  const deployments = networkData.deployments || [];

  if (deployments.length === 0) {
    console.warn(`No deployments found for ${ENV.DEPLOY_ON}`);
  } else {
    let selectedDeployment = null;

    // Try to find the requested deployment
    if (ENV.DEPLOYMENT_ID === "active") {
      selectedDeployment = deployments.find((d: any) => d.active === true);
      if (!selectedDeployment) {
        console.warn(
          `No active deployment set for ${ENV.DEPLOY_ON}. Use 'mark-active' script to set one.`
        );
      }
    } else {
      const deploymentId = parseInt(ENV.DEPLOYMENT_ID, 10);
      selectedDeployment = deployments.find((d: any) => d.id === deploymentId);
      if (!selectedDeployment) {
        console.warn(
          `Deployment #${deploymentId} not found on ${ENV.DEPLOY_ON}`
        );
      }
    }

    // Fallback to active deployment if requested one not found
    if (!selectedDeployment) {
      selectedDeployment = deployments.find((d: any) => d.active === true);
      if (selectedDeployment) {
        console.log(
          `Falling back to active deployment: #${selectedDeployment.id}`
        );
      } else {
        console.error("No active deployment available.");
        console.log("Available deployments:");
        deployments.forEach((d: any) => {
          const activeMarker = d.active ? " [ACTIVE]" : "";
          console.log(`  - #${d.id} (${d.createdAt})${activeMarker}`);
        });
        throw new Error("No usable deployment found");
      }
    } else {
      console.log(
        `Using deployment: #${selectedDeployment.id} (created: ${selectedDeployment.createdAt})`
      );
    }

    deploymentData = selectedDeployment;
  }
} catch (error) {
  console.warn("Error loading deployment.json:", error);
}

export const DEPLOYMENT = deploymentData;

export const SUI_PROXY =
  DEPLOYMENT.packageId && DEPLOYMENT.bridgeObjectId
    ? new SuiProxy(CONFIG.rpc, DEPLOYMENT.packageId, DEPLOYMENT.bridgeObjectId)
    : null;

export const SUI_CLIENT = new SuiClient({ url: CONFIG.rpc });

export const ADMIN =
  ENV.DEPLOYER_KEY != "0x"
    ? getKeyPairFromPvtKey(ENV.DEPLOYER_KEY, ENV.WALLET_SCHEME)
    : getKeyPairFromSeed(ENV.DEPLOYER_PHRASE, ENV.WALLET_SCHEME);

// TODO: Define OnChainCalls and QueryChain classes
// export const ONCHAIN_CALLS = new OnChainCalls(SUI_CLIENT, DEPLOYMENT, {
//   signer: ADMIN,
// });

// export const QUERY_CHAIN = new QueryChain(SUI_CLIENT);
