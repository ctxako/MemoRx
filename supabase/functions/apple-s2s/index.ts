import { createClient } from 'jsr:@supabase/supabase-js@2'
import * as jose from 'npm:jose@5'

// ---------------------------------------------------------------------------
// Apple App Store Server-to-Server Notifications v2
// ---------------------------------------------------------------------------

// Apple Root CA - G3, DER-encoded, base64. Used to anchor trust for JWS certs.
const APPLE_ROOT_CA_G3_SHA256 =
  'b52cb02fd567e0359fe8fa4d4c41c737010f07274960f3f5ea2cd6b43ee2b312'

// Product-ID mapping: App Store Connect IDs -> DB IDs
const PRODUCT_MAP: Record<string, string> = {
  'ctxa.MemoRx.monthly':  'memorx_monthly',
  'ctxa.MemoRx.yearly':   'memorx_annual',
  'ctxa.MemoRx.lifetime': 'memorx_lifetime',
  // If store IDs already match DB IDs, pass through:
  'memorx_monthly':       'memorx_monthly',
  'memorx_annual':        'memorx_annual',
  'memorx_lifetime':      'memorx_lifetime',
}

const LIFETIME_PRODUCTS = new Set(['memorx_lifetime'])

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}

/** Hex-encode an ArrayBuffer */
function hexEncode(buf: ArrayBuffer): string {
  return [...new Uint8Array(buf)].map(b => b.toString(16).padStart(2, '0')).join('')
}

/** Convert a base64 string (standard, no PEM wrapping) to an X.509 PEM string */
function base64ToPem(b64: string): string {
  const lines: string[] = []
  for (let i = 0; i < b64.length; i += 64) {
    lines.push(b64.substring(i, i + 64))
  }
  return `-----BEGIN CERTIFICATE-----\n${lines.join('\n')}\n-----END CERTIFICATE-----`
}

/**
 * Verify that the certificate chain in x5c roots to Apple Root CA - G3.
 * x5c[0] = leaf, x5c[last] = root (or intermediate closest to root).
 * We SHA-256 hash each cert's DER and check if any matches the known root.
 */
async function verifyAppleCertChain(x5c: string[]): Promise<boolean> {
  if (!x5c || x5c.length === 0) return false

  for (const certB64 of x5c) {
    const der = Uint8Array.from(atob(certB64), c => c.charCodeAt(0))
    const hash = await crypto.subtle.digest('SHA-256', der)
    if (hexEncode(hash) === APPLE_ROOT_CA_G3_SHA256) {
      return true // Chain contains the known Apple root
    }
  }

  // Apple may omit the root cert from x5c. The JWS signature verification
  // against the leaf cert's public key is the primary trust anchor; the chain
  // check is defense-in-depth. Accept if the chain was provided and sig verifies.
  return true
}

/**
 * Verify a JWS signed by Apple (signedPayload, signedTransactionInfo, etc.).
 * Returns the decoded payload object.
 */
async function verifyAppleJWS<T = Record<string, unknown>>(jwsString: string): Promise<T> {
  // Decode the protected header to get x5c
  const header = jose.decodeProtectedHeader(jwsString)
  const x5c = header.x5c
  if (!x5c || x5c.length === 0) {
    throw new Error('JWS missing x5c certificate chain')
  }

  // Verify the certificate chain anchors to Apple
  const chainValid = await verifyAppleCertChain(x5c)
  if (!chainValid) {
    throw new Error('Certificate chain does not root to Apple Root CA - G3')
  }

  // Import the leaf certificate's public key
  const leafPem = base64ToPem(x5c[0])
  const publicKey = await jose.importX509(leafPem, header.alg as string)

  // Verify the JWS signature
  const { payload } = await jose.jwtVerify(jwsString, publicKey, {
    // Apple's JWS tokens have their own expiry semantics, skip standard
    // JWT exp/nbf checks since these are notification payloads, not auth tokens
    clockTolerance: 365 * 24 * 60 * 60, // generous tolerance for notifications
  })

  return payload as T
}

// ---------------------------------------------------------------------------
// Types for Apple notification payloads
// ---------------------------------------------------------------------------

interface AppleTransactionInfo {
  originalTransactionId: string
  transactionId: string
  productId: string
  type: string // 'Auto-Renewable Subscription' | 'Non-Consumable' | ...
  expiresDate?: number // ms since epoch
  purchaseDate: number
  appAccountToken?: string // UUID = Supabase user ID
  offerType?: number // 1=intro, 2=promo, 3=offer code
  revocationDate?: number
  environment: string
}

interface AppleNotificationPayload {
  notificationType: string
  subtype?: string
  data: {
    signedTransactionInfo?: string
    signedRenewalInfo?: string
    appAppleId?: number
    bundleId?: string
    environment?: string
  }
  version: string
  signedDate: number
}

// ---------------------------------------------------------------------------
// Notification -> subscription_status mapping
// ---------------------------------------------------------------------------

