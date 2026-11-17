export const config = {
  port: Number(process.env.PORT ?? 3000),
  databaseUrl:
    process.env.DATABASE_URL ?? "postgres://postgres:postgres@localhost:5432/urlshortener",
  // Off locally, so dev and tests use the URL's password. On in AWS (infra/app/main.tf).
  databaseIamAuth: process.env.DATABASE_IAM_AUTH === "true",
  // Set by ECS in the task; only read when IAM auth is on.
  awsRegion: process.env.AWS_REGION,
};
