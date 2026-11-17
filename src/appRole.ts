import type pg from "pg";

// Creates the database user the app runs as, and gives it what it needs. Run as the RDS
// master user by `node dist/setupDb.js`; see infra/scripts/release.sh. Safe to run again.
//
// The master user is not a superuser: it has CREATEROLE and rds_superuser. On PostgreSQL 16 a
// CREATEROLE user only gets ADMIN on a role it creates, with neither SET nor INHERIT, and
// ALTER ... OWNER TO needs SET on the new owner. So the master user joins the role for the
// length of this transaction, then leaves it, so that it stays outside rds_iam's reach (RDS
// makes a member of rds_iam log in with a token). Before it leaves, it grants itself the
// tables, because tasks from before this change still connect as the master user. The test
// runs this as a non-superuser master (test/appRole.test.ts).
//
// rds_iam exists only on RDS; skipping it lets the script run on a local Postgres too.
// REASSIGN OWNED would also move the database itself, so owners are changed one by one.
// Everything runs in one DO block, so it is one transaction.
const SETUP_SQL = `
DO $$
DECLARE r record;
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'app') THEN
    CREATE ROLE app LOGIN;
  END IF;
  IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'rds_iam') THEN
    GRANT rds_iam TO app;
  END IF;

  EXECUTE format('GRANT CONNECT ON DATABASE %I TO app', current_database());
  GRANT USAGE, CREATE ON SCHEMA public TO app;
  GRANT app TO CURRENT_USER WITH INHERIT TRUE, SET TRUE;

  -- Sequences that belong to a column move with their table.
  FOR r IN
    SELECT c.relname, c.relkind FROM pg_class c
    WHERE c.relnamespace = 'public'::regnamespace
      AND c.relkind IN ('r', 'p', 'S')
      AND c.relowner <> 'app'::regrole
      AND NOT EXISTS (
        SELECT FROM pg_depend d
        WHERE d.classid = 'pg_class'::regclass AND d.objid = c.oid AND d.deptype IN ('a', 'i')
      )
  LOOP
    EXECUTE format('ALTER %s public.%I OWNER TO app', CASE r.relkind WHEN 'S' THEN 'SEQUENCE' ELSE 'TABLE' END, r.relname);
  END LOOP;

  GRANT ALL ON ALL TABLES IN SCHEMA public TO CURRENT_USER;
  GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO CURRENT_USER;
  REVOKE app FROM CURRENT_USER;
END
$$`;

export async function setupAppRole(pool: pg.Pool): Promise<void> {
  await pool.query(SETUP_SQL);
}
