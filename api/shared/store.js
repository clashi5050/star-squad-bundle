// Shared Cosmos client + auth helper for the Star Squad managed API.
// Connection details come from the Static Web App's app settings, which are
// set by Terraform (COSMOS_* -> azurerm_static_web_app.app_settings).
const { CosmosClient } = require("@azure/cosmos");

const endpoint = process.env.COSMOS_ENDPOINT;
const key = process.env.COSMOS_KEY;
const dbName = process.env.COSMOS_DATABASE || "starsquad";
const containerName = process.env.COSMOS_CONTAINER || "families";

// One client per cold start, reused across invocations.
const container = new CosmosClient({ endpoint, key })
  .database(dbName)
  .container(containerName);

// Static Web Apps injects the signed-in user as a base64 JSON header.
// Returns the decoded principal ({ userId, userDetails, ... }) or null.
function getUser(req) {
  const header = req.headers && req.headers["x-ms-client-principal"];
  if (!header) return null;
  try {
    return JSON.parse(Buffer.from(header, "base64").toString("utf8"));
  } catch (e) {
    return null;
  }
}

module.exports = { container, getUser };
