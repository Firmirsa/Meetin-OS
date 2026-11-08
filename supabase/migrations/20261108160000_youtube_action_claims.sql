-- One H session per confirmed YouTube comment proposal (replaces the single lifetime demo claim).
-- No browser cookies stored here.
create table meetin_private.youtube_action_claims (
  proposal_id uuid primary key,
  user_id uuid not null references auth.users on delete cascade,
  session_id uuid,
  created_at timestamptz not null default now()
);
revoke all on meetin_private.youtube_action_claims from public, anon, authenticated;

create function public.meetin_claim_youtube_action(p_user uuid, p_proposal uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare inserted integer; sid uuid; holder uuid;
begin
  insert into meetin_private.youtube_action_claims(proposal_id, user_id) values(p_proposal, p_user)
    on conflict(proposal_id) do nothing;
  get diagnostics inserted = row_count;
  select session_id, user_id into sid, holder from meetin_private.youtube_action_claims where proposal_id = p_proposal;
  if holder <> p_user then return jsonb_build_object('claimed', false, 'session_id', null); end if;
  return jsonb_build_object('claimed', inserted = 1, 'session_id', sid);
end;
$$;

create function public.meetin_save_youtube_action_session(p_user uuid, p_proposal uuid, p_session uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  update meetin_private.youtube_action_claims set session_id = p_session
    where proposal_id = p_proposal and user_id = p_user and session_id is null;
  if not found then raise exception 'Unexpected YouTube action claim'; end if;
end;
$$;

revoke all on function public.meetin_claim_youtube_action(uuid,uuid) from public, anon, authenticated;
revoke all on function public.meetin_save_youtube_action_session(uuid,uuid,uuid) from public, anon, authenticated;
grant execute on function public.meetin_claim_youtube_action(uuid,uuid) to service_role;
grant execute on function public.meetin_save_youtube_action_session(uuid,uuid,uuid) to service_role;
