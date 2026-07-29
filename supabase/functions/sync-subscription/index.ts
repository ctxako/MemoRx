import { createClient } from 'jsr:@supabase/supabase-js@2'
import { verifyTransaction, AppleTransactionInfo } from '../_shared/apple_verify.ts'

// ---------------------------------------------------------------------------
// sync-subscription — Hardened with Apple JWS verification
// ---------------------------------------------------------------------------
// The client provides a signedTransactionInfo JWS from StoreKit 2 instead of
// self-reporting subscription status. The server cryptographically verifies
// the JWS was signed by Apple — full x5c chain to Apple Root CA - G3, leaf
// OID, bundleId, environment — via the shared verifier before trusting any
// subscription data. See _shared/apple_verify.ts.
// ---------------------------------------------------------------------------

// Product-ID mapping: App Store Connect IDs -> DB IDs
const PRODUCT_MAP: Record<string, string> = {
  'ctxa.MemoRx.monthly':  'memorx_monthly',
  'ctxa.MemoRx.yearly':   'memorx_annual',
  'ctxa.MemoRx.lifetime': 'memorx_lifetime',
  'memorx_monthly':       'memorx_monthly',
  'memorx_annual':        'memorx_annual',
  'memorx_lifetime':      'memorx_lifetime',
}

const ALLOWED_PRODUCTS = new Set(['memorx_monthly', 'memorx_annual', 'memorx_lifetime'])
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

// ---------------------------------------------------------------------------
// Main handler
// ---------------------------------------------------------------------------

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405)
  }

  // --- Auth: verify JWT via Supabase Auth ---
  const authHeader = req.headers.get('Authorization') ?? ''
  const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null
  if (!token) {
    return json({ error: 'Missing Authorization header' }, 401)
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

  const authClient = createClient(supabaseUrl, anonKey, {
    auth: { persistSession: false },
  })
  const { data: { user }, error: authError } = await authClient.auth.getUser(token)
  if (authError || !user) {
    return json({ error: 'Invalid or expired token' }, 401)
  }
  const jwtUserId = user.id

  // --- Parse body ---
  let body: Record<string, unknown>
  try {
    body = await req.json()
  } catch {
    return json({ error: 'Invalid JSON body' }, 400)
  }

  const { user_id } = body as { user_id?: string }

  // --- Ownership check ---
  if (!user_id || user_id !== jwtUserId) {
    return json({ error: 'user_id does not match authenticated user' }, 401)
  }

  // --- Handle "clear" case: client has no active entitlements ---
  if (body.clear === true) {
    const adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    })

    // NOTE: do NOT touch is_lifetime here. is_lifetime is an admin/owner-granted
    // comp (or a real lifetime purchase) and must survive cold launches where
    // StoreKit reports no active entitlement (the normal state for a comped user
    // who never purchased). This clear path only resets StoreKit-derived
    // subscription_* fields. A genuine lifetime refund/revoke is handled via a
    // signed REFUND/REVOKE transaction, not this client "clear" call.
    const { error: dbError } = await adminClient
      .from('users')
      .update({
        subscription_status: 'none',
        subscription_product_id: null,
        subscription_expires_at: null,
        subscription_started_at: null,
        original_transaction_id: null,
      })
      .eq('id', user_id)

    if (dbError) {
      console.error('sync-subscription clear DB error:', dbError)
      return json({ error: 'Database error', detail: dbError.message }, 500)
    }

    return json({ ok: true, status: 'none' })
  }

  // --- Require signedTransactionInfo for all non-clear requests ---
  const signedTransactionInfo = body.signed_transaction_info as string | undefined
  if (!signedTransactionInfo) {
    return json(
      { error: 'Missing signed_transaction_info. Provide a StoreKit 2 JWS string or set clear=true.' },
      400
    )
  }

  // --- Verify the JWS against Apple's certificate chain ---
  let txn: AppleTransactionInfo
  try {
    txn = await verifyTransaction(signedTransactionInfo)
  } catch (err) {
    console.error('sync-subscription JWS verification failed:', err)
    return json({ error: 'JWS verification failed. Provide a valid Apple-signed transaction.' }, 403)
  }

  // --- Verify ownership: appAccountToken must match authenticated user ---
  if (txn.appAccountToken && txn.appAccountToken !== jwtUserId) {
    return json(
      { error: 'Transaction appAccountToken does not match authenticated user' },
      403
    )
  }

  // --- Map product ID ---
  const dbProductId = PRODUCT_MAP[txn.productId] ?? txn.productId
  if (!ALLOWED_PRODUCTS.has(dbProductId)) {
    return json(
      { error: `Unknown product: ${txn.productId}` },
      400
    )
  }

  const isLifetime = LIFETIME_PRODUCTS.has(dbProductId)

  // --- Derive subscription_status from verified transaction ---
  // Order: lifetime → revocation → expired → trial → active
  let subscriptionStatus: string

  if (isLifetime) {
    subscriptionStatus = 'lifetime'
  } else if (txn.revocationDate) {
    subscriptionStatus = 'none'
  } else if (txn.expiresDate && txn.expiresDate <= Date.now()) {
    subscriptionStatus = 'expired'
  } else if (txn.offerType === 1) {
    subscriptionStatus = 'trial'
  } else if (txn.expiresDate && txn.expiresDate > Date.now()) {
    subscriptionStatus = 'active'
  } else {
    subscriptionStatus = 'active'
  }

  // --- Build update ---
  const update: Record<string, unknown> = {
    subscription_status: subscriptionStatus,
    subscription_product_id: dbProductId,
    original_transaction_id: txn.originalTransactionId,
    subscription_started_at: new Date(txn.purchaseDate).toISOString(),
  }

  if (isLifetime) {
    update.is_lifetime = true
    update.subscription_expires_at = null
    update.trial_started_at = null
  } else if (subscriptionStatus === 'trial') {
    update.trial_started_at = new Date(txn.purchaseDate).toISOString()
    update.subscription_expires_at = txn.expiresDate
      ? new Date(txn.expiresDate).toISOString()
      : null
  } else if (txn.expiresDate) {
    update.subscription_expires_at = new Date(txn.expiresDate).toISOString()
  } else {
    update.subscription_expires_at = null
  }

  if (subscriptionStatus === 'none') {
    update.subscription_product_id = null
    update.subscription_started_at = null
    update.original_transaction_id = null
    update.subscription_expires_at = null
    update.trial_started_at = null
    if (isLifetime) {
      update.is_lifetime = false
    }
  }

  // --- Write with service_role ---
  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  })

  const { error: dbError } = await adminClient
    .from('users')
    .update(update)
    .eq('id', user_id)

  if (dbError) {
    console.error('sync-subscription DB error:', dbError)
    return json({ error: 'Database error', detail: dbError.message }, 500)
  }

  return json({
    ok: true,
    status: subscriptionStatus,
    product: dbProductId,
    expires_at: update.subscription_expires_at ?? null,
  })
})
