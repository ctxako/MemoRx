// ---------------------------------------------------------------------------
// apple_verify.ts — Real Apple JWS verification (shared)
// ---------------------------------------------------------------------------
// Uses Apple's official app-store-server-library, which performs FULL x5c
// certificate-chain validation: every cert is checked to be signed by the
// next, the chain is anchored to the pinned Apple Root CA - G3, the leaf must
// carry Apple's App Store receipt-signing OID, and the JWS signature is
// verified against that validated leaf. It also enforces bundleId and
// environment. This replaces the previous hand-rolled verifier, which
// effectively trusted any self-signed cert the caller placed in x5c.
//
// enableOnlineChecks is intentionally FALSE: the offline chain/OID/signature
// checks are what block forgery (verified against a self-signed forged JWS,
// which is rejected as INVALID_CERTIFICATE). OCSP online revocation adds an
// outbound-network dependency on the happy path; leave it off unless you have
// confirmed a real production purchase still verifies with it on. Flip via the
// code below if desired.
// ---------------------------------------------------------------------------

import { Buffer } from 'node:buffer'
import {
  SignedDataVerifier,
  Environment,
  VerificationException,
} from 'npm:@apple/app-store-server-library@1'

export { VerificationException }

// Apple Root CA - G3 (DER, base64). SHA-256:
// 63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179
const APPLE_ROOT_CA_G3_B64 =
  'MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBSb290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtfTjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySrMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gAMGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM6BgD56KyKA=='

const BUNDLE_ID = 'ctxa.MemoRx'
const APP_APPLE_ID = 6761398713
const ENABLE_ONLINE_CHECKS = false

// Production-only by default. Set the ALLOW_SANDBOX_RECEIPTS secret to "true"
// during TestFlight/sandbox testing windows to also accept sandbox receipts.
const ALLOW_SANDBOX =
  (Deno.env.get('ALLOW_SANDBOX_RECEIPTS') ?? '').trim().toLowerCase() === 'true'

const roots = [Buffer.from(APPLE_ROOT_CA_G3_B64, 'base64')]

function makeVerifier(env: Environment): SignedDataVerifier {
  return new SignedDataVerifier(
    roots,
    ENABLE_ONLINE_CHECKS,
    env,
    BUNDLE_ID,
    env === Environment.PRODUCTION ? APP_APPLE_ID : undefined,
  )
}

// Production first; sandbox appended only when explicitly allowed. A receipt is
// accepted only if it verifies against one of these environments — a sandbox
// receipt fails cleanly when sandbox is disabled.
const verifiers: SignedDataVerifier[] = [makeVerifier(Environment.PRODUCTION)]
if (ALLOW_SANDBOX) verifiers.push(makeVerifier(Environment.SANDBOX))

export interface AppleTransactionInfo {
  originalTransactionId: string
  transactionId: string
  productId: string
  type: string
  expiresDate?: number
  purchaseDate: number
  appAccountToken?: string
  offerType?: number
  revocationDate?: number
  bundleId?: string
  environment: string
}

/** Verify a StoreKit signedTransactionInfo JWS. Throws if not genuinely Apple-signed. */
export async function verifyTransaction(jws: string): Promise<AppleTransactionInfo> {
  let lastErr: unknown
  for (const v of verifiers) {
    try {
      return (await v.verifyAndDecodeTransaction(jws)) as unknown as AppleTransactionInfo
    } catch (e) {
      lastErr = e
    }
  }
  throw lastErr
}

/** Verify an App Store Server Notification v2 signedPayload. Throws if not genuinely Apple-signed. */
export async function verifyNotification(jws: string): Promise<any> {
  let lastErr: unknown
  for (const v of verifiers) {
    try {
      return await v.verifyAndDecodeNotification(jws)
    } catch (e) {
      lastErr = e
    }
  }
  throw lastErr
}
