import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { config } from "./config.js";

export const createDb = () => new DynamoDBClient({ endpoint: config.dynamodbEndpoint });
