// Supabase Edge Function: delivers a push to a user's devices over APNs.
//
// Deploy:
//   supabase functions deploy send-push
//   supabase secrets set APNS_KEY_ID=... APNS_TEAM_ID=... APNS_BUNDLE_ID=com.pinpop.app
//   supabase secrets set APNS_PRIVATE_KEY="$(cat AuthKey_XXXX.p8)"
//
// APNs is called directly with a signed JWT rather than through a third party,
// so there is no extra vendor holding the device tokens.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { create as createJwt, getNumericDate } from 'https://deno.land/x/djwt@v3.0.2/mod.ts';

interface PushRequest {
  /** Who should receive it. */
  user_id: string;
  title: string;
  body: string;
  /** Merged into the APNs payload for deep linking. */
  data?: Record<string, string>;
}

const APNS_HOST = Deno.env.get('APNS_SANDBOX') === 'true'
  ? 'https://api.sandbox.push.apple.com'
  : 'https://api.push.apple.com';

/**
 * APNs provider tokens are valid for up to an hour, so one is reused across
 * invocations of a warm instance instead of re-signing per notification.
 */
let cachedToken: { jwt: string; expiresAt: number } | null = null;

async function providerToken() {
  const now = Date.now();
  if (cachedToken && cachedToken.expiresAt > now + 60_000) return cachedToken.jwt;

  const keyId = Deno.env.get('APNS_KEY_ID');
  const teamId = Deno.env.get('APNS_TEAM_ID');
  const pem = Deno.env.get('APNS_PRIVATE_KEY');
  if (!keyId || !teamId || !pem) throw new Error('APNs secrets are not configured');

  const der = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s+/g, '');
  const bytes = Uint8Array.from(atob(der), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    'pkcs8',
    bytes,
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign'],
  );

  const jwt = await createJwt(
    { alg: 'ES256', kid: keyId },
    { iss: teamId, iat: getNumericDate(0) },
    key,
  );
  cachedToken = { jwt, expiresAt: now + 45 * 60_000 };
  return jwt;
}

Deno.serve(async (request) => {
  if (request.method !== 'POST') return new Response('Method not allowed', { status: 405 });

  // Only trusted callers: the DB trigger and other functions send the service key.
  const auth = request.headers.get('Authorization') ?? '';
  if (auth !== `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`) {
    return new Response('Unauthorized', { status: 401 });
  }

  let payload: PushRequest;
  try {
    payload = await request.json();
  } catch {
    return new Response('Bad request', { status: 400 });
  }
  if (!payload.user_id || !payload.title) {
    return new Response('user_id and title are required', { status: 400 });
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  const { data: tokens, error } = await supabase
    .from('push_tokens')
    .select('token')
    .eq('user_id', payload.user_id)
    .eq('platform', 'ios');
  if (error) return new Response(error.message, { status: 500 });
  if (!tokens?.length) return Response.json({ sent: 0 });

  const jwt = await providerToken();
  const bundleId = Deno.env.get('APNS_BUNDLE_ID') ?? 'com.pinpop.app';

  const results = await Promise.all(
    tokens.map(async ({ token }) => {
      const response = await fetch(`${APNS_HOST}/3/device/${token}`, {
        method: 'POST',
        headers: {
          authorization: `bearer ${jwt}`,
          'apns-topic': bundleId,
          'apns-push-type': 'alert',
        },
        body: JSON.stringify({
          aps: {
            alert: { title: payload.title, body: payload.body },
            sound: 'default',
          },
          ...payload.data,
        }),
      });

      // 410 means the device unregistered; drop the row so it is not retried.
      if (response.status === 410) {
        await supabase.from('push_tokens').delete().eq('token', token);
      }
      return response.status;
    }),
  );

  return Response.json({
    sent: results.filter((status) => status === 200).length,
    statuses: results,
  });
});
