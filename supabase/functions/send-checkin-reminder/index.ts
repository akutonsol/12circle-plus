// UC16 — Sunday check-in reminder automation
// Deploy and schedule with: supabase functions deploy send-checkin-reminder
// Add pg_cron job: SELECT cron.schedule('weekly-checkin-reminder', '0 9 * * 0', $$
//   SELECT net.http_post(url := '<PROJECT_URL>/functions/v1/send-checkin-reminder',
//     headers := '{"Authorization": "Bearer <SERVICE_ROLE_KEY>"}'::jsonb, body := '{}'::jsonb);
// $$);

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { authorizeServiceCaller, refusalResponse } from './service_caller.mjs';

const RESEND_API_KEY       = Deno.env.get('RESEND_API_KEY') ?? '';
const SUPABASE_URL         = Deno.env.get('SUPABASE_URL') ?? '';
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

serve(async (req) => {
  // P0-SEC-1 / EDGE-2: only the service role (the pg_cron job above) may run
  // the sweep. verify_jwt = true admits any signed-in user's JWT and the
  // legacy anon key, so the bearer is checked here, before any client is
  // built, any row is read or written, or any email is sent.
  const caller = await authorizeServiceCaller(req, SUPABASE_SERVICE_KEY);
  if (!caller.ok) return refusalResponse(caller);

  const db = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

  // Get the start of the current week (Monday)
  const now    = new Date();
  const monday = new Date(now);
  monday.setDate(now.getDate() - ((now.getDay() + 6) % 7));
  monday.setHours(0, 0, 0, 0);
  const mondayIso = monday.toISOString();

  // Find all active coach-client relationships
  const { data: relationships } = await db
    .from('coach_client_relationships')
    .select('client_id, coach_id')
    .eq('status', 'active');

  if (!relationships?.length) {
    return new Response(JSON.stringify({ reminded: 0 }), { status: 200 });
  }

  const clientIds = relationships.map((r: { client_id: string }) => r.client_id);

  // Find clients who have NOT submitted a check-in this week
  const { data: recentCheckins } = await db
    .from('weekly_checkins')
    .select('user_id')
    .in('user_id', clientIds)
    .gte('created_at', mondayIso);

  const checkedInIds = new Set((recentCheckins ?? []).map((c: { user_id: string }) => c.user_id));
  const needsReminder = relationships.filter(
    (r: { client_id: string }) => !checkedInIds.has(r.client_id)
  );

  if (!needsReminder.length) {
    return new Response(JSON.stringify({ reminded: 0, message: 'all clients checked in' }), { status: 200 });
  }

  // Fetch profiles for clients needing reminders
  const needsIds = needsReminder.map((r: { client_id: string }) => r.client_id);
  const { data: profiles } = await db
    .from('user_profiles')
    .select('id, first_name, email')
    .in('id', needsIds);

  const profileMap: Record<string, { first_name?: string; email?: string }> =
    Object.fromEntries((profiles ?? []).map((p: { id: string; first_name?: string; email?: string }) => [p.id, p]));

  let reminded = 0;
  const notificationRows: Array<Record<string, unknown>> = [];
  const emailSends: Promise<boolean>[] = [];

  for (const rel of needsReminder) {
    const clientId = rel.client_id as string;
    const profile  = profileMap[clientId];

    // Insert in-app notification
    notificationRows.push({
      recipient_id: clientId,
      type:         'checkin_reminder',
      title:        'Weekly Check-In Reminder',
      body:         'It\'s Sunday! Time to complete your weekly check-in and keep your streak alive.',
      data:         { action: 'open_checkin' },
      read:         false,
    });

    // Send email if available
    if (profile?.email && RESEND_API_KEY) {
      const name = profile.first_name ?? 'there';
      emailSends.push(
        fetch('https://api.resend.com/emails', {
          method:  'POST',
          headers: { 'Authorization': `Bearer ${RESEND_API_KEY}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({
            from:    '12 Circle Fitness <onboarding@resend.dev>',
            to:      [profile.email],
            subject: '⏰ Weekly Check-In Reminder',
            html: `
              <div style="font-family:sans-serif;max-width:520px;margin:0 auto;background:#0E0B16;color:#E5E2E3;padding:32px;border-radius:12px;">
                <h2 style="color:#DDB7FF;margin:0 0 8px">Time for your weekly check-in!</h2>
                <p style="color:#CFC2D6;margin:0 0 20px">Hi ${name},</p>
                <p style="color:#CFC2D6;">
                  It's Sunday — your coach is waiting for your weekly update. Complete your check-in to
                  track your progress, earn your 12 Circle points, and keep your streak going!
                </p>
                <div style="margin:28px 0;padding:20px;background:#1A1020;border-radius:8px;border-left:3px solid #A855F7;">
                  <p style="margin:0;color:#CFC2D6;font-size:14px;">Open the 12 Circle app and tap <strong style="color:#DDB7FF">Daily Check-In</strong> to get started.</p>
                </div>
                <p style="color:#4B444F;font-size:12px;margin:0;">12 Circle Fitness · Automated reminder sent every Sunday.</p>
              </div>
            `,
          }),
        }).then((r) => r.ok)
      );
    }

    reminded++;
  }

  // Batch insert all notifications
  if (notificationRows.length > 0) {
    await db.from('notifications').insert(notificationRows);
  }

  await Promise.allSettled(emailSends);

  return new Response(JSON.stringify({ reminded, total: needsReminder.length }), {
    headers: { 'Content-Type': 'application/json' },
    status: 200,
  });
});
