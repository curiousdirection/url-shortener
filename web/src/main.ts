import { sha256Hex } from "./sha256.js";

const $ = <T extends HTMLElement>(id: string) => document.getElementById(id) as T;
const form = $<HTMLFormElement>("form");
const submit = $<HTMLButtonElement>("submit");
const errorBox = $("error");
const result = $("result");
const shortUrl = $<HTMLAnchorElement>("short-url");
const copy = $<HTMLButtonElement>("copy");

const showError = (message: string) => {
  errorBox.textContent = message;
  errorBox.hidden = false;
  result.hidden = true;
};

// The API's message: its { error } string, or on a 400 zod's issues, which arrive as JSON text in error.message.
async function errorText(res: Response): Promise<string> {
  if (res.status === 429) return "Too many requests. Try again later.";
  const body = (await res.json().catch(() => null)) as { error?: unknown } | null;
  const error = body?.error;
  if (typeof error === "string") return error;
  if (res.status === 400 && typeof (error as { message?: unknown })?.message === "string") {
    try {
      const issues = JSON.parse((error as { message: string }).message) as { path: (string | number)[]; message: string }[];
      return issues.map((i) => `${i.path.join(".")}: ${i.message}`).join("; ");
    } catch {
      // Not zod's format: fall through.
    }
  }
  return `Something went wrong (${res.status}).`;
}

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  errorBox.hidden = true;
  result.hidden = true;
  const alias = $<HTMLInputElement>("alias").value.trim();
  // The body is built once, so the string that is hashed is the string that is sent.
  const body = JSON.stringify({ url: $<HTMLInputElement>("url").value.trim(), ...(alias && { alias }) });
  submit.disabled = true;
  try {
    const res = await fetch("/api/urls", {
      method: "POST",
      headers: { "content-type": "application/json", "x-amz-content-sha256": await sha256Hex(body) },
      body,
    });
    if (!res.ok) return showError(await errorText(res));
    const created = (await res.json()) as { shortUrl: string };
    shortUrl.href = created.shortUrl;
    shortUrl.textContent = created.shortUrl;
    copy.textContent = "Copy";
    result.hidden = false;
  } catch {
    showError("Could not reach the server.");
  } finally {
    submit.disabled = false;
  }
});

copy.addEventListener("click", async () => {
  try {
    await navigator.clipboard.writeText(shortUrl.href);
    copy.textContent = "Copied";
  } catch {
    copy.textContent = "Copy failed";
  }
});
