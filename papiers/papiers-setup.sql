-- Mes Papiers : à coller une fois dans Supabase → SQL Editor → New query → Run.
-- Range tes documents (impôts, salaires, loyers…) dans ton projet Supabase, visibles de toi seul.
-- Un fichier = une ligne dans mp_files ; son contenu est découpé en morceaux (base64) dans mp_chunks.

create table if not exists public.mp_files (
  id        bigserial   primary key,
  user_id   uuid        not null default auth.uid() references auth.users(id) on delete cascade,
  path      text        not null,               -- ex. "loyers/2026-11_Dijon_quittance.pdf"
  folder    text        not null,               -- ex. "Logement"
  name      text        not null,               -- nom du fichier
  mime      text        not null,
  size      bigint      not null,
  sha256    text        not null,
  chunks    int         not null,
  doc_date  text,                               -- "AAAA-MM" lu dans le nom
  added_at  timestamptz not null default now(),
  unique (user_id, path)
);
create table if not exists public.mp_chunks (
  file_id bigint not null references public.mp_files(id) on delete cascade,
  idx     int    not null,
  data    text   not null,
  primary key (file_id, idx)
);

alter table public.mp_files  enable row level security;
alter table public.mp_chunks enable row level security;

drop policy if exists "mp_files perso"  on public.mp_files;
drop policy if exists "mp_chunks perso" on public.mp_chunks;
create policy "mp_files perso" on public.mp_files for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "mp_chunks perso" on public.mp_chunks for all to authenticated
  using (exists (select 1 from public.mp_files f where f.id = file_id and f.user_id = auth.uid()))
  with check (exists (select 1 from public.mp_files f where f.id = file_id and f.user_id = auth.uid()));

-- Accès de Claude (rangement des documents que tu lui envoies) : une clé secrète,
-- créée dans l'appli (⋯ → Accès pour Claude). Seule son empreinte est gardée ici.
create table if not exists public.mp_claude (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  key_hash   text not null,
  created_at timestamptz not null default now()
);
alter table public.mp_claude enable row level security;   -- aucune règle : illisible directement

create or replace function public.mp_set_claude_key(p_hash text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'non connecté'; end if;
  if p_hash !~ '^[0-9a-f]{64}$' then raise exception 'empreinte invalide'; end if;
  insert into mp_claude(user_id, key_hash) values (auth.uid(), p_hash)
  on conflict (user_id) do update set key_hash = excluded.key_hash, created_at = now();
end $$;
create or replace function public.mp_del_claude_key() returns void
language sql security definer set search_path = public as $$
  delete from mp_claude where user_id = auth.uid();
$$;
create or replace function public.mp_has_claude_key() returns boolean
language sql security definer set search_path = public as $$
  select exists (select 1 from mp_claude where user_id = auth.uid());
$$;

-- propriétaire désigné par la clé envoyée dans l'en-tête « x-papiers-key »
create or replace function public._mp_owner() returns uuid
language plpgsql security definer set search_path = public as $$
declare k text; o uuid;
begin
  k := coalesce(current_setting('request.headers', true)::json ->> 'x-papiers-key', '');
  if length(k) < 20 then raise exception 'clé manquante'; end if;
  select user_id into o from mp_claude where key_hash = encode(sha256(convert_to(k, 'UTF8')), 'hex');
  if o is null then raise exception 'clé refusée'; end if;
  return o;
end $$;

create or replace function public.mp_c_list()
returns table(path text, sha256 text, size bigint, chunks int)
language plpgsql security definer set search_path = public as $$
declare o uuid := _mp_owner();
begin
  return query select f.path, f.sha256, f.size, f.chunks from mp_files f where f.user_id = o order by f.path;
end $$;

create or replace function public.mp_c_begin(p_path text, p_folder text, p_name text, p_mime text,
  p_size bigint, p_sha text, p_chunks int, p_date text) returns bigint
language plpgsql security definer set search_path = public as $$
declare o uuid := _mp_owner(); fid bigint;
begin
  delete from mp_files where user_id = o and path = p_path;
  insert into mp_files(user_id, path, folder, name, mime, size, sha256, chunks, doc_date)
  values (o, p_path, p_folder, p_name, p_mime, p_size, p_sha, p_chunks, p_date) returning id into fid;
  return fid;
end $$;

create or replace function public.mp_c_chunk(p_id bigint, p_idx int, p_data text) returns void
language plpgsql security definer set search_path = public as $$
declare o uuid := _mp_owner();
begin
  if not exists (select 1 from mp_files where id = p_id and user_id = o) then raise exception 'fichier inconnu'; end if;
  insert into mp_chunks(file_id, idx, data) values (p_id, p_idx, p_data)
  on conflict (file_id, idx) do update set data = excluded.data;
end $$;

create or replace function public.mp_c_delete(p_path text) returns void
language plpgsql security definer set search_path = public as $$
declare o uuid := _mp_owner();
begin
  delete from mp_files where user_id = o and path = p_path;
end $$;

revoke all on function public._mp_owner() from public, anon, authenticated;
grant execute on function public.mp_c_list(), public.mp_c_begin(text,text,text,text,bigint,text,int,text),
  public.mp_c_chunk(bigint,int,text), public.mp_c_delete(text) to anon, authenticated;
grant execute on function public.mp_set_claude_key(text), public.mp_del_claude_key(), public.mp_has_claude_key() to authenticated;
