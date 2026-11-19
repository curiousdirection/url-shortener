import {
  ConditionalCheckFailedException,
  DynamoDBClient,
  GetItemCommand,
  PutItemCommand,
} from "@aws-sdk/client-dynamodb";
import { generateCode, type GenerateCode } from "./codeGenerator.js";

const MAX_ATTEMPTS = 5;

export class AliasTakenError extends Error {}

export interface UrlService {
  create(longUrl: string, alias?: string): Promise<string>;
  resolve(code: string): Promise<string | null>;
}

export function createUrlService(
  db: DynamoDBClient,
  tableName: string,
  newCode: GenerateCode = generateCode,
): UrlService {
  // Writes the link only if the code is free. Returns false if it is taken.
  const putIfFree = async (code: string, longUrl: string) => {
    try {
      await db.send(
        new PutItemCommand({
          TableName: tableName,
          Item: { code: { S: code }, long_url: { S: longUrl } },
          ConditionExpression: "attribute_not_exists(code)",
        }),
      );
      return true;
    } catch (e) {
      if (e instanceof ConditionalCheckFailedException) return false;
      throw e;
    }
  };

  const get = async (code: string, consistent: boolean) => {
    const { Item } = await db.send(
      new GetItemCommand({
        TableName: tableName,
        Key: { code: { S: code } },
        ConsistentRead: consistent,
      }),
    );
    return Item?.long_url?.S ?? null;
  };

  return {
    async create(longUrl, alias) {
      if (alias) {
        if (await putIfFree(alias, longUrl)) return alias;
        throw new AliasTakenError(alias);
      }
      // A random code can match an existing code or alias; draw another.
      for (let i = 0; i < MAX_ATTEMPTS; i++) {
        const code = newCode();
        if (await putIfFree(code, longUrl)) return code;
      }
      throw new Error("could not allocate a unique code");
    },

    // The default read is cheaper but can miss an item written a moment ago. Ask again with a consistent read, so a link that was just created never answers 404.
    async resolve(code) {
      return (await get(code, false)) ?? (await get(code, true));
    },
  };
}
