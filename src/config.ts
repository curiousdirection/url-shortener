export const config = {
  tableName: process.env.TABLE_NAME ?? "urls",
  // Set only for tests (DynamoDB Local).
  // In AWS it is left out, so the SDK uses the real service.
  dynamodbEndpoint: process.env.DYNAMODB_ENDPOINT,
};
