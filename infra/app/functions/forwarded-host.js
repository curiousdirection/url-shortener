// Runs inside CloudFront on /api/* requests.
// CloudFront replaces Host with our Lambda's own address, so
// this first copies the visitor's Host into X-Forwarded-Host
// (src/app.ts reads it for shortUrl).
// It always overwrites the header, so a visitor can't set it to
// another address.
function handler(event) {
  var request = event.request;
  if (request.headers.host) {
    request.headers["x-forwarded-host"] = { value: request.headers.host.value };
  } else {
    delete request.headers["x-forwarded-host"];
  }
  return request;
}
