-- ═══════════════════════════════════════════════════════════════
-- IRONCRM — SETUP COMPLET SUPABASE (v2 — fix vue existante)
-- Exécutez ce fichier dans Supabase SQL Editor en une seule fois
-- ═══════════════════════════════════════════════════════════════

-- ══════════════════════════════════════
-- 0. NETTOYAGE — Supprimer les objets existants si besoin
-- ══════════════════════════════════════

DROP VIEW IF EXISTS public.admin_clubs_overview CASCADE;
DROP FUNCTION IF EXISTS public.register_new_club CASCADE;
DROP FUNCTION IF EXISTS public.get_my_club_id CASCADE;
DROP FUNCTION IF EXISTS public.is_super_admin CASCADE;


-- ══════════════════════════════════════
-- 1. TABLES
-- ══════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.clubs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  slug TEXT UNIQUE NOT NULL,
  plan TEXT NOT NULL DEFAULT 'starter' CHECK (plan IN ('starter', 'pro', 'reseau')),
  max_users INT NOT NULL DEFAULT 1,
  max_prospects INT NOT NULL DEFAULT 500,
  club_type TEXT DEFAULT 'Salle de fitness',
  phone TEXT DEFAULT '',
  website TEXT DEFAULT '',
  address TEXT DEFAULT '',
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  club_id UUID NOT NULL REFERENCES public.clubs(id) ON DELETE CASCADE,
  auth_id UUID UNIQUE NOT NULL,
  email TEXT NOT NULL,
  firstname TEXT NOT NULL DEFAULT '',
  lastname TEXT NOT NULL DEFAULT '',
  role TEXT NOT NULL DEFAULT 'commercial' CHECK (role IN ('admin', 'manager', 'commercial')),
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.super_admins (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_id UUID UNIQUE NOT NULL,
  email TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.pipeline_stages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  club_id UUID NOT NULL REFERENCES public.clubs(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  slug TEXT NOT NULL,
  color TEXT NOT NULL DEFAULT '#6b6b7a',
  position INT NOT NULL DEFAULT 0,
  is_won BOOLEAN NOT NULL DEFAULT false,
  is_lost BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.prospects (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  club_id UUID NOT NULL REFERENCES public.clubs(id) ON DELETE CASCADE,
  firstname TEXT NOT NULL,
  lastname TEXT NOT NULL,
  email TEXT DEFAULT '',
  phone TEXT DEFAULT '',
  source TEXT NOT NULL DEFAULT 'Autre',
  status TEXT NOT NULL DEFAULT 'nouveau',
  goal TEXT DEFAULT '',
  budget TEXT DEFAULT '',
  score INT NOT NULL DEFAULT 50 CHECK (score >= 0 AND score <= 100),
  assignee_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
  notes TEXT DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.prospect_timeline (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  prospect_id UUID NOT NULL REFERENCES public.prospects(id) ON DELETE CASCADE,
  club_id UUID NOT NULL REFERENCES public.clubs(id) ON DELETE CASCADE,
  user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
  type TEXT NOT NULL DEFAULT 'note',
  text TEXT NOT NULL,
  detail TEXT DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.appointments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  club_id UUID NOT NULL REFERENCES public.clubs(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  prospect_id UUID REFERENCES public.prospects(id) ON DELETE SET NULL,
  user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
  scheduled_at TIMESTAMPTZ NOT NULL,
  duration_minutes INT NOT NULL DEFAULT 30,
  type TEXT NOT NULL DEFAULT 'Visite du club',
  notes TEXT DEFAULT '',
  status TEXT NOT NULL DEFAULT 'scheduled' CHECK (status IN ('scheduled', 'completed', 'cancelled')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.automations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  club_id UUID NOT NULL REFERENCES public.clubs(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  trigger_type TEXT NOT NULL DEFAULT 'new_prospect',
  source_filter TEXT DEFAULT '',
  description TEXT DEFAULT '',
  steps JSONB NOT NULL DEFAULT '[]'::jsonb,
  is_enabled BOOLEAN NOT NULL DEFAULT false,
  run_count INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.activity_feed (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  club_id UUID NOT NULL REFERENCES public.clubs(id) ON DELETE CASCADE,
  user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
  text TEXT NOT NULL,
  color TEXT NOT NULL DEFAULT '#ff4c00',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);


-- ══════════════════════════════════════
-- 2. VUE ADMIN
-- ══════════════════════════════════════

CREATE VIEW public.admin_clubs_overview AS
SELECT
  c.id,
  c.name,
  c.slug,
  c.plan,
  c.is_active,
  c.created_at,
  COALESCE((SELECT COUNT(*) FROM public.users u WHERE u.club_id = c.id AND u.is_active = true), 0)::int AS user_count,
  COALESCE((SELECT COUNT(*) FROM public.prospects p WHERE p.club_id = c.id), 0)::int AS prospect_count,
  COALESCE((SELECT COUNT(*) FROM public.prospects p WHERE p.club_id = c.id AND p.status = 'converti'), 0)::int AS converted_count
FROM public.clubs c
ORDER BY c.created_at DESC;

GRANT SELECT ON public.admin_clubs_overview TO authenticated;


-- ══════════════════════════════════════
-- 3. INDEX
-- ══════════════════════════════════════

CREATE INDEX IF NOT EXISTS idx_users_auth_id ON public.users(auth_id);
CREATE INDEX IF NOT EXISTS idx_users_club_id ON public.users(club_id);
CREATE INDEX IF NOT EXISTS idx_prospects_club_id ON public.prospects(club_id);
CREATE INDEX IF NOT EXISTS idx_prospects_status ON public.prospects(status);
CREATE INDEX IF NOT EXISTS idx_prospects_assignee ON public.prospects(assignee_id);
CREATE INDEX IF NOT EXISTS idx_pipeline_stages_club ON public.pipeline_stages(club_id, position);
CREATE INDEX IF NOT EXISTS idx_timeline_prospect ON public.prospect_timeline(prospect_id);
CREATE INDEX IF NOT EXISTS idx_appointments_club ON public.appointments(club_id);
CREATE INDEX IF NOT EXISTS idx_appointments_date ON public.appointments(scheduled_at);
CREATE INDEX IF NOT EXISTS idx_automations_club ON public.automations(club_id);
CREATE INDEX IF NOT EXISTS idx_activity_club ON public.activity_feed(club_id, created_at DESC);


-- ══════════════════════════════════════
-- 4. FONCTIONS RPC
-- ══════════════════════════════════════

-- Helper : récupérer le club_id de l'utilisateur connecté
CREATE FUNCTION public.get_my_club_id()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT club_id FROM public.users WHERE auth_id = auth.uid() AND is_active = true LIMIT 1;
$$;

-- Helper : vérifier si super admin
CREATE FUNCTION public.is_super_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (SELECT 1 FROM public.super_admins WHERE auth_id = auth.uid());
$$;

-- RPC : inscription nouveau club
CREATE FUNCTION public.register_new_club(
  p_club_name TEXT,
  p_club_slug TEXT,
  p_user_email TEXT,
  p_user_firstname TEXT,
  p_user_lastname TEXT,
  p_auth_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_club_id UUID;
  v_user_id UUID;
BEGIN
  INSERT INTO public.clubs (name, slug, plan, max_users, max_prospects)
  VALUES (p_club_name, p_club_slug, 'starter', 1, 500)
  RETURNING id INTO v_club_id;

  INSERT INTO public.users (club_id, auth_id, email, firstname, lastname, role, is_active)
  VALUES (v_club_id, p_auth_id, p_user_email, p_user_firstname, p_user_lastname, 'admin', true)
  RETURNING id INTO v_user_id;

  INSERT INTO public.pipeline_stages (club_id, name, slug, color, position, is_won, is_lost) VALUES
    (v_club_id, 'Nouveau',        'nouveau',   '#6b6b7a', 0, false, false),
    (v_club_id, 'Contacté',       'contacte',  '#c8943a', 1, false, false),
    (v_club_id, 'En visite',      'visite',    '#3b82f6', 2, false, false),
    (v_club_id, 'Offre envoyée',  'offre',     '#ff4c00', 3, false, false),
    (v_club_id, 'Converti ✓',     'converti',  '#22c55e', 4, true,  false),
    (v_club_id, 'Perdu',          'perdu',     '#ef4444', 5, false, true);

  INSERT INTO public.activity_feed (club_id, user_id, text, color)
  VALUES (v_club_id, v_user_id, 'Bienvenue sur <strong>ironCRM</strong> ! Votre club est prêt.', '#22c55e');
END;
$$;


-- ══════════════════════════════════════
-- 5. ROW LEVEL SECURITY (RLS)
-- ══════════════════════════════════════

ALTER TABLE public.clubs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.super_admins ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pipeline_stages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prospects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prospect_timeline ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.appointments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.automations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activity_feed ENABLE ROW LEVEL SECURITY;

-- ── CLUBS ──
DROP POLICY IF EXISTS "Users can view their own club" ON public.clubs;
DROP POLICY IF EXISTS "Admins can update their club" ON public.clubs;

CREATE POLICY "Users can view their own club"
  ON public.clubs FOR SELECT
  USING (id = public.get_my_club_id() OR public.is_super_admin());

CREATE POLICY "Admins can update their club"
  ON public.clubs FOR UPDATE
  USING (id = public.get_my_club_id())
  WITH CHECK (id = public.get_my_club_id());

-- ── USERS ──
DROP POLICY IF EXISTS "Users can view members of their club" ON public.users;
DROP POLICY IF EXISTS "Users can read their own profile at login" ON public.users;
DROP POLICY IF EXISTS "Admins can insert members" ON public.users;
DROP POLICY IF EXISTS "Admins can update members" ON public.users;

CREATE POLICY "Users can view members of their club"
  ON public.users FOR SELECT
  USING (club_id = public.get_my_club_id() OR public.is_super_admin());

CREATE POLICY "Users can read their own profile at login"
  ON public.users FOR SELECT
  USING (auth_id = auth.uid());

CREATE POLICY "Admins can insert members"
  ON public.users FOR INSERT
  WITH CHECK (club_id = public.get_my_club_id());

CREATE POLICY "Admins can update members"
  ON public.users FOR UPDATE
  USING (club_id = public.get_my_club_id())
  WITH CHECK (club_id = public.get_my_club_id());

-- ── SUPER ADMINS ──
DROP POLICY IF EXISTS "Super admins can read their own record" ON public.super_admins;

CREATE POLICY "Super admins can read their own record"
  ON public.super_admins FOR SELECT
  USING (auth_id = auth.uid());

-- ── PIPELINE STAGES ──
DROP POLICY IF EXISTS "Users can view their club stages" ON public.pipeline_stages;
DROP POLICY IF EXISTS "Users can insert stages" ON public.pipeline_stages;
DROP POLICY IF EXISTS "Users can update stages" ON public.pipeline_stages;
DROP POLICY IF EXISTS "Users can delete stages" ON public.pipeline_stages;

CREATE POLICY "Users can view their club stages"
  ON public.pipeline_stages FOR SELECT
  USING (club_id = public.get_my_club_id());

CREATE POLICY "Users can insert stages"
  ON public.pipeline_stages FOR INSERT
  WITH CHECK (club_id = public.get_my_club_id());

CREATE POLICY "Users can update stages"
  ON public.pipeline_stages FOR UPDATE
  USING (club_id = public.get_my_club_id());

CREATE POLICY "Users can delete stages"
  ON public.pipeline_stages FOR DELETE
  USING (club_id = public.get_my_club_id());

-- ── PROSPECTS ──
DROP POLICY IF EXISTS "Users can view their club prospects" ON public.prospects;
DROP POLICY IF EXISTS "Users can insert prospects" ON public.prospects;
DROP POLICY IF EXISTS "Users can update prospects" ON public.prospects;
DROP POLICY IF EXISTS "Users can delete prospects" ON public.prospects;

CREATE POLICY "Users can view their club prospects"
  ON public.prospects FOR SELECT
  USING (club_id = public.get_my_club_id() OR public.is_super_admin());

CREATE POLICY "Users can insert prospects"
  ON public.prospects FOR INSERT
  WITH CHECK (club_id = public.get_my_club_id());

CREATE POLICY "Users can update prospects"
  ON public.prospects FOR UPDATE
  USING (club_id = public.get_my_club_id());

CREATE POLICY "Users can delete prospects"
  ON public.prospects FOR DELETE
  USING (club_id = public.get_my_club_id());

-- ── PROSPECT TIMELINE ──
DROP POLICY IF EXISTS "Users can view their club timeline" ON public.prospect_timeline;
DROP POLICY IF EXISTS "Users can insert timeline entries" ON public.prospect_timeline;

CREATE POLICY "Users can view their club timeline"
  ON public.prospect_timeline FOR SELECT
  USING (club_id = public.get_my_club_id());

CREATE POLICY "Users can insert timeline entries"
  ON public.prospect_timeline FOR INSERT
  WITH CHECK (club_id = public.get_my_club_id());

-- ── APPOINTMENTS ──
DROP POLICY IF EXISTS "Users can view their club appointments" ON public.appointments;
DROP POLICY IF EXISTS "Users can insert appointments" ON public.appointments;
DROP POLICY IF EXISTS "Users can update appointments" ON public.appointments;
DROP POLICY IF EXISTS "Users can delete appointments" ON public.appointments;

CREATE POLICY "Users can view their club appointments"
  ON public.appointments FOR SELECT
  USING (club_id = public.get_my_club_id());

CREATE POLICY "Users can insert appointments"
  ON public.appointments FOR INSERT
  WITH CHECK (club_id = public.get_my_club_id());

CREATE POLICY "Users can update appointments"
  ON public.appointments FOR UPDATE
  USING (club_id = public.get_my_club_id());

CREATE POLICY "Users can delete appointments"
  ON public.appointments FOR DELETE
  USING (club_id = public.get_my_club_id());

-- ── AUTOMATIONS ──
DROP POLICY IF EXISTS "Users can view their club automations" ON public.automations;
DROP POLICY IF EXISTS "Users can insert automations" ON public.automations;
DROP POLICY IF EXISTS "Users can update automations" ON public.automations;
DROP POLICY IF EXISTS "Users can delete automations" ON public.automations;

CREATE POLICY "Users can view their club automations"
  ON public.automations FOR SELECT
  USING (club_id = public.get_my_club_id());

CREATE POLICY "Users can insert automations"
  ON public.automations FOR INSERT
  WITH CHECK (club_id = public.get_my_club_id());

CREATE POLICY "Users can update automations"
  ON public.automations FOR UPDATE
  USING (club_id = public.get_my_club_id());

CREATE POLICY "Users can delete automations"
  ON public.automations FOR DELETE
  USING (club_id = public.get_my_club_id());

-- ── ACTIVITY FEED ──
DROP POLICY IF EXISTS "Users can view their club activity" ON public.activity_feed;
DROP POLICY IF EXISTS "Users can insert activity" ON public.activity_feed;

CREATE POLICY "Users can view their club activity"
  ON public.activity_feed FOR SELECT
  USING (club_id = public.get_my_club_id());

CREATE POLICY "Users can insert activity"
  ON public.activity_feed FOR INSERT
  WITH CHECK (club_id = public.get_my_club_id());


-- ══════════════════════════════════════
-- 6. CRÉER VOTRE PROFIL (anthony.rome45@gmail.com)
-- ══════════════════════════════════════

DO $$
DECLARE
  v_club_id UUID;
  v_user_id UUID;
  v_auth_id UUID := '2323cf1d-3ade-41bf-80f6-b66cf96a0fd0';
BEGIN
  IF EXISTS (SELECT 1 FROM public.users WHERE auth_id = v_auth_id) THEN
    RAISE NOTICE 'Profil existe déjà — rien à faire.';
    RETURN;
  END IF;

  INSERT INTO public.clubs (name, slug, plan, max_users, max_prospects)
  VALUES ('Mon Club', 'mon-club-' || extract(epoch FROM now())::bigint, 'starter', 1, 500)
  RETURNING id INTO v_club_id;

  INSERT INTO public.users (club_id, auth_id, email, firstname, lastname, role, is_active)
  VALUES (v_club_id, v_auth_id, 'anthony.rome45@gmail.com', 'Anthony', 'Rome', 'admin', true)
  RETURNING id INTO v_user_id;

  INSERT INTO public.pipeline_stages (club_id, name, slug, color, position, is_won, is_lost) VALUES
    (v_club_id, 'Nouveau',        'nouveau',   '#6b6b7a', 0, false, false),
    (v_club_id, 'Contacté',       'contacte',  '#c8943a', 1, false, false),
    (v_club_id, 'En visite',      'visite',    '#3b82f6', 2, false, false),
    (v_club_id, 'Offre envoyée',  'offre',     '#ff4c00', 3, false, false),
    (v_club_id, 'Converti ✓',     'converti',  '#22c55e', 4, true,  false),
    (v_club_id, 'Perdu',          'perdu',     '#ef4444', 5, false, true);

  INSERT INTO public.activity_feed (club_id, user_id, text, color)
  VALUES (v_club_id, v_user_id, 'Bienvenue sur <strong>ironCRM</strong> ! Votre club est prêt.', '#22c55e');

  RAISE NOTICE 'Profil créé ! club_id = %', v_club_id;
END;
$$;


-- ✅ TERMINÉ — Connectez-vous sur ironCRM !
