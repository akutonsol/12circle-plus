-- ═══════════════════════════════════════════════════════════════════════════
-- 155 · SEED THE APPROVED ADMIN CAPABILITY MATRIX
--
-- Owner (Julia) approved the complete 85-cell / 425-grant authorization policy on
-- 2026-10-05; the artifact is docs/design/admin-dashboard/ADMIN-CAPABILITY-MATRIX.json
-- (committed add4252) and V5 §125 records the approval. This migration is
-- GENERATED FROM THAT FILE — not hand-written — so the database cannot disagree
-- with the approved policy.
--
-- BINARY MODEL, unchanged from 153: a row means granted, its absence means denied.
-- Only the 116 TRUE grants are inserted. The 309 FALSE grants are
-- represented by the ABSENCE of a row, exactly as the owner specified.
--
-- CASING CONTRACT — the one trap here. 153's CHECK accepts LOWERCASE verbs
-- ('view','create','update','manage','approve') while the approved matrix and the
-- Admin design use display casing ('View'). Seeding display casing would insert
-- rows that no caller could ever match, so every grant would be silently inert and
-- every test would pass vacuously. Verbs are therefore lowercased here, AREAS keep
-- their display spelling ('Audit logs', 'AI Guardian', 'Wearable intelligence'),
-- and callers must pass admin_can('<Area display name>', '<lowercase verb>').
--
-- Nothing else changes. No policy, predicate, grant, role value or existing table
-- is touched. is_admin(), is_trust_operator(), is_erasure_executor(), A13·1's audit
-- read policy and A12's identity map are all untouched.
-- ═══════════════════════════════════════════════════════════════════════════

