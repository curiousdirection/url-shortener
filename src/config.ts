export const config = {
  port: Number(process.env.PORT ?? 3000),
  // Unset: shortUrl is built from the request (see app.ts).
  baseUrl: process.env.BASE_URL,
  databaseUrl:
    process.env.DATABASE_URL ?? "postgres://postgres:postgres@localhost:5432/urlshortener",
};
