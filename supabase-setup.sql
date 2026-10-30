-- Mes Comptes : à coller une fois dans Supabase → SQL Editor → New query → Run.
-- Une ligne par document : "settings" (budgets, décisions sur les abonnements) et "m-AAAA-MM" (opérations du mois).

create table if not exists public.mc_docs (
  user_id    uuid        not null default auth.uid() references auth.users(id) on delete cascade,
  doc_id     text        not null,
  data       jsonb       not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, doc_id)
);

-- Chacun ne voit et ne modifie que ses propres lignes.
alter table public.mc_docs enable row level security;

drop policy if exists "mc_docs lecture perso"      on public.mc_docs;
drop policy if exists "mc_docs ajout perso"        on public.mc_docs;
drop policy if exists "mc_docs modification perso" on public.mc_docs;
drop policy if exists "mc_docs suppression perso"  on public.mc_docs;

create policy "mc_docs lecture perso"      on public.mc_docs for select to authenticated using (auth.uid() = user_id);
create policy "mc_docs ajout perso"        on public.mc_docs for insert to authenticated with check (auth.uid() = user_id);
create policy "mc_docs modification perso" on public.mc_docs for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "mc_docs suppression perso"  on public.mc_docs for delete to authenticated using (auth.uid() = user_id);

-- Mise à jour en direct entre le téléphone et l'ordi.
do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'mc_docs') then
    alter publication supabase_realtime add table public.mc_docs;
  end if;
end $$;
