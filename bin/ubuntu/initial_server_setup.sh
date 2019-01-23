#!/bin/bash
set -euo pipefail

########################
### SCRIPT VARIABLES ###
########################

# Name of the user to create and grant sudo privileges
USERNAME=k

# Whether to copy over the root user's `authorized_keys` file to the new sudo
# user.
COPY_AUTHORIZED_KEYS_FROM_ROOT=false

# Additional public keys to add to the new sudo user
# OTHER_PUBLIC_KEYS_TO_ADD=(
#     "ssh-rsa AAAAB..."
#     "ssh-rsa AAAAB..."
# )
OTHER_PUBLIC_KEYS_TO_ADD=(
  "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDI8/TqvoQiBEZ0UTl8f8S7cd5NoZ862ep7z7VDgGNsObS5b3c36R/VXjl9ksVN9DW5hvlYUCbyk7fFpR30DK0nTssSRmtbKTfAdoeHFBmTbBiJtf1bfMAmqpFdqzlC/5FZZLaBy0pNBjw/n+zA3vT1vuTWwpFrIDjLNhBEqqq7taew4eTaDWitAIKDA3ifMO+PhpQ7i3RmGWfmxbdgWQ6BGPyYjbFAkB9IK7KfBxSgJahHu7N2PfQ+Vu+4e8juBpYqAc3+OL/9QLugJ8iNMRyHfTv+ZOpCu9dsrbwk0JwCAcEih6inbC5ywAJa0+0yrVWrQ1Z5Qf5nzNYpgykDlZYywJHfzoHVW6VcL4EkiMhs/n4RQyIiBKVSHYso42NuddDrau6T/RNnFyotaOw71VJs14By8Ya5Bbh/dwLMZsFRG0jzyVvjJ9vcqjqQCFPCiSTN0frQYlaJV5Qs0Ah2voq76AQTFkiA6/U7lX9jla0AQ2HcE9CBX4POZJSKkFnVsLZ7/kmJUnMO6cNWIf5UBDA0qeNl1V3OgnjXHG8xLnUleAY9/oBm5tZP01Vh8EHjWYL0e0Ee8MHbmiJNHtB5y4SXyOJBTBp3fqsVnrbD5rOXt+UOJFo0iZ5OrxMEBoIWqapNDsnruVJf+PwqEZVrO6Gox/nJAkDe/db+Eg0gH/FXnw== ksaynice@gmail.com"
)

####################
### SCRIPT LOGIC ###
####################

# Add sudo user and grant privileges
useradd --create-home --shell "/bin/bash" --groups sudo "${USERNAME}"

# Check whether the root account has a real password set
encrypted_root_pw="$(grep root /etc/shadow | cut --delimiter=: --fields=2)"

if [ "${encrypted_root_pw}" != "*" ]; then
    # Transfer auto-generated root password to user if present
    # and lock the root account to password-based access
    echo "${USERNAME}:${encrypted_root_pw}" | chpasswd --encrypted
    passwd --lock root
else
    # Delete invalid password for user if using keys so that a new password
    # can be set without providing a previous value
    passwd --delete "${USERNAME}"
fi

# Expire the sudo user's password immediately to force a change
chage --lastday 0 "${USERNAME}"

# Create SSH directory for sudo user
home_directory="$(eval echo ~${USERNAME})"
mkdir --parents "${home_directory}/.ssh"

# Copy `authorized_keys` file from root if requested
if [ "${COPY_AUTHORIZED_KEYS_FROM_ROOT}" = true ]; then
    cp /root/.ssh/authorized_keys "${home_directory}/.ssh"
fi

# Add additional provided public keys
for pub_key in "${OTHER_PUBLIC_KEYS_TO_ADD[@]}"; do
    echo "${pub_key}" >> "${home_directory}/.ssh/authorized_keys"
done

# Adjust SSH configuration ownership and permissions
chmod 0700 "${home_directory}/.ssh"
chmod 0600 "${home_directory}/.ssh/authorized_keys"
chown --recursive "${USERNAME}":"${USERNAME}" "${home_directory}/.ssh"

# Disable root SSH login with password
sed --in-place 's/^PermitRootLogin.*/PermitRootLogin prohibit-password/g' /etc/ssh/sshd_config
if sshd -t -q; then
    systemctl restart sshd
fi

# Add exception for SSH and then enable UFW firewall
# ufw allow OpenSSH
# ufw --force enable
