import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { config } from "./config.js";

// Short enough that the SDK's 3 attempts fit in the function's 10 s timeout, long enough for the first call after a cold start (about 130 ms).
const requestHandler = { connectionTimeout: 1_000, requestTimeout: 1_000 };

export const createDb = () => new DynamoDBClient({ endpoint: config.dynamodbEndpoint, requestHandler });
