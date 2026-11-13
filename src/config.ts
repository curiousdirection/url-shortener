export const config = {
  port: Number(process.env.PORT ?? 3000),
  // Unset or empty: shortUrl is built from the request (see app.ts).
  baseUrl: process.env.BASE_URL || undefined,
  databaseUrl:
    process.env.DATABASE_URL ?? "postgres://postgres:postgres@localhost:5432/urlshortener",
};
