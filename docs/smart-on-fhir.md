# SMART on FHIR

Siming is a **resource server**. It validates bearer tokens and publishes discovery
metadata; it never issues tokens. The authorization server is a separate deployment
(Keycloak, smart-launcher-v2, …).

SMART support is off by default and turns on when `SMART_ISSUER` is set.

## Environment variables

| Variable | Required | Purpose |
|---|---|---|
| `SMART_ISSUER` | yes — enables SMART | Expected `iss` claim. Tokens with a different issuer are rejected. |
| `SMART_JWKS_URL` | one of these two | JWKS endpoint, fetched once at startup. |
| `SMART_PUBLIC_KEY_PEM` | one of these two | RSA public key (RS256), as an alternative to JWKS. |
| `SMART_AUDIENCE` | no | Expected `aud` claim. Unset means `aud` is **not checked**. |
| `SMART_AUTHORIZE_URL` | with `SMART_TOKEN_URL` | Authorization server's `authorization_endpoint`. |
| `SMART_TOKEN_URL` | with `SMART_AUTHORIZE_URL` | Authorization server's `token_endpoint`. |

Neither JWKS nor PEM set → the server starts and logs a warning, but every token
fails verification.

## `aud` matching is exact

`BearerAuthMiddleware` compares via JWTKit's `AudienceClaim.verifyIntendedAudience(includes:)`,
which is a plain `contains` over the claim's values:

- **Byte-for-byte string equality, case-sensitive.** No URL normalisation.
- **A trailing slash is a different string** — `https://fhir.example.com` never matches
  `https://fhir.example.com/`. This is the most common misconfiguration, and it
  surfaces as "the token is valid but every request 401s".
- **An array `aud` is accepted**; the check passes if any element matches.
- `SMART_AUDIENCE` set but the token carries no `aud` → 401 `Missing aud claim`.

Use one literal spelling of the FHIR base URL everywhere: the client's `aud=` authorize
parameter, the authorization server's audience mapper, and `SMART_AUDIENCE`.

## Authorization-server endpoints are both-or-neither

`SMART_AUTHORIZE_URL` and `SMART_TOKEN_URL` must be set together. Setting exactly one
fails at startup rather than serving a half-built discovery document — a client that
requires both endpoints would otherwise fail while decoding, far from the actual
misconfiguration.

When both are set, `GET /.well-known/smart-configuration` gains `authorization_endpoint`,
`token_endpoint`, `code_challenge_methods_supported: ["S256"]`, and the
`launch-standalone` / `client-public` capabilities; `GET /metadata` gains the matching
`oauth-uris` extension on `rest.security`. When neither is set, none of those appear —
this deployment cannot support a standalone launch, so it does not claim to.

`token_endpoint_auth_methods_supported` includes `"none"`: public clients (native apps
with no client secret) authenticate with PKCE.

## Unauthenticated paths

`/health`, `/metadata`, `/metrics`, and `/.well-known/smart-configuration` bypass
`BearerAuthMiddleware`. Everything else requires a bearer token once `SMART_ISSUER` is set.
