export const config = {
  port: Number(process.env.PORT ?? 3000),
  tableName: process.env.TABLE_NAME ?? "urls",
  // Set only for local development and tests (DynamoDB Local).
  // In AWS it is left out, so the SDK uses the real service.
  dynamodbEndpoint: process.env.DYNAMODB_ENDPOINT,
  // Comma-separated domains that links may not point at, subdomains included.
  blockedDomains: (process.env.BLOCKED_DOMAINS ?? "")
    .split(",")
    .map((d) => d.trim().toLowerCase())
    .filter(Boolean),
};
