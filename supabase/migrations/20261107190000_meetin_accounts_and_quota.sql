create schema if not exists meetin_private;
revoke all on schema meetin_private from public, anon, authenticated;

create table meetin_private.quota_plans (
  code text primary key check (code in ('free', 'premium')),
  monthly_ms bigint not null check (monthly_ms > 0)
);

insert into meetin_private.quota_plans (code, monthly_ms)
values ('free', 15 * 60 * 1000), ('premium', 300 * 60 * 1000);

create table meetin_private.stripe_subscriptions (
  id text primary key,
  user_id uuid not null references auth.users on delete cascade,
  customer_id text not null,
  premium_until timestamptz,
  event_time bigint not null,
  observed_at timestamptz not null
);
create index meetin_stripe_user on meetin_private.stripe_subscriptions (user_id);

create table meetin_private.audio_months (
  user_id uuid not null references auth.users on delete cascade,
  month_start date not null,
  used_ms bigint not null check (used_ms >= 0),
  primary key (user_id, month_start)
);

create table meetin_private.audio_reservations (
  id uuid primary key,
  user_id uuid not null,
  month_start date not null,
  reserved_ms integer not null check (reserved_ms > 0),
  spent_ms integer check (spent_ms between 0 and reserved_ms),
  kind text not null check (kind in ('batch', 'live')),
  fingerprint text,
  provider_job uuid,
  created_at timestamptz not null default now(),
  foreign key (user_id, month_start) references meetin_private.audio_months on delete cascade
);
create index meetin_reservation_user on meetin_private.audio_reservations (user_id, month_start);

