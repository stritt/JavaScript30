import { createRemoteJWKSet, jwtVerify, SignJWT } from "jose";
import { createMiddleware } from "hono/factory";
import type { AppEnv, Env } from "../env";
import { apiError } from "./util";

const SESSION_TTL = "30d";
const ISSUER = "stepquest";
const APPLE_ISSUER = "https://appleid.apple.com";

// Module-scoped so the JWKS is cached across requests in the same isolate.
const appleJwks = createRemoteJWKSet(new URL("https://appleid.apple.com/auth/keys"));

const secretKey = (env: Env) => new TextEncoder().encode(env.JWT_SECRET);

export async function issueSession(env: Env, playerId: string): Promise<string> {
  return new SignJWT({})
    .setProtectedHeader({ alg: "HS256" })
    .setSubject(playerId)
    .setIssuer(ISSUER)
    .setIssuedAt()
    .setExpirationTime(SESSION_TTL)
    .sign(secretKey(env));
}

/** Verifies a Sign in with Apple identity token and returns Apple's stable user id (`sub`). */
export async function verifyAppleIdentityToken(env: Env, identityToken: string): Promise<string> {
  try {
    const { payload } = await jwtVerify(identityToken, appleJwks, {
      issuer: APPLE_ISSUER,
      audience: env.APPLE_BUNDLE_ID,
    });
    if (!payload.sub) throw new Error("missing sub");
    return payload.sub;
  } catch {
    throw apiError(401, "invalid_identity_token", "Apple identity token could not be verified");
  }
}

export const requireAuth = createMiddleware<AppEnv>(async (c, next) => {
  const header = c.req.header("Authorization");
  const token = header?.startsWith("Bearer ") ? header.slice(7) : null;
  if (!token) throw apiError(401, "unauthorized", "Missing bearer token");

  let playerId: string;
  try {
    const { payload } = await jwtVerify(token, secretKey(c.env), { issuer: ISSUER });
    if (!payload.sub) throw new Error("missing sub");
    playerId = payload.sub;
  } catch {
    throw apiError(401, "unauthorized", "Invalid or expired session");
  }

  if (c.env.RATE_LIMITER) {
    const { success } = await c.env.RATE_LIMITER.limit({ key: playerId });
    if (!success) throw apiError(429, "rate_limited", "Slow down, adventurer");
  }

  c.set("playerId", playerId);
  await next();
});
