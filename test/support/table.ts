import { DeleteItemCommand, ScanCommand, type DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { createTable } from "../../src/createTable.js";

// vitest.config.ts only lets tests run against a *_test table on
// DynamoDB Local, so these helpers can't touch real data.
export async function prepareTable(db: DynamoDBClient, tableName: string) {
  await createTable(db, tableName);
  await clearTable(db, tableName);
}

export async function clearTable(db: DynamoDBClient, tableName: string) {
  let startKey;
  do {
    const page = await db.send(
      new ScanCommand({ TableName: tableName, ProjectionExpression: "code", ExclusiveStartKey: startKey }),
    );
    for (const item of page.Items ?? []) {
      await db.send(new DeleteItemCommand({ TableName: tableName, Key: { code: item.code } }));
    }
    startKey = page.LastEvaluatedKey;
  } while (startKey);
}
