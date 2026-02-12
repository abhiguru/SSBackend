# Masala DB Backup & Restore

Automated Google Drive backup system for the Masala Spice Shop database.

## Quick Reference

| Setting | Value |
|---------|-------|
| Container | `masala-db` |
| Google Drive remote | `gdrive2:` |
| GDrive folder | `/masala_backups/` |
| Retention | 7 backups |
| Cron schedule | 3:30 AM daily |
| Log file | `logs/masala-backup.log` |

## Daily Backup (automated)

Runs automatically via cron at 3:30 AM. To run manually:

```bash
cd /home/gcswebserver/ws/SSMasala/backend
backup/backup_to_gdrive.sh
```

What it does:
1. `pg_dump` from `masala-db` container
2. Verifies backup has completion marker and is non-empty
3. Generates SHA256 checksum
4. Uploads SQL + checksum to `gdrive2:/masala_backups/`
5. Prunes old backups (keeps last 7, both local and GDrive)

## Restore from Google Drive

Interactive restore script:

```bash
cd /home/gcswebserver/ws/SSMasala/backend
backup/restore_from_gdrive.sh
```

What it does:
1. Lists available backups from GDrive (newest first)
2. Downloads selected backup
3. Verifies SHA256 checksum
4. Warns if DB has existing data (requires "YES" confirmation)
5. Stops supavisor, restores via `psql`, restarts supavisor
6. Verifies table and function counts

## Check Backup Status

```bash
# View recent backup log
tail -50 logs/masala-backup.log

# List backups in Google Drive
rclone ls gdrive2:/masala_backups/

# List local backups
ls -lh backup/masala_backup_*.sql

# Verify cron is scheduled
crontab -l | grep masala
```

## Troubleshooting

**Backup fails with "Another instance is running"**: Check for stale lock file at `/tmp/masala_backup_to_gdrive.lock`.

**rclone upload fails**: Verify rclone config with `rclone listremotes` (should show `gdrive2:`). Test with `rclone lsd gdrive2:/`.

**Restore checksum mismatch**: The backup file may be corrupted. Try a different backup.

**DB not running during restore**: Start the stack with `docker compose up -d` first.
