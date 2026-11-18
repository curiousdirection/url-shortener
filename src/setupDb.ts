import { config } from "./config.js";
import { createTable } from "./createTable.js";
import { createDb } from "./db.js";

// Local use only: refuse to touch the real service.
if (!config.dynamodbEndpoint) {
  throw new Error("DYNAMODB_ENDPOINT is not set. This script is only for DynamoDB Local.");
}

const db = createDb();
try {
  await createTable(db, config.tableName);
  console.log(`table ${config.tableName} is ready`);
} finally {
  db.destroy();
}
