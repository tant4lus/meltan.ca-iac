# cdn

CloudFront distribution fronting a `static-site-bucket` (`oai` mode): origin access identity, default cache behavior, and a CloudFront Function (viewer-request) that rewrites directory-style request URIs to append `index.html` — the fix for the 403 documented in meltan.ca#27.

Each instantiation owns its own copy of the function; it isn't shared across environments.
