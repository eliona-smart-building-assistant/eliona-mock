-- Replaces the random values of a fresh platform init with fixed mock values before the data is dumped.
-- Nothing generated here is a real credential; the mock is for local development only.

UPDATE public.eliona_tenant SET cust_id = 'mock tenant';

-- key 2 has full access, key 1 is read-only
UPDATE public.keyauth_credentials SET key = 'secret', name = 'mock key', ttl = NULL WHERE key_id = 2;
UPDATE public.keyauth_credentials SET key = 'secret-read-only', name = 'mock read-only key' WHERE key_id = 1;

UPDATE public.eliona_secret SET secret = 'mock-secret-' || schema;

UPDATE public.eliona_user
SET
    email    = 'mock-user-' || user_id || '@example.com',
    password = NULL;
