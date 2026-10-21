-- Simulated fix: a sender must be a participant of the conversation.
alter policy "authenticated can send messages" on public.messages with check (sender_id = auth.uid()
  and conversation_id in (select id from public.conversations where participant_1 = auth.uid() or participant_2 = auth.uid()));
