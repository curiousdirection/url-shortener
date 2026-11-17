import { afterEach, describe, expect, it, vi } from "vitest";
import { config } from "../src/config.js";
import { createPool } from "../src/db.js";

const { getAuthToken, Signer } = vi.hoisted(() => {
  const getAuthToken = vi.fn(async () => "token");
  const Signer = vi.fn(class {
    getAuthToken = getAuthToken;
  });
  return { getAuthToken, Signer };
});
vi.mock("@aws-sdk/rds-signer", () => ({ Signer }));

const url = "postgres://app@db.example.com:5432/urlshortener?sslmode=verify-full";
const iam = { ...config, databaseUrl: url, databaseIamAuth: true, awsRegion: "eu-north-1" };

afterEach(() => vi.clearAllMocks());

describe("createPool", () => {
  it("keeps the URL's password when IAM auth is off", async () => {
    const pool = createPool({ ...iam, databaseIamAuth: false });
    expect(Signer).not.toHaveBeenCalled();
    expect(typeof pool.options.password).not.toBe("function");
    await pool.end();
  });

  it("signs a token for each new connection when IAM auth is on", async () => {
    const pool = createPool(iam);
    expect(Signer).toHaveBeenCalledWith({
      hostname: "db.example.com",
      port: 5432,
      username: "app",
      region: "eu-north-1",
    });
    const password = pool.options.password as () => Promise<string>;
    expect(await password()).toBe("token");
    await password();
    expect(getAuthToken).toHaveBeenCalledTimes(2);
    // sslmode=verify-full from the URL still applies: TLS on, and not told to skip verifying.
    expect(pool.options.ssl).toBeTruthy();
    expect((pool.options.ssl as { rejectUnauthorized?: boolean }).rejectUnauthorized).not.toBe(false);
    await pool.end();
  });

  it("needs a region when IAM auth is on", () => {
    expect(() => createPool({ ...iam, awsRegion: undefined })).toThrow("AWS_REGION");
  });

  it("logs in with the token", async () => {
    // The token stands in for the test database's password, which is not in the URL here.
    const real = new URL(config.databaseUrl);
    getAuthToken.mockResolvedValueOnce(decodeURIComponent(real.password));
    real.password = "";
    const pool = createPool({ ...iam, databaseUrl: real.toString() });
    const { rows } = await pool.query("SELECT current_user AS u");
    expect(rows[0].u).toBe(decodeURIComponent(real.username));
    await pool.end();
  });
});
