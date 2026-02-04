// Shared response helpers for edge functions
// PERFORMANCE OPTIMIZED: Item 35 from performance audit

import { corsHeaders } from "./cors.ts";

// =============================================
// ITEM 35: Add Cache-Control Headers to Responses
// =============================================

/** Return a JSON response with CORS headers and optional caching */
export function jsonResponse(
  body: unknown,
  status = 200,
  options?: {
    cacheMaxAge?: number;
    cachePrivate?: boolean;
    etag?: string;
  }
): Response {
  const headers: Record<string, string> = {
    ...corsHeaders,
    'Content-Type': 'application/json',
  };

  // Add Cache-Control header if caching is requested
  if (options?.cacheMaxAge && options.cacheMaxAge > 0) {
    const visibility = options.cachePrivate ? 'private' : 'public';
    headers['Cache-Control'] = `${visibility}, max-age=${options.cacheMaxAge}`;
  } else {
    // Default: no caching for API responses
    headers['Cache-Control'] = 'no-store';
  }

  // Add ETag for conditional requests (Item 36)
  if (options?.etag) {
    headers['ETag'] = `"${options.etag}"`;
  }

  return new Response(JSON.stringify(body), { status, headers });
}

/** Return a cached JSON response (convenience wrapper) */
export function cachedJsonResponse(
  body: unknown,
  maxAgeSeconds: number,
  options?: { isPrivate?: boolean; etag?: string }
): Response {
  return jsonResponse(body, 200, {
    cacheMaxAge: maxAgeSeconds,
    cachePrivate: options?.isPrivate ?? false,
    etag: options?.etag,
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

/** Check If-None-Match header for conditional requests */
export function checkConditionalRequest(
  req: Request,
  currentEtag: string
): Response | null {
  const ifNoneMatch = req.headers.get('If-None-Match');
  if (ifNoneMatch && ifNoneMatch === `"${currentEtag}"`) {
    return new Response(null, {
      status: 304,
      headers: {
        ...corsHeaders,
        'ETag': `"${currentEtag}"`,
      },
    });
  }
  return null;
}

/** Generate a simple ETag from content */
export async function generateEtag(content: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(content);
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  // Use first 16 chars of hash as ETag
  return hashArray.slice(0, 8).map(b => b.toString(16).padStart(2, '0')).join('');
}
