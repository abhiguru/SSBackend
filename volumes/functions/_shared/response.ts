// Shared response helpers for edge functions

import { corsHeaders } from "./cors.ts";

/** Return a JSON response with CORS headers */
export function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

/** Return a structured error response */
export function errorResponse(
  error: string,
  message: string,
  status: number,
  extra?: Record<string, unknown>,
): Response {
  return jsonResponse({ error, message, ...extra }, status);
}

/** Handle caught errors uniformly (AuthError-aware) */
export function handleError(error: unknown, context: string): Response {
  if (error instanceof Error && error.name === 'AuthError') {
    const status = (error as Error & { status?: number }).status || 401;
    return errorResponse('UNAUTHORIZED', error.message, status);
  }

  console.error(`${context} error:`, error);
  return errorResponse('SERVER_ERROR', 'An unexpected error occurred', 500);
}