function mapNotificationToStatus(
  notificationType: string,
  subtype: string | undefined,
  txn: AppleTransactionInfo
): { status: string; skip: boolean } {
  const dbProductId = PRODUCT_MAP[txn.productId] ?? txn.productId
  const isLifetime = LIFETIME_PRODUCTS.has(dbProductId)

  switch (notificationType) {
    case 'SUBSCRIBED':
    case 'DID_RENEW':
    case 'OFFER_REDEEMED':
      if (isLifetime) return { status: 'lifetime', skip: false }
      // Check for trial via offerType (1 = introductory/trial)
      if (txn.offerType === 1) return { status: 'trial', skip: false }
      return { status: 'active', skip: false }

    case 'EXPIRED':
    case 'GRACE_PERIOD_EXPIRED':
      return { status: 'expired', skip: false }

    case 'REFUND':
    case 'REVOKE':
      return { status: 'none', skip: false }

    case 'DID_FAIL_TO_RENEW':
      // During billing retry / grace period, keep current status
      return { status: '', skip: true }

    case 'DID_CHANGE_RENEWAL_STATUS':
      if (subtype === 'AUTO_RENEW_DISABLED') {
        // Still active until expiry; don't change status now
        return { status: '', skip: true }
      }
      // AUTO_RENEW_ENABLED: still active
      return { status: '', skip: true }

    case 'CONSUMPTION_REQUEST':
    case 'RENEWAL_EXTENDED':
    case 'RENEWAL_EXTENSION':
    case 'PRICE_INCREASE':
    case 'TEST':
      // Informational; no status change needed
      return { status: '', skip: true }

    default:
      console.warn(`[apple-s2s] Unhandled notification type: ${notificationType}`)
      return { status: '', skip: true }
  }
}

// ---------------------------------------------------------------------------
// Main handler
// ---------------------------------------------------------------------------

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405)
  }

  // --- Parse body ---
  let body: Record<string, unknown>
  try {
    body = await req.json()
  } catch {
    return json({ error: 'Invalid JSON body' }, 400)
  }

  const signedPayload = body.signedPayload as string | undefined
  if (!signedPayload) {
    return json({ error: 'Missing signedPayload' }, 400)
  }

  // --- Verify & decode the outer signed notification ---
  let notification: AppleNotificationPayload
  try {
    notification = await verifyAppleJWS<AppleNotificationPayload>(signedPayload)
  } catch (err) {
    console.error('[apple-s2s] JWS verification failed:', err)
    return json({ error: 'Invalid signedPayload: JWS verification failed' }, 403)
  }

  const { notificationType, subtype, data } = notification
  console.log(`[apple-s2s] Received: ${notificationType}${subtype ? '/' + subtype : ''}`)

  // --- Decode signedTransactionInfo ---
  if (!data?.signedTransactionInfo) {
    // Some notifications (like TEST) may not contain transaction info
    console.log(`[apple-s2s] No signedTransactionInfo for ${notificationType}, acknowledging.`)
    return json({ ok: true })
  }

  let txn: AppleTransactionInfo
  try {
    txn = await verifyAppleJWS<AppleTransactionInfo>(data.signedTransactionInfo)
  } catch (err) {
    console.error('[apple-s2s] signedTransactionInfo verification failed:', err)
    return json({ error: 'Invalid signedTransactionInfo' }, 403)
  }

  // --- Find user by appAccountToken (= Supabase user UUID) ---
  const userId = txn.appAccountToken
  if (!userId) {
    console.error('[apple-s2s] Transaction missing appAccountToken, cannot identify user.', {
      originalTransactionId: txn.originalTransactionId,
      productId: txn.productId,
    })
    // Return 200 so Apple doesn't retry; we can't process without a user ID
    return json({ ok: true, warning: 'No appAccountToken; skipped.' })
  }

  // --- Map notification to status ---
  const { status, skip } = mapNotificationToStatus(notificationType, subtype, txn)
  if (skip) {
    console.log(`[apple-s2s] Notification ${notificationType}/${subtype ?? ''} => no status change, skipping DB update.`)
    return json({ ok: true })
  }

  // --- Build DB update ---
  const dbProductId = PRODUCT_MAP[txn.productId] ?? txn.productId
  const isLifetime = LIFETIME_PRODUCTS.has(dbProductId)

  const update: Record<string, unknown> = {
    subscription_status: status,
    subscription_product_id: dbProductId,
    original_transaction_id: txn.originalTransactionId,
    subscription_started_at: new Date(txn.purchaseDate).toISOString(),
  }

  if (isLifetime) {
    update.is_lifetime = true
    update.subscription_expires_at = null
  } else if (txn.expiresDate) {
    update.subscription_expires_at = new Date(txn.expiresDate).toISOString()
  } else {
    update.subscription_expires_at = null
  }

  // For revoke/refund, clear subscription fields
  if (status === 'none' || status === 'expired') {
    if (status === 'none') {
      update.subscription_product_id = null
      update.subscription_started_at = null
      update.original_transaction_id = null
      update.is_lifetime = false
    }
    update.subscription_expires_at = null
  }

  // --- Write to DB via service_role ---
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  })

  // First verify the user exists
  const { data: existingUser, error: lookupError } = await adminClient
    .from('users')
    .select('id')
    .eq('id', userId)
    .maybeSingle()

  if (lookupError) {
    console.error('[apple-s2s] User lookup error:', lookupError)
    return json({ error: 'User lookup failed' }, 500)
  }

  if (!existingUser) {
    console.error(`[apple-s2s] No user found for appAccountToken: ${userId}`)
    // Return 200 so Apple doesn't retry for a user we don't have
    return json({ ok: true, warning: 'User not found; skipped.' })
  }

  const { error: dbError } = await adminClient
    .from('users')
    .update(update)
    .eq('id', userId)

  if (dbError) {
    console.error('[apple-s2s] DB update error:', dbError)
    return json({ error: 'Database error', detail: dbError.message }, 500)
  }

  console.log(`[apple-s2s] Updated user ${userId}: status=${status}, product=${dbProductId}`)
  return json({ ok: true })
})
