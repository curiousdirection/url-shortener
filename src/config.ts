export const config = {
  port: Number(process.env.PORT ?? 3000),
  baseUrl: process.env.BASE_URL ?? "http://localhost:3000",
  databaseUrl:
    process.env.DATABASE_URL ?? "postgres://postgres:postgres@localhost:5432/urlshortener",
};
