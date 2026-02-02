// Main Edge Function Router
// Routes requests to appropriate function handlers

import { corsHeaders } from "../_shared/cors.ts";
import { jsonResponse, errorResponse } from "../_shared/response.ts";

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
      case 'cleanup':
        handler = (await import('../cleanup/index.ts')).handler;
        break;
      case 'delivery-staff':
        handler = (await import('../delivery-staff/index.ts')).handler;
        break;
      case 'users':
        handler = (await import('../users/index.ts')).handler;
        break;
      case 'admin-addresses':
        handler = (await import('../admin-addresses/index.ts')).handler;
        break;
      case 'update-order-items':
        handler = (await import('../update-order-items/index.ts')).handler;
        break;
      case 'request-account-deletion':
        handler = (await import('../request-account-deletion/index.ts')).handler;
        break;
      case 'process-account-deletion':
        handler = (await import('../process-account-deletion/index.ts')).handler;
        break;
      case 'register-push-token':
        handler = (await import('../register-push-token/index.ts')).handler;
        break;
      case 'health':
      case '':
        return jsonResponse({
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
            'cleanup',
            'delivery-staff',
            'users',
            'admin-addresses',
            'update-order-items',
            'request-account-deletion',
            'process-account-deletion',
            'register-push-token',
          ],
        });
      default:
        return errorResponse('NOT_FOUND', `Unknown endpoint: ${path}`, 404);
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
    return errorResponse('SERVER_ERROR', 'Internal server error', 500);
  }
});
