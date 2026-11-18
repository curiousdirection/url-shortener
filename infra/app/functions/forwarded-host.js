// Runs on /api/*. Copies the viewer's Host into X-Forwarded-Host for src/app.ts, since the function
// gets its own host instead. Always overwrites the header, so a viewer can't fake it.
function handler(event) {
  var request = event.request;
  if (request.headers.host) {
    request.headers["x-forwarded-host"] = { value: request.headers.host.value };
  } else {
    delete request.headers["x-forwarded-host"];
  }
  return request;
}
