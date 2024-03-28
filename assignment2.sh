#!/bin/bash


# Update netplan configuration
# Check if netplan is installed
if ! command -v netplan &> /dev/null; then
	echo "Installing netplan..."
	# Install netplan
	sudo apt-get update > /dev/null 2>&1 && sudo apt upgrade  > /dev/null  2>&1 && sudo apt-get install -y netplan > /dev/null 2>&1 
	# Check if installation was successful
	if [ $? -ne 0 ]; then
		    echo "Failed to install Netplan"
		    exit 1
	fi
fi

# set the new IP address for eth1
INT_NAME="eth1"  # Network interface for the 192.168.16 network
IP_ADDR="192.168.16.21"
sed -i '/'$INT_NAME':/,/  addresses:/s/\(  addresses: \).*/\1['$IP_ADDR'\/24]/' /etc/netplan/50-cloud-init.yaml

# Apply the netplan changes
sudo netplan apply
echo "Netplan configuration updated successfully."

# Update /etc/hosts
# Backup the original /etc/hosts
cp "/etc/hosts" "/etc/hosts.bak" &>/dev/null

# Remove existing entry for server1 (if any)
sudo sed -i '/server1/d' "/etc/hosts"

# Add new entry for server1
echo -e "$IP_ADDR\t server1" | sudo tee -a "/etc/hosts" >/dev/null
echo "/etc/hosts file updated successfully."

echo "Network configuration and /etc/hosts file updated successfully."


# Install and configure Apache2
echo "** Apache2 Installation **"

# Check if Apache2 is already installed
if dpkg-query -l apache2 >/dev/null 2>&1; then
    echo "Apache2 is already installed."
else
    echo "Installing Apache2..."
    if sudo apt install apache2 -y > /dev/null 2>&1 ; then
        echo "Apache2 installed successfully and running in its default configuration."
    else
        echo "Error installing Apache2!"
        exit 1
    fi
fi

# Install and configure Squid
echo "** Squid Installation **"
# Check if Squid is already installed
if dpkg-query -l squid >/dev/null 2>&1; then
    echo "Squid is already installed."
else
    echo "Installing Squid..."
    if sudo apt install squid -y >/dev/null 2>&1; then
        echo "Squid installed successfully and is running in its default configuration."
    else
        echo "Error installing Squid!"
        exit 1
    fi
fi

echo "Software installation completed."

# Function to configure ufw firewall rules
configure_ufw_rules() {
    #  network interface for management
    mgmt_if="eth2"

    # Validate if mgmt interface exists
    if ! ip addr show "$mgmt_if" &> /dev/null; then
    echo "Error: Management interface '$mgmt_if' not found!"
    exit 1
    fi


  # Check if ufw is already enabled
  if ! sudo ufw status | grep -q "Status: active"; then
    echo "** Firewall **"
    echo "Enabling ufw firewall..."
    if sudo ufw enable; then
      echo "ufw firewall enabled successfully."
    else
      echo "Error enabling ufw firewall!"
      exit 1
    fi
  else
    echo "** Firewall **"
    echo "ufw firewall already enabled."
  fi

  # Check existing SSH rule for mgmt interface
  if ! sudo ufw status verbose | grep -q "SRC INTERFACE $mgmt_if  DST PORT     22"; then
    echo "** SSH Rule **"
    echo "Adding rule to allow SSH on interface '$mgmt_if'..."
    if sudo ufw allow in on "$mgmt_if" to any port 22 proto tcp; then
      echo "SSH rule for '$mgmt_if' added successfully."
    else
      echo "Error adding SSH rule for '$mgmt_if'!"
      exit 1
    fi
  else
    echo "** SSH Rule **"
    echo "SSH rule for '$mgmt_if' already exists."
  fi

  # Check existing HTTP rule
  if ! sudo ufw status verbose | grep -q "PORT     80"; then
    echo "** HTTP Rule **"
    echo "Adding rule to allow HTTP traffic..."
    if sudo ufw allow in to any port 80 proto tcp comment "Allow HTTP traffic"; then
      echo "HTTP rule added successfully."
    else
      echo "Error adding HTTP rule!"
      exit 1
    fi
  else
    echo "** HTTP Rule **"
    echo "HTTP rule already exists."
  fi

  # Check existing web proxy rule (assuming port 8080)
  if ! sudo ufw status verbose | grep -q "PORT     8080"; then
    echo "** Web Proxy Rule **"
    echo "Adding rule to allow web proxy traffic on port 8080..."
    if sudo ufw allow in to any port 8080 proto tcp comment "Allow web proxy traffic"; then
      echo "Web proxy rule added successfully."
    else
      echo "Error adding web proxy rule!"
      exit 1
    fi
  else
    echo "** Web Proxy Rule **"
    echo "Web proxy rule already exists."
  fi
}


# Call the configuration function
configure_ufw_rules
echo "ufw firewall configuration completed."


users=("dennis" "aubrey" "captain" "snibbles" "brownie" "scooter" "sandy" "perrier" "cindy" "tiger" "yoda")
for user in "${users[@]}"; do
    # Check if user already exists
    id "$user" &>/dev/null && { echo "$user already exists"; continue; }

    # Create the user account
    sudo useradd -m -d /home/$user  -s /bin/bash "$user" || exit 1
    echo "Created user $user"

    # Set up SSH for the user
    ssh_dir="/home/$user/.ssh"
    sudo mkdir -p "$ssh_dir" || exit 1

    sudo ssh-keygen -t rsa -b 4096 -f /home/$user/.ssh/id_rsa -q -N ""
    sudo ssh-keygen -t ed25519 -f /home/$user/.ssh/id_ed25519 -q -N ""

    echo "${USERS[$user]}" | sudo tee -a /home/$user/.ssh/authorized_keys >/dev/null
    sudo cp /home/$user/.ssh/id_rsa.pub /home/$user/.ssh/authorized_keys
    sudo cp /home/$user/.ssh/id_ed25519.pub /home/$user/.ssh/authorized_keys

    sudo chown -R $user:$user /home/$user/.ssh
    sudo chmod 700 /home/$user/.ssh
    sudo chmod 644 /home/$user/.ssh/authorized_keys


    echo "Added SSH public keys for user $user"

    # Set sudo permissions for the dennis user
    if [ "$user" == "dennis" ]; then
        if ! sudo grep -q "^$user ALL=(ALL) NOPASSWD: ALL" /etc/sudoers; then
            echo "$user ALL=(ALL) NOPASSWD: ALL" | sudo tee -a /etc/sudoers.d/$user >/dev/null || exit 1
            sudo chmod 440 /etc/sudoers.d/$user
            echo "Set sudo permissions for user $user"
        fi
    fi
done

echo "User accounts created and configured successfully."