INSERT INTO public.admin_role_capabilities (admin_role, area, verb) VALUES
  ('trust_lead', 'Community', 'view'),
  ('operations_lead', 'Community', 'view'),
  ('support', 'Community', 'view'),
  ('content_editor', 'Community', 'view'),
  ('viewer', 'Community', 'view'),
  ('content_editor', 'Community', 'create'),
  ('content_editor', 'Community', 'update'),
  ('trust_lead', 'Events', 'view'),
  ('operations_lead', 'Events', 'view'),
  ('support', 'Events', 'view'),
  ('content_editor', 'Events', 'view'),
  ('viewer', 'Events', 'view'),
  ('content_editor', 'Events', 'create'),
  ('content_editor', 'Events', 'update'),
  ('trust_lead', 'Training', 'view'),
  ('operations_lead', 'Training', 'view'),
  ('support', 'Training', 'view'),
  ('content_editor', 'Training', 'view'),
  ('viewer', 'Training', 'view'),
  ('content_editor', 'Training', 'create'),
  ('content_editor', 'Training', 'update'),
  ('trust_lead', 'Monetization', 'view'),
  ('operations_lead', 'Monetization', 'view'),
  ('support', 'Monetization', 'view'),
  ('content_editor', 'Monetization', 'view'),
  ('viewer', 'Monetization', 'view'),
  ('trust_lead', 'Wearable intelligence', 'view'),
  ('operations_lead', 'Wearable intelligence', 'view'),
  ('support', 'Wearable intelligence', 'view'),
  ('content_editor', 'Wearable intelligence', 'view'),
  ('viewer', 'Wearable intelligence', 'view'),
  ('trust_lead', 'AI Guardian', 'view'),
  ('operations_lead', 'AI Guardian', 'view'),
  ('viewer', 'AI Guardian', 'view'),
  ('trust_lead', 'AI Guardian', 'create'),
  ('trust_lead', 'AI Guardian', 'update'),
  ('trust_lead', 'AI Guardian', 'manage'),
  ('trust_lead', 'AI Guardian', 'approve'),
  ('trust_lead', 'Security', 'view'),
  ('operations_lead', 'Security', 'view'),
  ('viewer', 'Security', 'view'),
  ('trust_lead', 'Security', 'create'),
  ('trust_lead', 'Security', 'update'),
  ('trust_lead', 'Security', 'manage'),
  ('trust_lead', 'Security', 'approve'),
  ('trust_lead', 'Incidents', 'view'),
  ('operations_lead', 'Incidents', 'view'),
  ('viewer', 'Incidents', 'view'),
  ('trust_lead', 'Incidents', 'create'),
  ('trust_lead', 'Incidents', 'update'),
  ('trust_lead', 'Incidents', 'manage'),
  ('trust_lead', 'Incidents', 'approve'),
  ('trust_lead', 'Audit logs', 'view'),
  ('operations_lead', 'Audit logs', 'view'),
  ('viewer', 'Audit logs', 'view'),
  ('trust_lead', 'Audit logs', 'create'),
  ('trust_lead', 'Audit logs', 'update'),
  ('trust_lead', 'Audit logs', 'manage'),
  ('trust_lead', 'Audit logs', 'approve'),
  ('trust_lead', 'QA', 'view'),
  ('operations_lead', 'QA', 'view'),
  ('support', 'QA', 'view'),
  ('content_editor', 'QA', 'view'),
  ('viewer', 'QA', 'view'),
  ('operations_lead', 'QA', 'create'),
  ('operations_lead', 'QA', 'update'),
  ('operations_lead', 'QA', 'manage'),
  ('operations_lead', 'QA', 'approve'),
  ('trust_lead', 'Releases', 'view'),
  ('operations_lead', 'Releases', 'view'),
  ('support', 'Releases', 'view'),
  ('content_editor', 'Releases', 'view'),
  ('viewer', 'Releases', 'view'),
  ('operations_lead', 'Releases', 'create'),
  ('operations_lead', 'Releases', 'update'),
  ('operations_lead', 'Releases', 'manage'),
  ('operations_lead', 'Releases', 'approve'),
  ('trust_lead', 'Integrations', 'view'),
  ('operations_lead', 'Integrations', 'view'),
  ('support', 'Integrations', 'view'),
  ('content_editor', 'Integrations', 'view'),
  ('viewer', 'Integrations', 'view'),
  ('operations_lead', 'Integrations', 'create'),
  ('operations_lead', 'Integrations', 'update'),
  ('operations_lead', 'Integrations', 'manage'),
  ('operations_lead', 'Integrations', 'approve'),
  ('trust_lead', 'System', 'view'),
  ('operations_lead', 'System', 'view'),
  ('support', 'System', 'view'),
  ('content_editor', 'System', 'view'),
  ('viewer', 'System', 'view'),
  ('operations_lead', 'System', 'create'),
  ('operations_lead', 'System', 'update'),
  ('operations_lead', 'System', 'manage'),
  ('operations_lead', 'System', 'approve'),
  ('trust_lead', 'Organization', 'view'),
  ('operations_lead', 'Organization', 'view'),
  ('support', 'Organization', 'view'),
  ('content_editor', 'Organization', 'view'),
  ('viewer', 'Organization', 'view'),
  ('trust_lead', 'Users', 'view'),
  ('operations_lead', 'Users', 'view'),
  ('support', 'Users', 'view'),
  ('content_editor', 'Users', 'view'),
  ('viewer', 'Users', 'view'),
  ('support', 'Users', 'update'),
  ('trust_lead', 'Roles', 'view'),
  ('operations_lead', 'Roles', 'view'),
  ('support', 'Roles', 'view'),
  ('content_editor', 'Roles', 'view'),
  ('viewer', 'Roles', 'view'),
  ('trust_lead', 'Configuration', 'view'),
  ('operations_lead', 'Configuration', 'view'),
  ('support', 'Configuration', 'view'),
  ('content_editor', 'Configuration', 'view'),
  ('viewer', 'Configuration', 'view')
ON CONFLICT (admin_role, area, verb) DO NOTHING;
