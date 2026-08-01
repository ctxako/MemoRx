import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const env = (k: string): string => {
  const v = (Deno.env.get(k) ?? "").trim()
  if (!v) throw new Error(`Missing required secret: ${k}`)
  return v
}

const KEY_ID = env("ASC_KEY_ID")
const ISSUER_ID = env("ASC_ISSUER_ID")
const VENDOR = env("ASC_VENDOR")
const PRIVATE_KEY_B64 = env("ASC_PRIVATE_KEY_B64")

const APP_ID_MAP: Record<string, string> = {
  "6761398713": "MemoRx",
  "6780775028": "Urge Surfing",
  "6761387344": "Clockd",
}
const APP_ORDER = Object.values(APP_ID_MAP)

async function generateJWT(): Promise<string> {
  const keyBytes = Uint8Array.from(atob(PRIVATE_KEY_B64), (c) => c.charCodeAt(0))
  const privateKey = await crypto.subtle.importKey(
    "pkcs8",
    keyBytes,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"]
  )
  const now = Math.floor(Date.now() / 1000)
  const toB64url = (s: string) =>
    btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "")
  const header = toB64url(JSON.stringify({ alg: "ES256", kid: KEY_ID }))
  const payload = toB64url(JSON.stringify({
    iss: ISSUER_ID, iat: now, exp: now + 1200, aud: "appstoreconnect-v1"
  }))
  const message = `${header}.${payload}`
  const sig = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    privateKey,
    new TextEncoder().encode(message)
  )
  const sigB64 = btoa(String.fromCharCode(...new Uint8Array(sig)))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "")
  return `${message}.${sigB64}`
}

async function fetchForDate(token: string, dateStr: string): Promise<string | null> {
  const url = new URL("https://api.appstoreconnect.apple.com/v1/salesReports")
  url.searchParams.set("filter[frequency]", "DAILY")
  url.searchParams.set("filter[reportType]", "SALES")
  url.searchParams.set("filter[reportSubType]", "SUMMARY")
  url.searchParams.set("filter[vendorNumber]", VENDOR)
  url.searchParams.set("filter[reportDate]", dateStr)
  const res = await fetch(url.toString(), {
    headers: { Authorization: `Bearer ${token}` }
  })
  if (res.status === 404) return null
  if (!res.ok) throw new Error(`ASC ${res.status}: ${await res.text()}`)
  const ds = new DecompressionStream("gzip")
  const chunks: Uint8Array[] = []
  const reader = res.body!.pipeThrough(ds).getReader()
  while (true) {
    const { done, value } = await reader.read()
    if (done) break
    chunks.push(value)
  }
  const total = chunks.reduce((n, c) => n + c.length, 0)
  const buf = new Uint8Array(total)
  let off = 0
  for (const c of chunks) { buf.set(c, off); off += c.length }
  return new TextDecoder().decode(buf)
}

function parseInstalls(tsv: string): { installs: Record<string, number>; diagnostic: string[] } {
  const installs: Record<string, number> = Object.fromEntries(APP_ORDER.map(a => [a, 0]))
  const diagnostic: string[] = []
  const lines = tsv.trim().split("\n")
  const headers = lines[0].split("\t")
  const appleIdIdx = headers.indexOf("Apple Identifier")
  const titleIdx = headers.indexOf("Title")
  const unitsIdx = headers.indexOf("Units")
  const typeIdx = headers.indexOf("Product Type Identifier")
  for (let i = 1; i < lines.length; i++) {
    const cols = lines[i].split("\t")
    if (!cols[typeIdx]?.startsWith("1")) continue
    const appleId = cols[appleIdIdx]
    const appName = APP_ID_MAP[appleId]
    if (appName) {
      installs[appName] += parseInt(cols[unitsIdx] || "0", 10)
    } else {
      diagnostic.push(`Apple Identifier=${appleId} Title="${cols[titleIdx]}" Units=${cols[unitsIdx]}`)
    }
  }
  return { installs, diagnostic }
}

Deno.serve(async (req) => {
  try {
    const token = await generateJWT()
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    )

    // Get list of dates already in DB (last 30 days)
    const { data: existing } = await supabase
      .from("asc_daily_stats")
      .select("report_date")
      .gte("report_date", (() => { const d = new Date(); d.setDate(d.getDate() - 30); return d.toISOString().split("T")[0] })())
    const existingDates = new Set((existing ?? []).map((r: { report_date: string }) => r.report_date))

    // Walk back up to 20 days, stop at first missing date that has ASC data
    for (let daysBack = 1; daysBack <= 20; daysBack++) {
      const d = new Date()
      d.setDate(d.getDate() - daysBack)
      const dateStr = d.toISOString().split("T")[0]

      if (existingDates.has(dateStr)) continue

      const tsv = await fetchForDate(token, dateStr)
      if (tsv === null) continue  // no sales that day, keep walking back

      const { installs, diagnostic } = parseInstalls(tsv)
      const { error } = await supabase.from("asc_daily_stats").upsert(
        APP_ORDER.map(app => ({
          report_date: dateStr,
          app_name: app,
          installs: installs[app],
          fetched_at: new Date().toISOString()
        })),
        { onConflict: "report_date,app_name" }
      )
      if (error) throw error

      return new Response(JSON.stringify({ success: true, date: dateStr, installs, diagnostic }), {
        headers: { "Content-Type": "application/json" }
      })
    }

    return new Response(JSON.stringify({ success: true, message: "No new ASC data found in last 20 days" }), {
      headers: { "Content-Type": "application/json" }
    })
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { "Content-Type": "application/json" }
    })
  }
})
