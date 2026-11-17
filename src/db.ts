import { Signer } from "@aws-sdk/rds-signer";
import pg from "pg";
import { config } from "./config.js";

// With IAM auth, the password is a token that RDS accepts for 15 minutes, signed with the
// task role's credentials. pg calls the function for each new connection, so the pool never
// holds an expired one; connections that are already open stay open.
export const createPool = (cfg = config) => {
  if (!cfg.databaseIamAuth) return new pg.Pool({ connectionString: cfg.databaseUrl });

  if (!cfg.awsRegion) throw new Error("DATABASE_IAM_AUTH is on but AWS_REGION is not set");
  // pg ignores a password function when there is a connection string, so the URL is taken
  // apart here instead. A Client that never connects is just the URL's parsed settings,
  // including the TLS ones from sslmode.
  const { host, port, user, database, ssl } = new pg.Client(cfg.databaseUrl);
  if (!user) throw new Error("DATABASE_URL has no user");
  const signer = new Signer({ hostname: host, port, username: user, region: cfg.awsRegion });
  return new pg.Pool({ host, port, user, database, ssl, password: () => signer.getAuthToken() });
};
