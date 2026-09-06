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

**An empty value counts as unset.** `SMART_AUDIENCE=""` in a compose file or Helm
chart is indistinguishable from omitting it, so empty (and whitespace-only) values
are normalised to absent before any rule is applied. The one exception is
`SMART_ISSUER`: an empty value fails at startup rather than disabling SMART, because
silently disabling it would serve FHIR with no authentication at all.

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

Because an empty value is normalised to absent first, `SMART_AUTHORIZE_URL=""` with a
real `SMART_TOKEN_URL` fails at startup too, rather than publishing an empty
`authorization_endpoint`.

## What the endpoints gate

Siming does not run the authorization server, so it must not describe one that is not
configured. Everything below appears only when both endpoints are set, and disappears
together when they are not:

| Field | Value |
|---|---|
| `authorization_endpoint` / `token_endpoint` | as configured |
| `code_challenge_methods_supported` | `["S256"]` |
| `grant_types_supported` | `["authorization_code", "refresh_token"]` — required by SMART 2.0 once endpoints are advertised; `refresh_token` because `offline_access` is in `scopes_supported` and no other grant redeems it |
| `token_endpoint_auth_methods_supported` | `["none", "private_key_jwt", "client_secret_basic"]` — `"none"` is for public clients (native apps with no secret) authenticating via PKCE. Describes the token endpoint, so it is not emitted without one |
| `capabilities` | adds `launch-standalone`, `client-public`, `context-standalone-patient` — the last is patient context *in a standalone launch* and cannot stand without the launch |

`GET /metadata` carries the same two endpoints in the `oauth-uris` extension on
`rest.security`. Both documents derive from `SmartConfiguration.authorizationServer`,
a single property, so they cannot disagree.

A deployment with no authorization server keeps only `issuer`, `scopes_supported`,
`response_types_supported`, `jwks_uri` and the `permission-*` capabilities.

## Unauthenticated paths

`/health`, `/metadata`, `/metrics`, and `/.well-known/smart-configuration` bypass
`BearerAuthMiddleware`. Everything else requires a bearer token once `SMART_ISSUER` is set.
