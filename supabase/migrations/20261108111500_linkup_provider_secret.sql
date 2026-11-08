-- Shared server-only Linkup credential, alongside existing providers.
create or replace function public.meetin_provider_secret(p_provider text) returns text
language sql stable security definer set search_path = '' as $$
  with names as (
    select case p_provider
      when 'gladia' then array['gladia_api_key', 'gladia']
      when 'hcompany' then array['hai_api_key', 'hcompany_api_key', 'hcompany']
      when 'devin' then array['devin_api_key', 'devin']
      when 'linkup' then array['linkup_api_key', 'linkup']
    end as allowed
  )
  select s.decrypted_secret from vault.decrypted_secrets s cross join names
    where lower(s.name) = any(names.allowed)
    order by array_position(names.allowed, lower(s.name)), s.updated_at desc limit 1;
$$;

revoke all on function public.meetin_provider_secret(text) from public, anon, authenticated;
grant execute on function public.meetin_provider_secret(text) to service_role;
