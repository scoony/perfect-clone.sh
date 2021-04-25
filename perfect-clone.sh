#!/bin/bash

#### Config
mount_points="/mnt"


#### Autoupdater
remote_folder="https://raw.githubusercontent.com/scoony/perfect-clone.sh/main/"
local_folder="/opt/scripts/perfect-clone/"
 
source <(curl -s https://raw.githubusercontent.com/scoony/perfect-clone.sh/main/extras/update-files)
 
for current_file in $file{001..999}; do
  remote_md5=`curl -s ${remote_folder}$current_file | md5sum | cut -f1 -d" "`
  local_md5=`md5sum ${local_folder}$current_file 2>/dev/null | cut -f1 -d" "`
  if [[ $remote_md5 == $local_md5 ]]; then
    echo "$current_file : No upgrade required"
  else
    echo "$current_file : Upgrade required"
    wget --quiet "${remote_folder}${current_file}" -O "${local_folder}${current_file}"
    if [[ "$current_file" =~ ".sh" ]]; then
      chmod +x "${local_folder}${current_file}"
    fi
    echo "Update Done"
  fi
done

#### Generate local DB
updatedb --output ${local_folder}source.db --database-root ${mount_points}

#### Display DB infos
locate -d ${local_folder}source.db -S

#### Get remote DB
