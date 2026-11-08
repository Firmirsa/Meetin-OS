-- One permitted demo publication per explicitly configured user. No browser cookies stored here.
create table meetin_private.youtube_demo_claims (
  user_id uuid primary key references auth.users on delete cascade,
  proposal_id uuid not null,
  session_id uuid,
  created_at timestamptz not null default now()
);
revoke all on meetin_private.youtube_demo_claims from public, anon, authenticated;
create function public.meetin_claim_youtube_demo(p_user uuid, p_proposal uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare inserted integer; sid uuid;
begin
  insert into meetin_private.youtube_demo_claims(user_id, proposal_id) values(p_user,p_proposal)
    on conflict(user_id) do nothing;
  get diagnostics inserted = row_count;
  select session_id into sid from meetin_private.youtube_demo_claims where user_id=p_user;
  return jsonb_build_object('claimed', inserted=1, 'session_id', sid);
end;
$$;
create function public.meetin_save_youtube_session(p_user uuid, p_proposal uuid, p_session uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  update meetin_private.youtube_demo_claims set session_id=p_session
    where user_id=p_user and proposal_id=p_proposal and session_id is null;
  if not found then raise exception 'Unexpected demo claim'; end if;
end;
$$;
revoke all on function public.meetin_claim_youtube_demo(uuid,uuid) from public, anon, authenticated;
revoke all on function public.meetin_save_youtube_session(uuid,uuid,uuid) from public, anon, authenticated;
grant execute on function public.meetin_claim_youtube_demo(uuid,uuid) to service_role;
grant execute on function public.meetin_save_youtube_session(uuid,uuid,uuid) to service_role;
