# Deployment Scripts Changes: Removed Deploy User Concept

## Summary

The deployment scripts have been updated to remove the "deploy user" concept and now use the currently logged-in user instead. This simplifies the deployment process and eliminates the need to create and manage a separate deployment user.

## Changes Made

### 1. deploy-wise-owl.sh

**Before:**

- Used `DEPLOY_USER="${DEPLOY_USER:-deploy}"`
- Created directories with `deploy` user ownership
- Ran commands as the deploy user via `sudo -u $DEPLOY_USER`

**After:**

- Uses `CURRENT_USER="$(whoami)"` to get the current user
- Creates directories with current user ownership
- Runs commands directly without user switching
- Systemd service uses current user instead of deploy user
- Cron jobs run as current user instead of deploy user

### 2. setup-raspberry-pi-generic.sh

**Before:**

- Had an interactive user creation process
- Created a separate "deploy" user with sudo privileges
- Set up SSH keys for the deploy user
- Changed ownership of all directories to deploy user

**After:**

- Uses `CURRENT_USER="$(logname 2>/dev/null || echo $SUDO_USER)"` to detect the original user (even when run with sudo)
- Removes the user creation phase entirely
- Adds current user to docker group automatically
- Provides instructions for SSH key setup for current user
- All directory ownership uses current user

## Benefits

1. **Simplified Setup**: No need to create and manage a separate user account
2. **Reduced Complexity**: Eliminates user switching and permission complications
3. **Better Security**: Uses the actual user's account with proper permissions
4. **Easier Maintenance**: No confusion about which user owns what files
5. **More Intuitive**: Works with the user that's actually running the deployment

## Usage Notes

### For setup-raspberry-pi-generic.sh:

- Must still be run as root (using `sudo`)
- Automatically detects the original user who ran sudo
- Sets up permissions for the original user, not root

### For deploy-wise-owl.sh:

- Can be run as the regular user (no sudo required for most operations)
- Uses current user for all file operations
- Only requires sudo for system-level operations (systemd, cron)

## Migration from Old Scripts

If you previously used the old scripts with a deploy user:

1. **Files owned by deploy user**: Change ownership to your current user:

   ```bash
   sudo chown -R $(whoami):$(whoami) /opt/traefik /opt/prometheus /opt/grafana /opt/cloudflared /opt/uptime-kuma
   ```

2. **Systemd service**: The service will now run as your current user instead of the deploy user

3. **Cron jobs**: Will run as your current user instead of the deploy user

4. **Docker group**: Make sure your current user is in the docker group:
   ```bash
   sudo usermod -aG docker $(whoami)
   # Then log out and back in for the change to take effect
   ```

## Security Considerations

- The current user should have appropriate permissions for the deployment
- Ensure the current user is in the docker group
- SSH access should be configured for the current user
- Consider using SSH keys instead of password authentication
- The scripts still require sudo for system-level operations

## Testing

Both scripts have been syntax-checked and are ready for use. The changes maintain all functionality while simplifying the user management aspect of the deployment process.
