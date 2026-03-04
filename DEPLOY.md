# 🚀 ironCRM — Guide de déploiement multi-club

## Vue d'ensemble

```
ironCRM-multiclub.html   → Frontend (déployer sur Vercel / GitHub Pages)
supabase-setup.sql       → Backend (coller dans Supabase SQL Editor)
```

---

## ÉTAPE 1 — Créer votre projet Supabase (10 min)

1. Aller sur **https://supabase.com** → "Start your project"
2. Créer un compte (gratuit, pas de CB)
3. "New project" :
   - **Name** : `ironcrm-prod`
   - **Database password** : choisir un mot de passe fort (le noter !)
   - **Region** : `eu-west-3` (Paris) recommandé
4. Attendre ~2 min que le projet s'initialise

---

## ÉTAPE 2 — Installer le schéma SQL (5 min)

1. Dans Supabase → **SQL Editor** → "New Query"
2. Copier-coller **tout le contenu** de `supabase-setup.sql`
3. Cliquer **"Run"** (bouton vert en bas à droite)
4. Vérifier : message `Success. No rows returned`

> ✅ Cela crée : clubs, users, prospects, appointments, automations, pipeline_stages, activity_feed, RLS multi-tenant, fonctions automatiques

---

## ÉTAPE 3 — Récupérer vos clés API (2 min)

Dans Supabase → **Settings** → **API** :

```
Project URL  →  VOTRE_SUPABASE_URL    (ex: https://abcdefg.supabase.co)
anon public  →  VOTRE_ANON_KEY        (ex: eyJhbGci...)
```

---

## ÉTAPE 4 — Configurer l'application (2 min)

Ouvrir `ironCRM-multiclub.html` dans un éditeur de texte.

Trouver les lignes (vers le début du `<script>`) :

```javascript
const SUPABASE_URL = 'VOTRE_SUPABASE_URL';
const SUPABASE_ANON_KEY = 'VOTRE_ANON_KEY';
```

Remplacer par vos vraies valeurs :

```javascript
const SUPABASE_URL = 'https://abcdefg.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...';
```

---

## ÉTAPE 5 — Activer l'authentification email (3 min)

Dans Supabase → **Authentication** → **Providers** :

1. **Email** → activer "Enable Email Provider" ✓
2. Désactiver "Confirm email" pour les tests (réactiver en prod)
3. **Authentication** → **URL Configuration** :
   - Site URL : `https://votre-domaine.com` (ou `http://localhost` pour les tests)

---

## ÉTAPE 6 — Déployer le frontend

### Option A — Vercel (recommandé, gratuit)

```bash
# 1. Créer un repo GitHub avec votre fichier HTML renommé index.html
# 2. Aller sur vercel.com → "New Project" → importer le repo
# 3. Deploy → vous obtenez une URL https://ironcrm-xxx.vercel.app
```

### Option B — GitHub Pages (gratuit)

```bash
# 1. Créer un repo GitHub public
# 2. Uploader ironCRM-multiclub.html renommé en index.html
# 3. Settings → Pages → Source: main branch
# URL : https://votre-username.github.io/ironcrm
```

### Option C — Hébergement simple (OVH, etc.)

```bash
# Uploader le fichier HTML sur votre hébergeur via FTP
# Renommer en index.html
```

---

## ÉTAPE 7 — Créer votre compte Super Admin

Une fois déployé, ouvrez l'app dans le navigateur.

### Via SQL Editor Supabase :

```sql
-- 1. D'abord créer un compte via l'interface (inscription normale)
-- 2. Récupérer votre auth_id :
SELECT id, email FROM auth.users;

-- 3. Vous ajouter comme super admin :
INSERT INTO super_admins (auth_id, email)
VALUES ('VOTRE-AUTH-ID-UUID', 'votre@email.com');
```

Après ça, connectez-vous → vous verrez le **panneau Super Admin** avec tous les clubs.

---

## ÉTAPE 8 — Configurer l'email transactionnel (optionnel)

Pour les emails de bienvenue, réinitialisation, etc. :

### Supabase Auth emails (gratuit, limité)
Supabase envoie automatiquement les emails de confirmation.

### Resend (recommandé, 3000 emails/mois gratuit)

1. Créer compte sur **resend.com**
2. Ajouter votre domaine
3. Dans Supabase → **Settings** → **Auth** → **SMTP Settings** :
   ```
   Host: smtp.resend.com
   Port: 465
   User: resend
   Pass: votre-api-key-resend
   Sender: ironCRM <noreply@votreclubcrm.fr>
   ```

---

## ÉTAPE 9 — Stripe pour la facturation (optionnel)

```bash
# 1. Créer un compte stripe.com
# 2. Créer 3 produits / prix :
#    - Starter : 79€/mois  → price_xxx_starter
#    - Pro     : 149€/mois → price_xxx_pro
#    - Réseau  : 299€/mois → price_xxx_reseau
# 3. Activer Stripe Customer Portal
# 4. Intégrer les liens de paiement dans l'app (settings > plan)
```

---

## Architecture multi-tenant : comment ça marche

```
Chaque club a son club_id unique
↓
Row Level Security (RLS) sur Supabase
↓
Chaque requête est automatiquement filtrée par club_id
↓
Un club ne peut JAMAIS voir les données d'un autre club
```

### Règle RLS exemple (prospects) :
```sql
-- Automatiquement appliqué sur TOUTES les requêtes
SELECT * FROM prospects
WHERE club_id = get_user_club_id()  -- fonction = club de l'utilisateur connecté
```

---

## Limites par plan

| Plan     | Prix      | Utilisateurs | Prospects | Multi-locations |
|----------|-----------|-------------|-----------|-----------------|
| Starter  | 79€/mois  | 1           | 500       | Non             |
| Pro      | 149€/mois | 5           | Illimité  | Non             |
| Réseau   | 299€/mois | Illimité    | Illimité  | Oui             |

Ces limites sont gérées côté app JS (fichier HTML) et vérifiables côté SQL.

---

## Checklist Go-Live

- [ ] Supabase projet créé
- [ ] SQL schema installé
- [ ] Clés API configurées dans le HTML
- [ ] Auth email activé
- [ ] Frontend déployé (Vercel/GitHub)
- [ ] Compte super admin créé
- [ ] Email SMTP configuré
- [ ] Domaine personnalisé (optionnel)
- [ ] Stripe configuré (optionnel)
- [ ] Premier club client créé et testé

---

## Séquence recommandée (lancement en 2 semaines)

**Semaine 1 :**
- Jours 1-2 : Supabase + déploiement Vercel (ce guide)
- Jours 3-4 : Créer 5 comptes de test avec de vrais clubs pilotes
- Jours 5-7 : Feedbacks et corrections

**Semaine 2 :**
- Jours 8-10 : Stripe + facturation
- Jours 11-14 : 5 premiers clients payants à 49€/mois (tarif lancement)

**Objectif mois 2 :** 10 clubs × 79€ = 790€ MRR → valide le produit

---

## Support & Questions

- Email : contact@ironcrm.fr
- Documentation Supabase : https://supabase.com/docs
- Documentation Vercel : https://vercel.com/docs

---

*ironCRM v2 — Architecture multi-club avec Supabase RLS*
