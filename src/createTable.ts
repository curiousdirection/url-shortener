import { CreateTableCommand, DynamoDBClient, ResourceInUseException } from "@aws-sdk/client-dynamodb";

// Creates the table in DynamoDB Local (npm run db:setup). Same key and billing mode as the real
// table in infra/foundation/dynamodb.tf. Does nothing if it already exists.
export async function createTable(db: DynamoDBClient, tableName: string): Promise<void> {
  try {
    await db.send(
      new CreateTableCommand({
        TableName: tableName,
        AttributeDefinitions: [{ AttributeName: "code", AttributeType: "S" }],
        KeySchema: [{ AttributeName: "code", KeyType: "HASH" }],
        BillingMode: "PAY_PER_REQUEST",
      }),
    );
  } catch (e) {
    if (!(e instanceof ResourceInUseException)) throw e;
  }
}
