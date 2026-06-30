import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

function env(k: string): string {
  const v = Deno.env.get(k)
  if (!v) throw new Error(`Missing required secret: ${k}`)
  return v
}

const KB_SECRET = env('KB_SECRET')

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
)

const cors = {
  'Content-Type': 'application/json',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'content-type, x-kb-key',
  'Access-Control-Allow-Methods': 'GET, POST, DELETE, PATCH, OPTIONS',
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: cors })

  if (req.headers.get('x-kb-key') !== KB_SECRET) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401, headers: cors })
  }

  const url = new URL(req.url)
  // path after /functions/v1/kb
  const path = url.pathname.replace(/^\/functions\/v1\/kb/, '') || '/'
  const method = req.method

  try {
    // GET /nodes
    if (path === '/nodes' && method === 'GET') {
      const { data, error } = await supabase
        .from('kb_nodes')
        .select('*')
        .order('created_at', { ascending: true })
      if (error) throw error
      return new Response(JSON.stringify(data), { headers: cors })
    }

    // GET /edges
    if (path === '/edges' && method === 'GET') {
      const { data, error } = await supabase.from('kb_edges').select('*')
      if (error) throw error
      return new Response(JSON.stringify(data), { headers: cors })
    }

    // POST /nodes — upsert by id
    if (path === '/nodes' && method === 'POST') {
      const body = await req.json()
      const { data, error } = await supabase
        .from('kb_nodes')
        .upsert(body, { onConflict: 'id' })
        .select()
      if (error) throw error
      return new Response(JSON.stringify(data), { headers: cors })
    }

    // POST /edges
    if (path === '/edges' && method === 'POST') {
      const body = await req.json()
      const { data, error } = await supabase
        .from('kb_edges')
        .insert(body)
        .select()
      if (error) throw error
      return new Response(JSON.stringify(data), { headers: cors })
    }

    // DELETE /nodes/:id
    if (path.startsWith('/nodes/') && method === 'DELETE') {
      const id = path.replace('/nodes/', '')
      const { error } = await supabase.from('kb_nodes').delete().eq('id', id)
      if (error) throw error
      return new Response(JSON.stringify({ deleted: id }), { headers: cors })
    }

    // DELETE /edges/:id
    if (path.startsWith('/edges/') && method === 'DELETE') {
      const id = path.replace('/edges/', '')
      const { error } = await supabase.from('kb_edges').delete().eq('id', id)
      if (error) throw error
      return new Response(JSON.stringify({ deleted: id }), { headers: cors })
    }

    return new Response(JSON.stringify({ error: 'Not found' }), { status: 404, headers: cors })

  } catch (e: any) {
    return new Response(JSON.stringify({ error: e.message }), { status: 500, headers: cors })
  }
})
