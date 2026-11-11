// Lapsy routing proxy: keeps the OpenRouteService key on the server.
// Deploy:  supabase functions deploy route
// Key:     supabase secrets set ORS_API_KEY=<your key>
// JWT verification stays ON (default), so only signed-in Lapsy users can call it.
import { createClient } from "jsr:@supabase/supabase-js@2";

const PROFILES = new Set([
  "foot-walking", "foot-hiking", "cycling-regular", "cycling-road",
  "cycling-mountain", "cycling-electric", "driving-car", "wheelchair",
]);
const DAILY_LIMIT = 150; // route requests per user per day

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  if (req.method !== "POST") return json(405, { error: { message: "POST only" } });

  const auth = req.headers.get("Authorization") ?? "";
  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: auth } },
  });
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return json(401, { error: { message: "Please sign in again." } });

  const { profile, body } = await req.json().catch(() => ({}));
  if (!PROFILES.has(profile) || typeof body !== "object" || body === null) {
    return json(400, { error: { message: "Bad request" } });
  }

  // Simple per-user daily cap, kept in memory per instance (best effort).
  const day = new Date().toISOString().slice(0, 10);
  const key = `${user.id}:${day}`;
  const used = (counts.get(key) ?? 0) + 1;
  counts.set(key, used);
  if (used > DAILY_LIMIT) return json(429, { error: { message: "Daily route limit reached. Try again tomorrow." } });

  const upstream = await fetch(`https://api.openrouteservice.org/v2/directions/${profile}/geojson`, {
    method: "POST",
    headers: { Authorization: Deno.env.get("ORS_API_KEY")!, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  return new Response(await upstream.text(), {
    status: upstream.status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
});

const counts = new Map<string, number>();
