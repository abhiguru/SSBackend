// Main Edge Function Router
// Routes requests to appropriate function handlers

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
};

Deno.serve(async (req: Request) => {
  // Handle CORS preflight for all routes
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  const url = new URL(req.url);
  const pathname = url.pathname;

  // Remove leading slash and extract function name
  const path = pathname.replace(/^\//, '').replace(/\/$/, '');

  try {
    // Dynamic import based on path
    let handler: (req: Request) => Promise<Response>;

    switch (path) {
      case 'send-otp':
        handler = (await import('../send-otp/index.ts')).handler;
        break;
      case 'verify-otp':
        handler = (await import('../verify-otp/index.ts')).handler;
        break;
      case 'refresh-token':
        handler = (await import('../refresh-token/index.ts')).handler;
        break;
      case 'checkout':
        handler = (await import('../checkout/index.ts')).handler;
        break;
      case 'update-order-status':
        handler = (await import('../update-order-status/index.ts')).handler;
        break;
      case 'verify-delivery-otp':
        handler = (await import('../verify-delivery-otp/index.ts')).handler;
        break;
      case 'mark-delivery-failed':
        handler = (await import('../mark-delivery-failed/index.ts')).handler;
        break;
      case 'reorder':
        handler = (await import('../reorder/index.ts')).handler;
        break;
      case 'health':
      case '':
        return new Response(
          JSON.stringify({
            status: 'ok',
            service: 'masala-functions',
            timestamp: new Date().toISOString(),
            endpoints: [
              'send-otp',
              'verify-otp',
              'refresh-token',
              'checkout',
              'update-order-status',
              'verify-delivery-otp',
              'mark-delivery-failed',
              'reorder',
            ],
          }),
          { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      default:
        return new Response(
          JSON.stringify({ error: 'NOT_FOUND', message: `Unknown endpoint: ${path}` }),
          { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
    }

    const response = await handler(req);

    // Ensure CORS headers are included
    const headers = new Headers(response.headers);
    Object.entries(corsHeaders).forEach(([key, value]) => {
      headers.set(key, value);
    });

    return new Response(response.body, {
      status: response.status,
      statusText: response.statusText,
      headers,
    });
  } catch (error) {
    console.error('Router error:', error);
    return new Response(
      JSON.stringify({ error: 'SERVER_ERROR', message: 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
