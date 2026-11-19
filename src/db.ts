import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { config } from "./config.js";

// A stalled connection should fail in about a second and be retried, instead of hanging until the 10 s Lambda timeout.
// Each timeout is 1 s, which is far above a warm GetItem (a few ms) and the roughly 130 ms cold-start TLS setup, so healthy calls never trip it.
// With the SDK's default 3 attempts the worst case is about 3 x 1 s plus short retry backoff, well inside 10 s.
const requestTimeouts = { connectionTimeout: 1_000, requestTimeout: 1_000 };
const maxAttempts = 3;

export const createDb = () =>
  new DynamoDBClient({ endpoint: config.dynamodbEndpoint, maxAttempts, requestHandler: requestTimeouts });
