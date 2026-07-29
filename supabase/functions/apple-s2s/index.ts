import { createClient } from 'jsr:@supabase/supabase-js@2'
import { verifyTransaction, verifyNotification, AppleTransactionInfo } from '../_shared/apple_verify.ts'

// ---------------------------------------------------------------------------
// Apple App Store Server-to-Server Notifications v2
// ---------------------------------------------------------------------------
// Both the outer signedPayload and the inner signedTransactionInfo are
// cryptographically verified as Apple-signed (full x5c chain to Apple Root
// CA - G3, leaf OID, bundleId, environment) via the shared verifier. See
// _shared/apple_verify.ts. This endpoint is unauthenticated (Apple posts to
// it), so JWS verification is the ONLY trust boundary — a forged payload must
// never reach the DB write.
// ---------------------------------------------------------------------------

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
    notification = await verifyNotification(signedPayload) as AppleNotificationPayload
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
    txn = await verifyTransaction(data.signedTransactionInfo)
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
    update.trial_started_at = null
  } else if (status === 'trial') {
    update.trial_started_at = new Date(txn.purchaseDate).toISOString()
    update.subscription_expires_at = txn.expiresDate
      ? new Date(txn.expiresDate).toISOString()
      : null
  } else if (txn.expiresDate) {
    update.subscription_expires_at = new Date(txn.expiresDate).toISOString()
  } else {
    update.subscription_expires_at = null
  }

  if (status === 'none' || status === 'expired') {
    if (status === 'none') {
      update.subscription_product_id = null
      update.subscription_started_at = null
      update.original_transaction_id = null
      update.is_lifetime = false
      update.trial_started_at = null
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