create function public.meetin_account_quota(p_user uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  with period as (
    select date_trunc('month', now() at time zone 'UTC')::date as starts
  ), entitlement as (
    select case when exists (
      select 1 from meetin_private.stripe_subscriptions where user_id = p_user and premium_until > now()
    ) then 'premium' else 'free' end as plan
  )
  select jsonb_build_object(
    'plan', q.code,
    'limitMs', q.monthly_ms,
    'usedMs', coalesce(m.used_ms, 0),
    'remainingMs', greatest(0, q.monthly_ms - coalesce(m.used_ms, 0)),
    'resetsAt', (period.starts + interval '1 month') at time zone 'UTC',
    'customerId', (
      select customer_id from meetin_private.stripe_subscriptions
      where user_id = p_user order by (premium_until > now()) desc nulls last, observed_at desc limit 1
    )
  )
  from period cross join entitlement
  join meetin_private.quota_plans q on q.code = entitlement.plan
  left join meetin_private.audio_months m on m.user_id = p_user and m.month_start = period.starts;
$$;

create function public.meetin_reserve_audio(p_user uuid, p_id uuid, p_ms integer, p_kind text, p_fingerprint text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  bucket date := date_trunc('month', now() at time zone 'UTC')::date;
  available_ms bigint;
  allocated_ms integer;
  previous meetin_private.audio_reservations%rowtype;
begin
  if p_ms is null or p_ms <= 0 or p_kind is null or p_kind not in ('batch', 'live')
    or (p_kind = 'batch' and (p_ms > 90000 or p_fingerprint is null or p_fingerprint !~ '^[a-f0-9]{64}$'))
    or (p_kind = 'live' and (p_ms > 10000 or p_fingerprint is not null)) then
    raise exception 'invalid audio reservation';
  end if;

  -- Serializes allocations and refunds for the same account across all server instances.
  perform pg_advisory_xact_lock(hashtextextended(p_user::text, 4198));
  select * into previous from meetin_private.audio_reservations where id = p_id;
  if found then
    if previous.user_id <> p_user or previous.kind <> p_kind
      or previous.fingerprint is distinct from p_fingerprint then
      return jsonb_build_object('status', 'conflict');
    end if;
    return jsonb_build_object('status', 'existing', 'reservedMs', previous.reserved_ms);
  end if;

  available_ms := (public.meetin_account_quota(p_user)->>'remainingMs')::bigint;
  if available_ms = 0 or (p_kind = 'batch' and available_ms < p_ms) then
    return jsonb_build_object('status', 'quota');
  end if;
  allocated_ms := least(available_ms, p_ms);

  insert into meetin_private.audio_months as m (user_id, month_start, used_ms)
    values (p_user, bucket, allocated_ms)
    on conflict (user_id, month_start) do update set used_ms = m.used_ms + excluded.used_ms;
  insert into meetin_private.audio_reservations (id, user_id, month_start, reserved_ms, kind, fingerprint)
    values (p_id, p_user, bucket, allocated_ms, p_kind, p_fingerprint);
  return jsonb_build_object('status', 'reserved', 'reservedMs', allocated_ms);
end;
$$;

create function public.meetin_finish_audio(p_user uuid, p_id uuid, p_ms integer, p_job uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  reservation meetin_private.audio_reservations%rowtype;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_user::text, 4198));
  select * into reservation from meetin_private.audio_reservations where id = p_id and user_id = p_user;
  if not found or reservation.spent_ms is not null then return; end if;
  if p_ms is null or p_ms < 0 or p_ms > reservation.reserved_ms then
    raise exception 'invalid audio consumption';
  end if;
  update meetin_private.audio_reservations set spent_ms = p_ms, provider_job = p_job where id = p_id;
  update meetin_private.audio_months
    set used_ms = used_ms - (reservation.reserved_ms - p_ms)
    where user_id = p_user and month_start = reservation.month_start;
end;
$$;

create function public.meetin_audio_job(p_user uuid, p_id uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'job', provider_job,
    'starting', spent_ms is null and created_at > now() - interval '2 minutes'
  ) from meetin_private.audio_reservations where id = p_id and user_id = p_user and kind = 'batch';
$$;

create function public.meetin_sync_subscription(
  p_id text, p_user uuid, p_customer text, p_premium_until timestamptz, p_event_time bigint, p_observed_at timestamptz
) returns void language sql security definer set search_path = '' as $$
  insert into meetin_private.stripe_subscriptions as s (id, user_id, customer_id, premium_until, event_time, observed_at)
    select p_id, p_user, p_customer, p_premium_until, p_event_time, p_observed_at
    where exists (select 1 from auth.users where id = p_user)
    on conflict (id) do update
      set premium_until = excluded.premium_until, event_time = excluded.event_time, observed_at = excluded.observed_at
      where s.user_id = excluded.user_id and s.customer_id = excluded.customer_id
        and (s.event_time, s.observed_at) < (excluded.event_time, excluded.observed_at);
$$;

create function public.meetin_provider_secret(p_provider text) returns text
language sql stable security definer set search_path = '' as $$
  with names as (
    select case p_provider
      when 'gladia' then array['gladia_api_key', 'gladia']
      when 'hcompany' then array['hai_api_key', 'hcompany_api_key', 'hcompany']
      when 'devin' then array['devin_api_key', 'devin']
    end as allowed
  )
  select s.decrypted_secret from vault.decrypted_secrets s cross join names
    where lower(s.name) = any(names.allowed)
    order by array_position(names.allowed, lower(s.name)), s.updated_at desc limit 1;
$$;

revoke all on function public.meetin_account_quota(uuid),
  public.meetin_reserve_audio(uuid, uuid, integer, text, text), public.meetin_finish_audio(uuid, uuid, integer, uuid),
  public.meetin_audio_job(uuid, uuid), public.meetin_sync_subscription(text, uuid, text, timestamptz, bigint, timestamptz),
  public.meetin_provider_secret(text) from public, anon, authenticated;

grant execute on function public.meetin_account_quota(uuid),
  public.meetin_reserve_audio(uuid, uuid, integer, text, text), public.meetin_finish_audio(uuid, uuid, integer, uuid),
  public.meetin_audio_job(uuid, uuid), public.meetin_sync_subscription(text, uuid, text, timestamptz, bigint, timestamptz),
  public.meetin_provider_secret(text) to service_role;
