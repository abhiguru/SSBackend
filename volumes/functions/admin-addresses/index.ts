// Admin Address Management - CRUD addresses for any user with geocoding
// GET    ?user_id={uuid}          - List addresses for a user
// POST   { user_id, ... }         - Create address (geocodes on save)
// PATCH  { address_id, ... }      - Update address (re-geocodes if address fields change)
// DELETE ?address_id={uuid}       - Delete address

import { requireAdmin, getServiceClient } from "../_shared/auth.ts";
import { jsonResponse, errorResponse, handleError } from "../_shared/response.ts";
import { geocodeAddress } from "../_shared/geocoding.ts";

const ADDRESS_FIELDS = ['address_line1', 'address_line2', 'city', 'state', 'pincode'] as const;

function buildAddressFromFields(addr: {
  address_line1: string;
  address_line2?: string;
  city: string;
  state?: string;
  pincode: string;
}): string {
  return [addr.address_line1, addr.address_line2, addr.city, addr.state, addr.pincode]
    .filter(Boolean)
    .join(', ');
}

export async function handler(req: Request): Promise<Response> {
  try {
    switch (req.method) {
      case 'GET':
        return await handleGet(req);
      case 'POST':
        return await handlePost(req);
      case 'PATCH':
        return await handlePatch(req);
      case 'DELETE':
        return await handleDelete(req);
      default:
        return errorResponse('METHOD_NOT_ALLOWED', 'Use GET, POST, PATCH, or DELETE', 405);
    }
  } catch (error) {
    return handleError(error, 'admin-addresses');
  }
}

async function handleGet(req: Request): Promise<Response> {
  await requireAdmin(req);

  const url = new URL(req.url);
  const userId = url.searchParams.get('user_id');

  if (!userId) {
    return errorResponse('MISSING_USER_ID', 'user_id query parameter is required', 400);
  }

  const supabase = getServiceClient();

  const { data, error } = await supabase
    .from('user_addresses')
    .select('*')
    .eq('user_id', userId)
    .order('is_default', { ascending: false })
    .order('created_at', { ascending: false });

  if (error) {
    console.error('Address list error:', error);
    return errorResponse('QUERY_ERROR', 'Failed to fetch addresses', 500);
  }

  return jsonResponse(data);
}

async function handlePost(req: Request): Promise<Response> {
  await requireAdmin(req);

  const body = await req.json();
  const { user_id, label, full_name, phone, address_line1, address_line2, city, state, pincode, is_default } = body;

  // Validate required fields
  if (!user_id || !full_name || !phone || !address_line1 || !city || !pincode) {
    return errorResponse(
      'MISSING_FIELDS',
      'Required: user_id, full_name, phone, address_line1, city, pincode',
      400,
    );
  }

  const supabase = getServiceClient();

  // Verify user exists
  const { data: user, error: userError } = await supabase
    .from('users')
    .select('id')
    .eq('id', user_id)
    .single();

  if (userError || !user) {
    return errorResponse('USER_NOT_FOUND', 'Target user not found', 404);
  }

  // Geocode address
  const addressString = buildAddressFromFields({ address_line1, address_line2, city, state, pincode });
  let geoResult = { lat: null as number | null, lng: null as number | null, formatted_address: null as string | null };
  try {
    const result = await geocodeAddress(addressString);
    geoResult = { lat: result.lat, lng: result.lng, formatted_address: result.formatted_address ?? null };
  } catch (geoError) {
    console.error('Geocoding failed on create, saving without coordinates:', geoError);
  }

  const insertData: Record<string, unknown> = {
    user_id,
    full_name,
    phone,
    address_line1,
    city,
    pincode,
    lat: geoResult.lat,
    lng: geoResult.lng,
    formatted_address: geoResult.formatted_address,
  };
  if (label !== undefined) insertData.label = label;
  if (address_line2 !== undefined) insertData.address_line2 = address_line2;
  if (state !== undefined) insertData.state = state;
  if (is_default !== undefined) insertData.is_default = is_default;

  const { data, error } = await supabase
    .from('user_addresses')
    .insert(insertData)
    .select()
    .single();

  if (error) {
    console.error('Address insert error:', error);
    return errorResponse('INSERT_ERROR', 'Failed to create address', 500);
  }

  return jsonResponse(data, 201);
}

async function handlePatch(req: Request): Promise<Response> {
  await requireAdmin(req);

  const body = await req.json();
  const { address_id, ...fields } = body;

  if (!address_id) {
    return errorResponse('MISSING_ADDRESS_ID', 'address_id is required', 400);
  }

  const supabase = getServiceClient();

  // Fetch existing address
  const { data: existing, error: fetchError } = await supabase
    .from('user_addresses')
    .select('*')
    .eq('id', address_id)
    .single();

  if (fetchError || !existing) {
    return errorResponse('ADDRESS_NOT_FOUND', 'Address not found', 404);
  }

  // Build update data from allowed fields
  const allowedFields = ['label', 'full_name', 'phone', 'address_line1', 'address_line2', 'city', 'state', 'pincode', 'is_default', 'lat', 'lng', 'formatted_address'];
  const updateData: Record<string, unknown> = {};
  for (const key of allowedFields) {
    if (fields[key] !== undefined) {
      updateData[key] = fields[key];
    }
  }

  if (Object.keys(updateData).length === 0) {
    return errorResponse('NO_CHANGES', 'No fields to update', 400);
  }

  // If frontend supplied lat/lng directly, use those.
  // Otherwise, if address fields changed, re-geocode server-side.
  const frontendSuppliedCoords = fields.lat !== undefined && fields.lng !== undefined;

  if (!frontendSuppliedCoords) {
    const addressFieldChanged = ADDRESS_FIELDS.some(
      (f) => updateData[f] !== undefined && updateData[f] !== existing[f],
    );

    if (addressFieldChanged) {
      const merged = {
        address_line1: (updateData.address_line1 ?? existing.address_line1) as string,
        address_line2: (updateData.address_line2 ?? existing.address_line2) as string | undefined,
        city: (updateData.city ?? existing.city) as string,
        state: (updateData.state ?? existing.state) as string | undefined,
        pincode: (updateData.pincode ?? existing.pincode) as string,
      };

      const addressString = buildAddressFromFields(merged);
      try {
        const result = await geocodeAddress(addressString);
        updateData.lat = result.lat;
        updateData.lng = result.lng;
        updateData.formatted_address = result.formatted_address ?? null;
      } catch (geoError) {
        console.error('Re-geocoding failed on update:', geoError);
        // Keep existing coordinates rather than clearing them
      }
    }
  }

  const { data, error } = await supabase
    .from('user_addresses')
    .update(updateData)
    .eq('id', address_id)
    .select()
    .single();

  if (error) {
    console.error('Address update error:', error);
    return errorResponse('UPDATE_ERROR', 'Failed to update address', 500);
  }

  return jsonResponse(data);
}

async function handleDelete(req: Request): Promise<Response> {
  await requireAdmin(req);

  const url = new URL(req.url);
  const addressId = url.searchParams.get('address_id');

  if (!addressId) {
    return errorResponse('MISSING_ADDRESS_ID', 'address_id query parameter is required', 400);
  }

  const supabase = getServiceClient();

  const { error } = await supabase
    .from('user_addresses')
    .delete()
    .eq('id', addressId);

  if (error) {
    console.error('Address delete error:', error);
    return errorResponse('DELETE_ERROR', 'Failed to delete address', 500);
  }

  return jsonResponse({ success: true });
}
