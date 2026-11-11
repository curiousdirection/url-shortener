import { buildApp } from "./app.js";
import { createCodeGenerator } from "./codeGenerator.js";
import { config } from "./config.js";
import { createPool } from "./db.js";
import { createUrlService } from "./urlService.js";

const pool = createPool();
const app = buildApp(createUrlService(pool, createCodeGenerator(pool)), config.baseUrl);

app.listen(config.port, () => console.log(`listening on :${config.port}`));
