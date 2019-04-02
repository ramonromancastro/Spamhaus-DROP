#!/bin/bash

# Spamhaus-DROP.sh is a bash function to download Spamhaus DROP lists
# (https://www.spamhaus.org/drop/) and modify them to use in conjuntion
# with Squid.
#
# Copyright (C) 2018 Ramon Roman Castro ramonromancastro@gmail.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

#
# Default configuration variables (You can modify them)
#

# Spamhaus list
# All list from Spamhaus DROP (https://www.spamhaus.org/drop/) that you want to download. Format ("LIST_URI_1" ... "LIST_URI_N")
# Spamhaus_Lists=

# Destination directory for SQUID ACLs and lists
# Spamhaus_Destination_Path=/etc/squid/Spamhaus

# Spamhaus Squid ACL filename
# Spamhaus_Squid_ACL=Spamhaus.acl

# Spamhaus integration
# Spamhaus_Squid_Integration=true
# Spamhaus_Smtp_Integration=false

# SMTP configuration
# Mail client used is mailx
# Spamhaus_Smtp_Smtp=
# Spamhaus_Smtp_From=
# Spamhaus_Smtp_Username=
# Spamhaus_Smtp_Password=
# Spamhaus_Smtp_To=
# Spamhaus_Smtp_Parameters=

#
# Constants
#

Spamhaus_Version=1.2
Spamhaus_Config=Spamhaus-DROP.conf

#
# Functions
#

email(){
	if [[ $Spamhaus_Smtp_Integration =~ true ]]; then
		echo -e "An error occurred while running Spamhaus-DROP.sh (`hostname -f`):\n\n$1" | mailx -v -r "$Spamhaus_Smtp_From" -s "Spamhaus-DROP: Error" $Spamhaus_Smtp_Parameters $Spamhaus_Smtp_To > /dev/null 2>&1
	fi
}

msg(){
	echo -e $1
}

error(){
	ERROR_COLOR="\033[91m"
	DEFAULT_COLOR="\033[39m"
	echo -en $ERROR_COLOR
	msg "$1"
	echo -en $DEFAULT_COLOR
	email "$1"
	exit 1
}

#
# Main code
#

msg "Spamhaus-DROP v$Spamhaus_Version\nCopyright (c) 2018 Ramón Román Castro <ramonromancastro@gmail.com>\n"

# Enable case insensitive regex in bash
shopt -s nocasematch

# Verifying configuration file
if [ -f $Spamhaus_Config ]; then
	msg "Loading $Spamhaus_Config ..."
	. $Spamhaus_Config
else
	error "$Spamhaus_Config not found!"
fi

# Detect squid installation
squid -v > /dev/null 2>1 || error "squid not found!"

# Verifying destination directory
if [ ! -d $Spamhaus_Destination_Path ]; then
	msg "Creating $Spamhaus_Destination_Path directory ..."
	mkdir -p $Spamhaus_Destination_Path || error "Error creating $Spamhaus_Destination_Path directory"
fi

# Creating Squid ACL header
msg "Creating Squid ACL header..."
Spamhaus_Destination_ACL=$Spamhaus_Destination_Path/$Spamhaus_Squid_ACL
echo "# Spamhaus DROP Lists UT1 (The Spamhaus Don't Route Or Peer Lists)" > $Spamhaus_Destination_ACL
echo "# Generated automatically by Spamhaus-DROP.sh" >> $Spamhaus_Destination_ACL
echo "# IMPORTANT: DO NOT EDIT MANUALLY!" >> $Spamhaus_Destination_ACL
echo "# Date: `date`" >> $Spamhaus_Destination_ACL

# Downloading Spamhaus lists
for Spamhaus_List_Uri in "${Spamhaus_Lists[@]}"; do
	Spamhaus_List_Filename=$(basename $Spamhaus_List_Uri)
	Spamhaus_List_OnlyFilename=${Spamhaus_List_Filename%.*}
	Spamhaus_Destination_File=$Spamhaus_Destination_Path/$Spamhaus_List_Filename
	
	msg "Downloading $Spamhaus_List_Uri ..."
	wget --no-check-certificate -q -O $Spamhaus_Destination_File $Spamhaus_List_Uri || error "Error downloading $Spamhaus_List_Uri"
	
	msg "Parsing $Spamhaus_List_Filename ..."
	sed -ri "s/^([^;]+)(.*)$/\1/gi; s/^\n//gi; s/;/#/g" $Spamhaus_Destination_File || error "Error parsing $Spamhaus_Destination_File"
	
	msg "Creating Squid ACL list Spamhaus_$Spamhaus_List_OnlyFilename ..."
	echo "acl Spamhaus_$Spamhaus_List_OnlyFilename dst -n \"$Spamhaus_Destination_File\"" >> $Spamhaus_Destination_ACL
	echo "http_access deny Spamhaus_$Spamhaus_List_OnlyFilename" >> $Spamhaus_Destination_ACL
	
done

# Reloading Squid
if [[ $Spamhaus_Squid_Integration =~ true ]]; then
	msg "Reloading squid ..."
	if ps 1 | grep "systemd" > /dev/null 2>&1; then
		systemctl reload squid > /dev/null 2>&1 || error "Error reloading squid"
	else
		service squid reload > /dev/null 2>&1 || error "Error reloading squid"
	fi
fi

msg "\nExecution success!"