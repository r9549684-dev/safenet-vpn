UPDATE users SET trial_ends_at = NOW() + INTERVAL '30 days';
SELECT device_id, trial_ends_at FROM users;
