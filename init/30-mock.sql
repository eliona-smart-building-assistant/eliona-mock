-- Adjustments the mock needs on top of the generated schema.

-- calculator-mock upserts heap ON CONFLICT (asset_id, subtype); asset_id is unique, so this adds no new constraint.
CREATE UNIQUE INDEX IF NOT EXISTS heap_asset_id_subtype_mock ON public.heap (asset_id, subtype);
