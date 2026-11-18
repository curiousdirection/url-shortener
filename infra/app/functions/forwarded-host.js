// CloudFront Function (viewer request, JavaScript runtime 2.0) for /api/*. It copies the host the
// viewer called into X-Forwarded-Host, because the origin request carries the function URL's host
// instead. It always overwrites the header, so a viewer can't set it. Read by src/app.ts.
function handler(event) {
  var request = event.request;
  if (request.headers.host) {
    request.headers["x-forwarded-host"] = { value: request.headers.host.value };
  } else {
    delete request.headers["x-forwarded-host"];
  }
  return request;
}
