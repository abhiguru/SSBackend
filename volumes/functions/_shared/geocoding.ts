// Google Geocoding API Helper
// Converts addresses to coordinates for Porter delivery

export interface GeocodingResult {
  lat: number;
  lng: number;
  formatted_address?: string;
}

export interface GeocodingError {
  error: string;
  status: string;
}

/**
 * Geocode an address to coordinates using Google Geocoding API
 */
export async function geocodeAddress(address: string): Promise<GeocodingResult> {
  const apiKey = Deno.env.get('GOOGLE_GEOCODING_API_KEY');

  if (!apiKey) {
    console.warn('GOOGLE_GEOCODING_API_KEY not configured, using fallback');
    return fallbackGeocode(address);
  }

  try {
    // Append India to improve accuracy for local addresses
    const fullAddress = address.includes('India') ? address : `${address}, India`;
    const encodedAddress = encodeURIComponent(fullAddress);

    const url = `https://maps.googleapis.com/maps/api/geocode/json?address=${encodedAddress}&key=${apiKey}&region=in&components=country:IN`;

    const response = await fetch(url);

    if (!response.ok) {
      throw new Error(`Geocoding API error: ${response.status}`);
    }

    const data = await response.json();

    if (data.status !== 'OK' || !data.results || data.results.length === 0) {
      console.error('Geocoding failed:', data.status, data.error_message);
      throw new Error(`Geocoding failed: ${data.status}`);
    }

    const location = data.results[0].geometry.location;

    return {
      lat: location.lat,
      lng: location.lng,
      formatted_address: data.results[0].formatted_address,
    };
  } catch (error) {
    console.error('Geocoding error:', error);
    // Fall back to approximate geocoding
    return fallbackGeocode(address);
  }
}

/**
 * Build a full address string from order shipping details
 */
export function buildAddressString(order: {
  shipping_address_line1: string;
  shipping_address_line2?: string;
  shipping_city: string;
  shipping_state: string;
  shipping_pincode: string;
}): string {
  const parts = [
    order.shipping_address_line1,
    order.shipping_address_line2,
    order.shipping_city,
    order.shipping_state,
    order.shipping_pincode,
  ].filter(Boolean);

  return parts.join(', ');
}

/**
 * Fallback geocoding using pincode centroids
 * This provides approximate coordinates when Google API is unavailable
 */
function fallbackGeocode(address: string): GeocodingResult {
  // Extract pincode from address
  const pincodeMatch = address.match(/\b\d{6}\b/);
  const pincode = pincodeMatch ? pincodeMatch[0] : null;

  // Known pincode centroids for Ahmedabad area
  const pincodeCoords: Record<string, { lat: number; lng: number }> = {
    '380001': { lat: 23.0225, lng: 72.5714 }, // Ahmedabad Central
    '380002': { lat: 23.0288, lng: 72.5868 },
    '380003': { lat: 23.0364, lng: 72.5566 },
    '380004': { lat: 23.0423, lng: 72.5454 },
    '380005': { lat: 23.0512, lng: 72.5321 },
    '380006': { lat: 23.0134, lng: 72.5612 },
    '380007': { lat: 23.0078, lng: 72.5876 },
    '380008': { lat: 22.9987, lng: 72.5534 },
    '380009': { lat: 23.0145, lng: 72.5234 },
    '380010': { lat: 23.0267, lng: 72.5098 },
    '380013': { lat: 23.0339, lng: 72.5614 }, // Usmanpura (Store location)
    '380015': { lat: 23.0512, lng: 72.5456 },
    '380016': { lat: 23.0634, lng: 72.5312 },
    '360001': { lat: 22.3039, lng: 70.8022 }, // Rajkot
    '360002': { lat: 22.2987, lng: 70.7856 },
    '360003': { lat: 22.3123, lng: 70.7934 },
    '360004': { lat: 22.2845, lng: 70.8134 },
    '360005': { lat: 22.3201, lng: 70.8212 },
  };

  if (pincode && pincodeCoords[pincode]) {
    console.log(`Using fallback coordinates for pincode ${pincode}`);
    return {
      ...pincodeCoords[pincode],
      formatted_address: address,
    };
  }

  // Default to Ahmedabad center if no pincode match
  console.warn('No pincode match, using Ahmedabad center coordinates');
  return {
    lat: 23.0225,
    lng: 72.5714,
    formatted_address: address,
  };
}

/**
 * Validate coordinates are within reasonable bounds for India
 */
export function validateCoordinates(lat: number, lng: number): boolean {
  // India bounds (approximate)
  const indiaBounds = {
    minLat: 6.5,
    maxLat: 35.5,
    minLng: 68.0,
    maxLng: 97.5,
  };

  return (
    lat >= indiaBounds.minLat &&
    lat <= indiaBounds.maxLat &&
    lng >= indiaBounds.minLng &&
    lng <= indiaBounds.maxLng
  );
}

/**
 * Calculate straight-line distance between two points (km)
 */
export function calculateDistance(
  lat1: number,
  lng1: number,
  lat2: number,
  lng2: number
): number {
  const R = 6371; // Earth's radius in km
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
    Math.sin(dLng / 2) * Math.sin(dLng / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

function toRad(deg: number): number {
  return deg * (Math.PI / 180);
}
